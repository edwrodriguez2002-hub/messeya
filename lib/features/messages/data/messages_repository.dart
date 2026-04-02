import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:stream_chat_flutter_core/stream_chat_flutter_core.dart' as stream;

import '../../../core/config/push_config.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/services/cloudinary_media_service.dart';
import '../../../core/services/stream_chat_service.dart';
import '../../../shared/models/message.dart';

final messagesRepositoryProvider = Provider<MessagesRepository>((ref) {
  return MessagesRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseAuthProvider),
    ref.watch(cloudinaryMediaServiceProvider),
    ref.watch(streamChatServiceProvider),
  );
});

final chatMessagesProvider = StreamProvider.family<List<Message>, String>((ref, chatId) {
  return ref.watch(messagesRepositoryProvider).watchMessages(chatId);
});

class MessagesRepository {
  MessagesRepository(
    this._firestore,
    this._auth,
    this._cloudinary,
    this._streamChatService,
  );

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final CloudinaryMediaService _cloudinary;
  final StreamChatService _streamChatService;

  CollectionReference<Map<String, dynamic>> get _chats => _firestore.collection('chats');
  CollectionReference<Map<String, dynamic>> get _desktopOutbox => _firestore.collection('desktop_outbox');
  stream.StreamChatClient? get _streamClient => _streamChatService.client;
  // Firestore vuelve a ser la fuente principal para mensajeria en cliente.
  bool get _useStream => false;

