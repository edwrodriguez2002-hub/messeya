import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../../../core/config/backend_config.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/services/cloudinary_media_service.dart';
import '../../../shared/models/message.dart';

final messagesRepositoryProvider = Provider<MessagesRepository>((ref) {
  return MessagesRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseAuthProvider),
    ref.watch(cloudinaryMediaServiceProvider),
  );
});

final chatMessagesProvider =
    StreamProvider.family<List<Message>, String>((ref, chatId) {
  return ref.watch(messagesRepositoryProvider).watchMessages(chatId);
});

class MessagesRepository {
  MessagesRepository(this._firestore, this._auth, this._cloudinary);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final CloudinaryMediaService _cloudinary;

  CollectionReference<Map<String, dynamic>> get _chats =>
      _firestore.collection('chats');

  Stream<List<Message>> watchMessages(String chatId) {
    return _chats
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Message.fromDoc).toList());
  }

  Future<void> sendMultiAttachmentMessage({
    required String chatId,
    required List<File> files,
    required String text,
    String subject = '',
    String priority = 'normal',
    Message? replyTo,
    String replySenderName = '',
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final attachments = <MessageAttachment>[];
    for (final file in files) {
      final fileName = path.basename(file.path);
      final type = _isImage(file.path)
          ? 'image'
          : (_isVideo(file.path) ? 'video' : 'file');
      final upload = await _uploadToCloudinary(
        type,
        file,
        null,
        fileName,
        chatId,
      );
      attachments.add(
        MessageAttachment(
          url: upload.secureUrl,
          name: fileName,
          type: type,
        ),
      );
    }

    final messageType =
        attachments.length == 1 ? attachments.first.type : 'mixed';
    await _createMessage(
      chatId: chatId,
      type: messageType,
      text: text.trim(),
      subject: subject.trim(),
      priority: priority,
      replyTo: replyTo,
      replySenderName: replySenderName,
      attachments: attachments,
    );
  }

  Future<void> sendTextMessage({
    required String chatId,
    required String text,
    String subject = '',
    String priority = 'normal',
    Message? replyTo,
    String replySenderName = '',
    String forwardedFromSenderName = '',
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && subject.isEmpty) return;

    if (_auth.currentUser == null) {
      throw Exception('No hay una sesión activa.');
    }

    await _createMessage(
      chatId: chatId,
      type: 'text',
      text: trimmed,
      subject: subject.trim(),
      priority: priority,
      replyTo: replyTo,
      replySenderName: replySenderName,
      forwardedFromSenderName: forwardedFromSenderName,
    );
  }

  Future<void> sendAttachmentMessage({
    required String chatId,
    required String type,
    File? file,
    Uint8List? bytes,
    String? fileName,
    String text = '',
    String subject = '',
    String priority = 'normal',
    bool viewOnce = false,
    Message? replyTo,
    String replySenderName = '',
  }) async {
    if (_auth.currentUser == null) {
      throw Exception('No hay sesión activa.');
    }

    final resolvedFileName =
        fileName ?? (file != null ? path.basename(file.path) : 'archivo');
    final upload = await _uploadToCloudinary(
      type,
      file,
      bytes,
      resolvedFileName,
      chatId,
    );

    await _createMessage(
      chatId: chatId,
      type: type,
      text: text.trim(),
      subject: subject.trim(),
      priority: priority,
      replyTo: replyTo,
      replySenderName: replySenderName,
      attachmentUrl: upload.secureUrl,
      fileName: resolvedFileName,
      attachments: [
        MessageAttachment(
          url: upload.secureUrl,
          name: resolvedFileName,
          type: type,
        ),
      ],
      viewOnce: viewOnce,
    );
  }

  Future<void> sendVoiceMessage({
    required String chatId,
    required File audioFile,
    required int durationMs,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final fileName = path.basename(audioFile.path);
    final upload = await _cloudinary.uploadRawAsset(
      file: audioFile,
      fileName: fileName,
      folder: 'messeya/audio/$chatId',
    );

    await _createMessage(
      chatId: chatId,
      type: 'audio',
      text: '',
      attachmentUrl: upload.secureUrl,
      fileName: fileName,
      voiceDurationMs: durationMs,
    );
  }

  Future<void> markMessagesAsSeen({
    required String chatId,
    required List<Message> messages,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    final batch = _firestore.batch();
    var hasChanges = false;
    final now = FieldValue.serverTimestamp();
    for (final message in messages) {
      if (message.senderId != userId && !message.seenBy.contains(userId)) {
        batch
            .update(_chats.doc(chatId).collection('messages').doc(message.id), {
          'seenBy': FieldValue.arrayUnion([userId]),
          'deliveredTo': FieldValue.arrayUnion([userId]),
          'seenAt.$userId': now,
          'deliveredAt.$userId': now,
        });
        hasChanges = true;
      }
    }
    if (hasChanges) {
      await batch.commit();
      await _chats.doc(chatId).update({'unreadCounts.$userId': 0});
    }
  }

  Future<void> markRecentMessagesAsDelivered({
    required String chatId,
    String? viewerUserId,
  }) async {
    final userId = viewerUserId ?? _auth.currentUser?.uid;
    if (userId == null) return;
    final messages = await _chats
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .get();
    final batch = _firestore.batch();
    var hasChanges = false;
    final now = FieldValue.serverTimestamp();
    for (final doc in messages.docs) {
      final data = doc.data();
      final deliveredTo = List<String>.from(data['deliveredTo'] ?? const []);
      if (data['senderId'] != userId && !deliveredTo.contains(userId)) {
        batch.update(doc.reference, {
          'deliveredTo': FieldValue.arrayUnion([userId]),
          'deliveredAt.$userId': now,
        });
        hasChanges = true;
      }
    }
    if (hasChanges) await batch.commit();
  }

  Future<void> deleteMessageForMe({
    required String chatId,
    required String messageId,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    await _chats.doc(chatId).collection('messages').doc(messageId).update({
      'deletedFor': FieldValue.arrayUnion([userId]),
    });
  }

  Future<void> deleteMessageForEveryone({
    required String chatId,
    required Message message,
  }) async {
    await _chats.doc(chatId).collection('messages').doc(message.id).update({
      'text': 'Mensaje eliminado',
      'type': 'deleted',
      'deletedForAll': true,
    });
  }

  Future<void> forwardMessage({
    required String targetChatId,
    required Message originalMessage,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _createMessage(
      chatId: targetChatId,
      type: originalMessage.type,
      text: originalMessage.text,
      subject: originalMessage.subject,
      priority: originalMessage.priority,
      attachmentUrl: originalMessage.attachmentUrl,
      fileName: originalMessage.fileName,
      attachments: originalMessage.attachments,
      voiceDurationMs: originalMessage.voiceDurationMs,
      viewOnce: originalMessage.viewOnce,
      forwardedFromMessageId: originalMessage.id,
      forwardedFromChatId: originalMessage.chatId,
      forwardedFromSenderName:
          originalMessage.forwardedFromSenderName.isNotEmpty
              ? originalMessage.forwardedFromSenderName
              : (originalMessage.senderId == user.uid ? 'Tú' : 'Usuario'),
    );
  }

  Future<void> _createMessage({
    required String chatId,
    required String type,
    required String text,
    String subject = '',
    String priority = 'normal',
    Message? replyTo,
    String replySenderName = '',
    String forwardedFromMessageId = '',
    String forwardedFromChatId = '',
    String forwardedFromSenderName = '',
    String attachmentUrl = '',
    String fileName = '',
    List<MessageAttachment> attachments = const [],
    int voiceDurationMs = 0,
    bool viewOnce = false,
  }) async {
    if (BackendConfig.hasApiBaseUrl) {
      await _createMessageViaApi(
        chatId: chatId,
        type: type,
        text: text,
        subject: subject,
        priority: priority,
        replyTo: replyTo,
        replySenderName: replySenderName,
        forwardedFromMessageId: forwardedFromMessageId,
        forwardedFromChatId: forwardedFromChatId,
        forwardedFromSenderName: forwardedFromSenderName,
        attachmentUrl: attachmentUrl,
        fileName: fileName,
        attachments: attachments,
        voiceDurationMs: voiceDurationMs,
        viewOnce: viewOnce,
      );
      return;
    }

    await _createMessageDirectly(
      chatId: chatId,
      type: type,
      text: text,
      subject: subject,
      priority: priority,
      replyTo: replyTo,
      replySenderName: replySenderName,
      forwardedFromMessageId: forwardedFromMessageId,
      forwardedFromChatId: forwardedFromChatId,
      forwardedFromSenderName: forwardedFromSenderName,
      attachmentUrl: attachmentUrl,
      fileName: fileName,
      attachments: attachments,
      voiceDurationMs: voiceDurationMs,
      viewOnce: viewOnce,
    );
  }

  Future<void> _createMessageViaApi({
    required String chatId,
    required String type,
    required String text,
    required String subject,
    required String priority,
    required Message? replyTo,
    required String replySenderName,
    required String forwardedFromMessageId,
    required String forwardedFromChatId,
    required String forwardedFromSenderName,
    required String attachmentUrl,
    required String fileName,
    required List<MessageAttachment> attachments,
    required int voiceDurationMs,
    required bool viewOnce,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay una sesión activa.');

    final idToken = await user.getIdToken(true);
    final response = await http.post(
      BackendConfig.buildUri('/api/send-message'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'chatId': chatId,
        'type': type,
        'text': text,
        'subject': subject,
        'priority': priority,
        'replyToMessageId': replyTo?.id ?? '',
        'replyToText': replyTo?.text ?? '',
        'replyToSenderName': replySenderName,
        'replyToType': replyTo?.type ?? '',
        'forwardedFromMessageId': forwardedFromMessageId,
        'forwardedFromChatId': forwardedFromChatId,
        'forwardedFromSenderName': forwardedFromSenderName,
        'attachmentUrl': attachmentUrl,
        'fileName': fileName,
        'attachments': attachments.map((item) => item.toMap()).toList(),
        'voiceDurationMs': voiceDurationMs,
        'viewOnce': viewOnce,
      }),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    Map<String, dynamic> payload = const {};
    if (response.body.isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        payload = decoded;
      }
    }
    throw Exception(
      payload['error']?.toString() ??
          'No se pudo enviar el mensaje mediante el backend.',
    );
  }

  Future<void> _createMessageDirectly({
    required String chatId,
    required String type,
    required String text,
    required String subject,
    required String priority,
    required Message? replyTo,
    required String replySenderName,
    required String forwardedFromMessageId,
    required String forwardedFromChatId,
    required String forwardedFromSenderName,
    required String attachmentUrl,
    required String fileName,
    required List<MessageAttachment> attachments,
    required int voiceDurationMs,
    required bool viewOnce,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay una sesión activa.');

    final userId = user.uid;
    final messageRef = _chats.doc(chatId).collection('messages').doc();
    final now = FieldValue.serverTimestamp();

    await _firestore.runTransaction((transaction) async {
      final chatRef = _chats.doc(chatId);
      final chatSnapshot = await transaction.get(chatRef);

      if (!chatSnapshot.exists) throw Exception('El chat no existe.');

      transaction.set(messageRef, {
        ..._baseMessageData(
          messageId: messageRef.id,
          chatId: chatId,
          userId: userId,
          type: type,
          text: text,
          now: now,
          replyTo: replyTo,
          replySenderName: replySenderName,
        ),
        'subject': subject,
        'priority': priority,
        'attachmentUrl': attachmentUrl,
        'fileName': fileName,
        'attachments': attachments.map((item) => item.toMap()).toList(),
        'voiceDurationMs': voiceDurationMs,
        'viewOnce': viewOnce,
        'forwardedFromMessageId': forwardedFromMessageId,
        'forwardedFromChatId': forwardedFromChatId,
        'forwardedFromSenderName': forwardedFromSenderName,
      });

      final members = List<String>.from(chatSnapshot.data()?['members'] ?? []);
      final updates = <String, dynamic>{
        'lastMessage': _buildPreview(
          type: type,
          text: text,
          subject: subject,
          priority: priority,
          attachmentsCount: attachments.length,
        ),
        'lastMessageAt': now,
        'lastMessageSenderId': userId,
      };

      for (final memberId in members) {
        if (memberId != userId) {
          updates['unreadCounts.$memberId'] = FieldValue.increment(1);
        }
      }

      transaction.update(chatRef, updates);
    });
  }

  Map<String, dynamic> _baseMessageData({
    required String messageId,
    required String chatId,
    required String userId,
    required String type,
    required String text,
    required FieldValue now,
    Message? replyTo,
    String replySenderName = '',
  }) {
    return {
      'id': messageId,
      'chatId': chatId,
      'senderId': userId,
      'text': text,
      'createdAt': now,
      'type': type,
      'seenBy': [userId],
      'deliveredTo': [userId],
      'deletedFor': [],
      'deletedForAll': false,
      'attachmentUrl': '',
      'fileName': '',
      'attachments': [],
      'reactions': {},
      'replyToMessageId': replyTo?.id ?? '',
      'replyToText': replyTo?.text ?? '',
      'replyToSenderName': replySenderName,
      'replyToType': replyTo?.type ?? '',
      'voiceDurationMs': 0,
      'pollQuestion': '',
      'pollOptions': [],
      'editedAt': null,
      'forwardedFromMessageId': '',
      'forwardedFromChatId': '',
      'forwardedFromSenderName': '',
      'starredBy': [],
      'viewOnce': false,
      'mediaOpenedBy': [userId],
      'subject': '',
      'priority': 'normal',
      'seenAt': {userId: now},
      'deliveredAt': {userId: now},
    };
  }

  bool _isImage(String value) {
    return ['jpg', 'jpeg', 'png', 'gif', 'webp']
        .contains(value.split('.').last.toLowerCase());
  }

  bool _isVideo(String value) {
    return ['mp4', 'mov', 'avi', 'mkv']
        .contains(value.split('.').last.toLowerCase());
  }

  String _getPreviewLabel(String type) {
    return switch (type) {
      'image' => 'Foto',
      'video' => 'Video',
      'audio' => 'Audio',
      _ => 'Archivo',
    };
  }

  String _buildPreview({
    required String type,
    required String text,
    required String subject,
    required String priority,
    int attachmentsCount = 0,
  }) {
    if (subject.isNotEmpty && text.isNotEmpty) {
      return '[$priority] $subject: $text';
    }
    if (subject.isNotEmpty) {
      return '[$priority] $subject';
    }
    if (text.isNotEmpty) {
      return text;
    }
    if (attachmentsCount > 1) {
      return 'Envio $attachmentsCount archivos';
    }
    return _getPreviewLabel(type);
  }

  Future<dynamic> _uploadToCloudinary(
    String type,
    File? file,
    Uint8List? bytes,
    String fileName,
    String chatId,
  ) async {
    return switch (type) {
      'image' => await _cloudinary.uploadImageAsset(
          file: file,
          bytes: bytes,
          fileName: fileName,
          folder: 'messeya/media/$chatId',
        ),
      'video' => await _cloudinary.uploadVideoAsset(
          file: file!,
          folder: 'messeya/media/$chatId',
        ),
      _ => await _cloudinary.uploadRawAsset(
          file: file,
          bytes: bytes,
          fileName: fileName,
          folder: 'messeya/media/$chatId',
        ),
    };
  }
}