  Stream<List<Message>> watchMessages(String chatId) {
    if (_useStream) {
      return _watchStreamMessages(chatId);
    }

    final userId = _auth.currentUser?.uid ?? '';
    return _chats.doc(chatId).collection('messages')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
            .map(Message.fromDoc)
            .where((m) => !m.deletedFor.contains(userId))
            .toList();
        });
  }

  Stream<List<Message>> _watchStreamMessages(String chatId) async* {
    final channel = await _resolveStreamChannel(chatId, watch: true);
    yield* channel.state!.channelStateStream.map((channelState) {
      final items = (channelState.messages ?? const <stream.Message>[])
          .where((message) => message.shadowed != true)
          .map((message) => _mapStreamMessage(
                chatId: chatId,
                message: message,
                reads: channelState.read ?? const <stream.Read>[],
              ))
          .toList()
        ..sort((a, b) {
          final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });
      return items;
    });
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchPendingDesktopOutbox(String userId) {
    return _desktopOutbox
        .where('ownerUid', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) => snapshot.docs);
  }

  Future<void> processDesktopOutboxItem(QueryDocumentSnapshot<Map<String, dynamic>> document) async {
    final data = document.data();
    final type = data['type'] as String? ?? 'text';
    
    if (type == 'text' || type == 'mixed') {
      await sendEmailStyleMessage(
        chatId: data['chatId'] as String? ?? '',
        subject: data['subject'] as String? ?? '',
        body: data['text'] as String? ?? '',
        files: [],
        priority: data['priority'] as String? ?? 'normal',
      );
    }

    await document.reference.update({
      'status': 'processed',
      'processedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> sendEmailStyleMessage({
    required String chatId,
    required String subject,
    required String body,
    required List<File> files,
    String priority = 'normal',
    Message? replyTo,
    String replySenderName = '',
  }) async {
    if (_useStream) {
      await _sendStreamMessage(
        chatId: chatId,
        subject: subject,
        body: body,
        files: files,
        priority: priority,
        replyTo: replyTo,
        replySenderName: replySenderName,
      );
      return;
    }

    final user = _auth.currentUser;
    if (user == null) return;
    final userId = user.uid;
    final messageRef = _chats.doc(chatId).collection('messages').doc();
    final now = FieldValue.serverTimestamp();

    final chatDoc = await _chats.doc(chatId).get();
    final chatData = chatDoc.data() ?? {};
    final members = List<String>.from(chatData['members'] ?? []);

    final batch = _firestore.batch();
    
    batch.set(messageRef, {
      ..._baseMessageData(
        messageId: messageRef.id,
        chatId: chatId,
        userId: userId,
        type: files.isNotEmpty ? 'mixed' : 'text',
        text: body,
        now: now,
      ),
      'subject': subject,
      'priority': priority,
      'status': 'sent',
      'replyToMessageId': replyTo?.id ?? '',
      'replyToText': replyTo?.text ?? '',
      'replyToSenderName': replySenderName,
    });

    final updates = <String, dynamic>{
      'lastMessage': subject.isNotEmpty ? subject : (body.isNotEmpty ? body : 'Archivo adjunto'),
      'lastMessageAt': now,
      'lastMessageSenderId': userId,
    };

    for (final memberId in members) {
      if (memberId != userId) {
        updates['unreadCounts.$memberId'] = FieldValue.increment(1);
      }
    }

    batch.update(_chats.doc(chatId), updates);
    await batch.commit();
    await _notifyPushBackend(
      chatId: chatId,
      messageId: messageRef.id,
    );

    if (files.isNotEmpty) {
      _processFilesAndFinalize(chatId, messageRef.id, files);
    }
  }

  Future<void> _sendStreamMessage({
    required String chatId,
    required String subject,
    required String body,
    required List<File> files,
    required String priority,
    Message? replyTo,
    String replySenderName = '',
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final client = _streamClient;
    if (client == null || client.state.currentUser == null) {
      throw StateError(
        'Stream Chat no esta conectado. Verifica que el token provider este activo y vuelve a intentar.',
      );
    }

    final channel = await _resolveStreamChannel(chatId, watch: true);
    final attachments = await _buildStreamAttachments(files, channel);
    final effectiveType = _resolveMessageType(files, body);

    final message = stream.Message(
      text: body.trim(),
      attachments: attachments,
      quotedMessageId: replyTo?.id.isNotEmpty == true ? replyTo!.id : null,
      extraData: {
        'subject': subject.trim(),
        'priority': priority,
        'chatId': chatId,
        'messageType': effectiveType,
        'replyToText': replyTo?.text ?? '',
        'replyToSenderName': replySenderName,
        'replyToType': replyTo?.type ?? '',
      },
    );

    try {
      await channel.sendMessage(message).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw TimeoutException(
            'Stream Chat tardo demasiado en enviar el mensaje.',
          );
        },
      );
    } on TimeoutException catch (_) {
      throw StateError(
        'No se pudo enviar el mensaje a tiempo. Revisa la conexion de Stream y vuelve a intentar.',
      );
    }
  }

  Future<List<stream.Attachment>> _buildStreamAttachments(List<File> files, stream.Channel channel) async {
    final attachments = <stream.Attachment>[];

    for (final file in files) {
      final attachmentFile = stream.AttachmentFile(
        path: file.path,
        size: await file.length(),
        name: path.basename(file.path),
      );
      final type = _getFileType(file.path);
      final streamType = _toStreamAttachmentType(type);

      String? url;
      if (streamType == 'image') {
        final response = await channel.sendImage(attachmentFile);
        url = response.file;
      } else {
        final response = await channel.sendFile(attachmentFile);
        url = response.file;
      }

      attachments.add(
        stream.Attachment(
          type: streamType,
          assetUrl: url,
          imageUrl: streamType == 'image' ? url : null,
          title: path.basename(file.path),
        ),
      );
    }

    return attachments;
  }

  String _toStreamAttachmentType(String type) {
    switch (type) {
      case 'image':
        return 'image';
      case 'video':
        return 'video';
      case 'audio':
        return 'audio';
      default:
        return 'file';
    }
  }

  Future<void> _processFilesAndFinalize(String chatId, String msgId, List<File> files) async {
    try {
      List<MessageAttachment> attachments = [];
      for (var file in files) {
        final fileName = path.basename(file.path);
        final upload = await _cloudinary.uploadRawAsset(
          file: file,
          fileName: fileName,
          folder: 'messeya/attachments/$chatId',
        );
        attachments.add(MessageAttachment(url: upload.secureUrl, name: fileName, type: _getFileType(file.path)));
      }

      await _chats.doc(chatId).collection('messages').doc(msgId).update({
        'attachments': attachments.map((a) => a.toMap()).toList(),
      });
    } catch (e) {
      debugPrint('Error procesando archivos: $e');
    }
  }

  Future<void> markMessagesAsSeen({required String chatId, required List<Message> messages}) async {
    if (_useStream) {
      final channel = await _resolveStreamChannel(chatId, watch: true);
      await channel.markRead();
      return;
    }

    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    final batch = _firestore.batch();
    var hasChanges = false;
    final now = DateTime.now();

    for (var m in messages) {
      if (m.senderId != userId && !m.seenBy.contains(userId)) {
        batch.update(_chats.doc(chatId).collection('messages').doc(m.id), {
          'seenBy': FieldValue.arrayUnion([userId]),
          'deliveredTo': FieldValue.arrayUnion([userId]),
          'seenAt.$userId': Timestamp.fromDate(now),
          'deliveredAt.$userId': Timestamp.fromDate(now),
        });
        hasChanges = true;
      }
    }
    
    if (hasChanges) {
      await batch.commit();
      await _chats.doc(chatId).update({'unreadCounts.$userId': 0});
    }
  }

  String _getFileType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'webp'].contains(ext)) return 'image';
    if (['mp4', 'mov'].contains(ext)) return 'video';
    return 'file';
  }

  Map<String, dynamic> _baseMessageData({
    required String messageId, required String chatId, required String userId,
    required String type, required String text, required FieldValue now,
  }) {
    return {
      'id': messageId, 'chatId': chatId, 'senderId': userId, 'text': text,
      'createdAt': now, 'type': type, 'seenBy': [userId], 'deliveredTo': [userId],
      'attachments': [], 'reactions': {}, 'subject': '', 'priority': 'normal',
      'mediaOpenedBy': [userId], 'deletedForAll': false, 'deletedFor': [], 'replyToMessageId': '',
      'replyToText': '', 'replyToSenderName': '', 'replyToType': '',
      'seenAt': {userId: Timestamp.now()},
      'deliveredAt': {userId: Timestamp.now()},
    };
  }

  // Métodos de conveniencia
  Future<void> sendTextMessage({required String chatId, required String text, String subject = '', Message? replyTo, String replySenderName = ''}) async => 
    sendEmailStyleMessage(chatId: chatId, subject: subject, body: text, files: [], replyTo: replyTo, replySenderName: replySenderName);

  Future<void> sendAttachmentMessage({required String chatId, required String type, File? file, String? fileName, String text = '', String subject = '', bool viewOnce = false, Message? replyTo, String replySenderName = ''}) async => 
    sendEmailStyleMessage(chatId: chatId, subject: subject, body: text, files: file != null ? [file] : [], replyTo: replyTo, replySenderName: replySenderName);

  Future<void> sendVoiceMessage({required String chatId, required File audioFile, required int durationMs, Message? replyTo, String replySenderName = ''}) async => 
    sendEmailStyleMessage(chatId: chatId, subject: "Nota de voz", body: "", files: [audioFile], replyTo: replyTo, replySenderName: replySenderName);

  Future<void> resetUnreadCount(String chatId) async {
    if (_useStream) {
      final channel = await _resolveStreamChannel(chatId, watch: true);
      await channel.markRead();
      return;
    }

    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    await _chats.doc(chatId).update({'unreadCounts.$userId': 0});
  }

  Future<void> markRecentMessagesAsDelivered({required String chatId, String? viewerUserId}) async {
    if (_useStream) {
      return;
    }

    final userId = viewerUserId ?? _auth.currentUser?.uid;
    if (userId == null) return;
    
    final messagesSnap = await _chats.doc(chatId).collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .get();

    final batch = _firestore.batch();
    bool hasChanges = false;
    final now = DateTime.now();

    for (var doc in messagesSnap.docs) {
      final deliveredTo = List<String>.from(doc.data()['deliveredTo'] ?? []);
      if (!deliveredTo.contains(userId)) {
        batch.update(doc.reference, {
          'deliveredTo': FieldValue.arrayUnion([userId]),
          'deliveredAt.$userId': Timestamp.fromDate(now),
        });
        hasChanges = true;
      }
    }

    if (hasChanges) await batch.commit();
  }

  Future<void> forwardMessage({required String targetChatId, required Message originalMessage}) async {
    if (_useStream) {
      final channel = await _resolveStreamChannel(targetChatId, watch: true);
      await channel.sendMessage(
        stream.Message(
          text: originalMessage.text,
          attachments: originalMessage.attachments
              .map(
                (attachment) => stream.Attachment(
                  type: _toStreamAttachmentType(attachment.type),
                  title: attachment.name,
                  assetUrl: attachment.type == 'image' ? null : attachment.url,
                  imageUrl: attachment.type == 'image' ? attachment.url : null,
                ),
              )
              .toList(),
          extraData: {
            'subject': originalMessage.subject,
            'priority': originalMessage.priority,
            'forwardedFromMessageId': originalMessage.id,
            'forwardedFromChatId': originalMessage.chatId,
            'forwardedFromSenderName': originalMessage.forwardedFromSenderName,
            'messageType': originalMessage.type,
          },
        ),
      );
      return;
    }

    final user = _auth.currentUser;
    if (user == null) return;
    final msgRef = _chats.doc(targetChatId).collection('messages').doc();
    await msgRef.set({
      ...originalMessage.toMap(),
      'id': msgRef.id,
      'chatId': targetChatId,
      'senderId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'seenBy': [user.uid],
      'deliveredTo': [user.uid],
    });
  }

  Future<void> deleteMessageForMe({required String chatId, required String messageId}) async {
    if (_useStream) {
      throw UnimplementedError('Eliminar solo para mi aun no esta disponible en Stream.');
    }

    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    await _chats.doc(chatId).collection('messages').doc(messageId).update({
      'deletedFor': FieldValue.arrayUnion([userId]),
    });
  }

  Future<void> deleteMessageForEveryone({required String chatId, required Message message}) async {
    if (_useStream) {
      await _streamClient!.deleteMessage(message.id, hard: false);
      return;
    }

    await _chats.doc(chatId).collection('messages').doc(message.id).update({
      'text': '🚫 Este mensaje fue eliminado',
      'attachments': [],
      'deletedForAll': true,
    });
  }

  Future<stream.Channel> _resolveStreamChannel(
    String chatId, {
    bool watch = false,
  }) async {
    final client = await _streamChatService.requireConnectedClient();

    final channel = client.channel('messaging', id: chatId);

    if (watch && channel.state == null) {
      try {
        await channel.watch().timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException(
              'Stream Chat tardo demasiado en cargar el canal.',
            );
          },
        );
      } on TimeoutException catch (_) {
        throw StateError(
          'No se pudo abrir el canal de Stream. Asegurate de que el backend local del token este corriendo.',
        );
      }
    }

    return channel;
  }

  Message _mapStreamMessage({
    required String chatId,
    required stream.Message message,
    required List<stream.Read> reads,
  }) {
    final createdAt = message.createdAt.toLocal();
    final senderId = message.user?.id ?? '';
    final seenReads = reads.where((read) {
      final lastRead = read.lastRead;
      return read.user.id != senderId && !lastRead.isBefore(createdAt);
    }).toList();
    final deliveredReads = reads.where((read) {
      final lastDelivered = read.lastDeliveredAt;
      if (lastDelivered == null) return false;
      return read.user.id != senderId && !lastDelivered.isBefore(createdAt);
    }).toList();

    final attachments = message.attachments
        .map(
          (attachment) => MessageAttachment(
            url: attachment.imageUrl ?? attachment.assetUrl ?? '',
            name: attachment.title ?? _attachmentFileName(attachment) ?? 'archivo',
            type: _normalizeAttachmentType(attachment.type?.toString()),
          ),
        )
        .where((attachment) => attachment.url.isNotEmpty)
        .toList();

    final quoted = message.quotedMessage;
    final extraData = message.extraData;
    final subject = (extraData['subject'] as String? ?? '').trim();
    final priority = (extraData['priority'] as String? ?? 'normal').trim();
    final type = ((extraData['messageType'] as String?) ?? _resolveTypeFromAttachments(attachments, message.text ?? '')).trim();

    return Message(
      id: message.id,
      chatId: chatId,
      senderId: senderId,
      text: message.text ?? '',
      createdAt: createdAt,
      type: type.isEmpty ? 'text' : type,
      seenBy: <String>[
        if (senderId.isNotEmpty) senderId,
        ...seenReads.map((read) => read.user.id),
      ],
      deliveredTo: <String>[
        if (senderId.isNotEmpty) senderId,
        ...deliveredReads.map((read) => read.user.id),
      ],
      deletedFor: const [],
      deletedForAll: message.type == 'deleted' || message.deletedAt != null,
      attachmentUrl: attachments.isNotEmpty ? attachments.first.url : '',
      fileName: attachments.isNotEmpty ? attachments.first.name : '',
      attachments: attachments,
      reactions: _mapStreamReactions(message),
      replyToMessageId: quoted?.id ?? '',
      replyToText: quoted?.text ?? (extraData['replyToText'] as String? ?? ''),
      replyToSenderName: quoted?.user?.name ?? (extraData['replyToSenderName'] as String? ?? ''),
      replyToType: (extraData['replyToType'] as String? ?? '').trim(),
      voiceDurationMs: 0,
      pollQuestion: '',
      pollOptions: const [],
      editedAt: message.updatedAt.toLocal(),
      forwardedFromMessageId: (extraData['forwardedFromMessageId'] as String? ?? '').trim(),
      forwardedFromChatId: (extraData['forwardedFromChatId'] as String? ?? '').trim(),
      forwardedFromSenderName: (extraData['forwardedFromSenderName'] as String? ?? '').trim(),
      starredBy: const [],
      viewOnce: false,
      mediaOpenedBy: const [],
      subject: subject,
      priority: priority.isEmpty ? 'normal' : priority,
      seenAt: {
        for (final read in seenReads) read.user.id: read.lastRead.toLocal(),
      },
      deliveredAt: {
        for (final read in deliveredReads) read.user.id: read.lastDeliveredAt!.toLocal(),
      },
      isEncrypted: false,
    );
  }

  Map<String, List<String>> _mapStreamReactions(stream.Message message) {
    final grouped = <String, List<String>>{};
    for (final reaction in message.latestReactions ?? const <stream.Reaction>[]) {
      final type = reaction.type;
      final userId = reaction.user?.id ?? '';
      if (type.isEmpty || userId.isEmpty) continue;
      grouped.putIfAbsent(type, () => <String>[]).add(userId);
    }
    return grouped;
  }

  String? _attachmentFileName(stream.Attachment attachment) {
    final url = attachment.imageUrl ?? attachment.assetUrl ?? '';
    if (url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.pathSegments.isEmpty) return null;
    return uri.pathSegments.last;
  }

  String _normalizeAttachmentType(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'image':
        return 'image';
      case 'video':
        return 'video';
      case 'audio':
        return 'audio';
      default:
        return 'file';
    }
  }

  String _resolveTypeFromAttachments(List<MessageAttachment> attachments, String text) {
    if (attachments.length > 1) return 'mixed';
    if (attachments.length == 1) return attachments.first.type;
    return text.trim().isNotEmpty ? 'text' : 'file';
  }

  String _resolveMessageType(List<File> files, String body) {
    if (files.length > 1) return 'mixed';
    if (files.length == 1) return _getFileType(files.first.path);
    return body.trim().isNotEmpty ? 'text' : 'file';
  }

  Future<void> _notifyPushBackend({
    required String chatId,
    required String messageId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final url = PushConfig.messagePushUrl.trim();
    if (url.isEmpty) return;

    try {
      final idToken = await user.getIdToken();
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'chatId': chatId,
              'messageId': messageId,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'Push backend respondio con ${response.statusCode}: ${response.body}',
        );
      }
    } catch (error) {
      debugPrint('No se pudo avisar al backend de push: $error');
    }
  }
}
