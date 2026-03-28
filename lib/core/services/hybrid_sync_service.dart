import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../firebase/firebase_providers.dart';
import 'app_preferences_service.dart';
import '../../features/messages/data/messages_repository.dart';
import '../../features/profile/data/profile_repository.dart';
import 'hybrid_local_message.dart';
import 'hybrid_local_queue_service.dart';
import 'nearby_mesh_service.dart';
import 'network_connectivity_service.dart';

final hybridSyncServiceProvider = Provider<HybridSyncService>((ref) {
  return HybridSyncService(
    ref.watch(firestoreProvider),
    ref.watch(appPreferencesServiceProvider),
    ref.watch(hybridLocalQueueServiceProvider),
    ref.watch(nearbyMeshServiceProvider),
    ref.watch(networkConnectivityServiceProvider),
    ref.watch(messagesRepositoryProvider),
    ref.watch(profileRepositoryProvider),
  );
});

class HybridSyncService {
  HybridSyncService(
    this._firestore,
    this._preferences,
    this._queue,
    this._nearby,
    this._connectivity,
    this._messagesRepository,
    this._profileRepository,
  );

  final FirebaseFirestore _firestore;
  final AppPreferencesService _preferences;
  final HybridLocalQueueService _queue;
  final NearbyMeshService _nearby;
  final NetworkConnectivityService _connectivity;
  final MessagesRepository _messagesRepository;
  final ProfileRepository _profileRepository;

  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<Map<String, dynamic>>? _nearbySubscription;
  StreamSubscription<NearbyMeshState>? _nearbyStateSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _gatewayPacketsSubscription;
  Timer? _meshRetryTimer;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _queue.initialize();
    if (_preferences.getHybridEnabled()) {
      await _ensureNearbyReady();
    }

    _connectivitySubscription = _connectivity.watchOnline().listen((online) {
      if (online) {
        unawaited(flushPendingToCloud());
      }
    });

    _nearbySubscription = _nearby.receivedMessages.listen(_handleNearbyPayload);
    _nearbyStateSubscription = _nearby.stateStream.listen((state) {
      if (_preferences.getHybridEnabled() &&
          state.connectedEndpoints.isNotEmpty) {
        unawaited(flushPendingToMesh());
      }
    });
    _meshRetryTimer = Timer.periodic(
      const Duration(seconds: 12),
      (_) => unawaited(flushPendingToMesh()),
    );
    await _bindGatewayPackets();

    if (await _connectivity.isOnline()) {
      await flushPendingToCloud();
    }
    if (_preferences.getHybridEnabled()) {
      await flushPendingToMesh();
    }
  }

  Future<void> sendDirectText({
    required String chatId,
    required String recipientId,
    required String text,
  }) async {
    final currentUser = await _profileRepository.getCurrentUser();
    if (currentUser == null) {
      throw Exception('No encontramos tu perfil para enviar el mensaje.');
    }
    if (!_preferences.getHybridEnabled()) {
      throw Exception(
        'Activa la red hibrida en Ajustes para usar envio cercano sin internet.',
      );
    }
    await _ensureNearbyReady();

    final message = HybridLocalMessage(
      localId: 0,
      messageUuid: const Uuid().v4(),
      chatId: chatId,
      senderId: currentUser.uid,
      senderName: currentUser.name,
      recipientId: recipientId,
      text: text.trim(),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      direction: 'outgoing',
      status: 'pending',
      relayHopsLeft: 3,
      lastError: '',
      packetType: 'message',
      originalSenderId: currentUser.uid,
      retryCount: 0,
      lastAttemptAtMs: 0,
      attachmentPath: '',
      attachmentName: '',
      voiceDurationMs: 0,
    );
    await _queue.insert(message);
    await _queue.markPacketSeen(
      message.messageUuid,
      packetType: message.packetType,
    );

    final online = await _connectivity.isOnline();
    if (online) {
      await _syncOutgoingMessage(message);
      return;
    }

    await flushPendingToMesh();
  }

  Future<void> flushPendingToCloud() async {
    final pending = await _queue.getPendingMessages();
    for (final message in pending) {
      await _syncOutgoingMessage(message);
    }
  }

  Future<void> queueCloudText({
    required String chatId,
    required String recipientId,
    required String text,
  }) async {
    final currentUser = await _profileRepository.getCurrentUser();
    if (currentUser == null) {
      throw Exception('No encontramos tu perfil para guardar el mensaje.');
    }
    await _queue.insert(
      HybridLocalMessage(
        localId: 0,
        messageUuid: const Uuid().v4(),
        chatId: chatId,
        senderId: currentUser.uid,
        senderName: currentUser.name,
        recipientId: recipientId,
        text: text.trim(),
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        direction: 'outgoing',
        status: 'pending',
        relayHopsLeft: 0,
        lastError: '',
        packetType: 'cloud_text',
        originalSenderId: currentUser.uid,
        retryCount: 0,
        lastAttemptAtMs: 0,
        attachmentPath: '',
        attachmentName: '',
        voiceDurationMs: 0,
      ),
    );
  }

  Future<void> queueCloudAttachment({
    required String chatId,
    required String recipientId,
    required String type,
    File? file,
    Uint8List? bytes,
    String? fileName,
    String text = '',
  }) async {
    final currentUser = await _profileRepository.getCurrentUser();
    if (currentUser == null) {
      throw Exception('No encontramos tu perfil para guardar el archivo.');
    }
    final storedPath = await _persistOfflineFile(
      bytes: bytes,
      sourceFile: file,
      fileName: fileName,
    );
    final resolvedName = fileName ??
        (file != null ? path.basename(file.path) : path.basename(storedPath));
    final packetType = switch (type) {
      'image' => 'cloud_attachment_image',
      'video' => 'cloud_attachment_video',
      _ => 'cloud_attachment_file',
    };
    await _queue.insert(
      HybridLocalMessage(
        localId: 0,
        messageUuid: const Uuid().v4(),
        chatId: chatId,
        senderId: currentUser.uid,
        senderName: currentUser.name,
        recipientId: recipientId,
        text: text.trim(),
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        direction: 'outgoing',
        status: 'pending',
        relayHopsLeft: 0,
        lastError: '',
        packetType: packetType,
        originalSenderId: currentUser.uid,
        retryCount: 0,
        lastAttemptAtMs: 0,
        attachmentPath: storedPath,
        attachmentName: resolvedName,
        voiceDurationMs: 0,
      ),
    );
  }

  Future<void> queueCloudVoice({
    required String chatId,
    required String recipientId,
    required File audioFile,
    required int durationMs,
  }) async {
    final currentUser = await _profileRepository.getCurrentUser();
    if (currentUser == null) {
      throw Exception('No encontramos tu perfil para guardar la nota de voz.');
    }
    final storedPath = await _persistOfflineFile(sourceFile: audioFile);
    await _queue.insert(
      HybridLocalMessage(
        localId: 0,
        messageUuid: const Uuid().v4(),
        chatId: chatId,
        senderId: currentUser.uid,
        senderName: currentUser.name,
        recipientId: recipientId,
        text: '',
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        direction: 'outgoing',
        status: 'pending',
        relayHopsLeft: 0,
        lastError: '',
        packetType: 'cloud_voice',
        originalSenderId: currentUser.uid,
        retryCount: 0,
        lastAttemptAtMs: 0,
        attachmentPath: storedPath,
        attachmentName: path.basename(storedPath),
        voiceDurationMs: durationMs,
      ),
    );
  }

  Future<void> restartNearby() async {
    await _nearby.stop();
    if (_preferences.getHybridEnabled()) {
      await _ensureNearbyReady();
    }
  }

  Future<void> flushPendingToMesh() async {
    if (!_preferences.getHybridEnabled()) return;
    if (_nearby.currentState.connectedEndpoints.isEmpty) return;

    final packets = await _queue.getPendingMeshPackets();
    if (packets.isEmpty) return;

    for (final packet in packets) {
      if (packet.retryCount >= 12) {
        await _queue.expirePacket(
          packet.messageUuid,
          error: 'Se agotaron los reintentos mesh.',
        );
        continue;
      }
      final payload = packet.packetType == 'ack'
          ? {
              'type': 'hybrid_ack',
              'ackUuid': packet.messageUuid,
              'messageUuid': packet.text,
              'chatId': packet.chatId,
              'originalSenderId': packet.originalSenderId,
              'fromUserId': packet.senderId,
              'toUserId': packet.recipientId,
              'relayHopsLeft': packet.relayHopsLeft,
            }
          : {
              'type': 'hybrid_message',
              'messageUuid': packet.messageUuid,
              'chatId': packet.chatId,
              'senderId': packet.senderId,
              'senderName': packet.senderName,
              'recipientId': packet.recipientId,
              'text': packet.text,
              'createdAtMs': packet.createdAtMs,
              'relayHopsLeft': packet.relayHopsLeft,
              'originalSenderId': packet.originalSenderId,
            };
      final sentCount = await _nearby.sendJsonBroadcast(payload);
      if (sentCount == 0) {
        await _queue.touchForRetry(packet.messageUuid);
        continue;
      }
      await _queue.updateStatus(
        packet.messageUuid,
        status: packet.packetType == 'ack'
            ? 'ack_forwarded'
            : packet.direction == 'relay'
                ? 'mesh_forwarded'
                : 'mesh_sent',
        trackAttempt: true,
      );
    }
  }

  Future<void> _ensureNearbyReady() async {
    final currentUser = await _profileRepository.getCurrentUser();
    if (currentUser == null) return;
    await _nearby.initialize(userName: currentUser.name);
  }

  Future<void> _syncOutgoingMessage(HybridLocalMessage message) async {
    try {
      switch (message.packetType) {
        case 'cloud_attachment_image':
        case 'cloud_attachment_video':
        case 'cloud_attachment_file':
          final queuedFile = File(message.attachmentPath);
          if (!await queuedFile.exists()) {
            throw Exception(
                'No encontramos el archivo offline para sincronizar.');
          }
          final attachmentType = switch (message.packetType) {
            'cloud_attachment_image' => 'image',
            'cloud_attachment_video' => 'video',
            _ => 'file',
          };
          await _messagesRepository.sendAttachmentMessage(
            chatId: message.chatId,
            type: attachmentType,
            file: queuedFile,
            fileName: message.attachmentName,
            text: message.text,
          );
          break;
        case 'cloud_voice':
          final voiceFile = File(message.attachmentPath);
          if (!await voiceFile.exists()) {
            throw Exception(
                'No encontramos la nota de voz offline para sincronizar.');
          }
          await _messagesRepository.sendVoiceMessage(
            chatId: message.chatId,
            audioFile: voiceFile,
            durationMs: message.voiceDurationMs,
          );
          break;
        case 'cloud_text':
        case 'message':
        default:
          await _messagesRepository.sendTextMessage(
            chatId: message.chatId,
            text: message.text,
          );
      }
      await _queue.updateStatus(message.messageUuid, status: 'cloud_synced');
      if (message.attachmentPath.isNotEmpty) {
        final localFile = File(message.attachmentPath);
        if (await localFile.exists()) {
          await localFile.delete();
        }
      }
    } catch (error) {
      await _queue.updateStatus(
        message.messageUuid,
        status: 'pending',
        error: error.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> _handleNearbyPayload(Map<String, dynamic> payload) async {
    final currentUser = await _profileRepository.getCurrentUser();
    if (currentUser == null) return;

    final type = payload['type'] as String? ?? '';
    if (type == 'hybrid_ack') {
      final ackUuid = payload['ackUuid'] as String? ?? '';
      final messageUuid = payload['messageUuid'] as String? ?? '';
      final chatId = payload['chatId'] as String? ?? '';
      final targetUserId = payload['toUserId'] as String? ?? '';
      final fromUserId = payload['fromUserId'] as String? ?? '';
      final relayHopsLeft = payload['relayHopsLeft'] as int? ?? 0;
      if (ackUuid.isEmpty || await _queue.hasSeenPacket(ackUuid)) return;
      await _queue.markPacketSeen(ackUuid, packetType: 'ack');
      await _queue.storeAck(
        ackUuid: ackUuid,
        messageUuid: messageUuid,
        fromUserId: fromUserId,
        toUserId: targetUserId,
      );
      if (messageUuid.isNotEmpty && targetUserId == currentUser.uid) {
        await _queue.updateStatus(messageUuid, status: 'ack_received');
        return;
      }
      if (relayHopsLeft > 0) {
        await _queue.insert(
          HybridLocalMessage(
            localId: 0,
            messageUuid: ackUuid,
            chatId: chatId,
            senderId: fromUserId,
            senderName: 'ACK',
            recipientId: targetUserId,
            text: messageUuid,
            createdAtMs: DateTime.now().millisecondsSinceEpoch,
            direction: 'relay',
            status: 'ack_pending',
            relayHopsLeft: relayHopsLeft - 1,
            lastError: '',
            packetType: 'ack',
            originalSenderId: targetUserId,
            retryCount: 0,
            lastAttemptAtMs: 0,
            attachmentPath: '',
            attachmentName: '',
            voiceDurationMs: 0,
          ),
        );
        await flushPendingToMesh();
      }
      return;
    }

    if (type != 'hybrid_message') return;

    final messageUuid = payload['messageUuid'] as String? ?? '';
    if (messageUuid.isEmpty || await _queue.hasSeenPacket(messageUuid)) return;
    await _queue.markPacketSeen(messageUuid, packetType: 'message');

    final recipientId = payload['recipientId'] as String? ?? '';
    final relayHopsLeft = payload['relayHopsLeft'] as int? ?? 0;
    final originalSenderId = payload['originalSenderId'] as String? ??
        payload['senderId'] as String? ??
        '';
    final chatId = payload['chatId'] as String? ?? '';

    if (recipientId == currentUser.uid) {
      await _queue.insert(
        HybridLocalMessage(
          localId: 0,
          messageUuid: messageUuid,
          chatId: chatId,
          senderId: payload['senderId'] as String? ?? '',
          senderName: payload['senderName'] as String? ?? 'Cercano',
          recipientId: recipientId,
          text: payload['text'] as String? ?? '',
          createdAtMs: payload['createdAtMs'] as int? ??
              DateTime.now().millisecondsSinceEpoch,
          direction: 'incoming',
          status: 'mesh_received',
          relayHopsLeft: 0,
          lastError: '',
          packetType: 'message',
          originalSenderId: originalSenderId,
          retryCount: 0,
          lastAttemptAtMs: 0,
          attachmentPath: '',
          attachmentName: '',
          voiceDurationMs: 0,
        ),
      );
      final ackUuid = const Uuid().v4();
      await _queue.storeAck(
        ackUuid: ackUuid,
        messageUuid: messageUuid,
        fromUserId: currentUser.uid,
        toUserId: originalSenderId,
      );
      await _queue.markPacketSeen(ackUuid, packetType: 'ack');
      await _queue.insert(
        HybridLocalMessage(
          localId: 0,
          messageUuid: ackUuid,
          chatId: chatId,
          senderId: currentUser.uid,
          senderName: currentUser.name,
          recipientId: originalSenderId,
          text: messageUuid,
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
          direction: 'outgoing',
          status: 'ack_pending',
          relayHopsLeft: 3,
          lastError: '',
          packetType: 'ack',
          originalSenderId: originalSenderId,
          retryCount: 0,
          lastAttemptAtMs: 0,
          attachmentPath: '',
          attachmentName: '',
          voiceDurationMs: 0,
        ),
      );
      await flushPendingToMesh();
      return;
    }

    if (_preferences.getHybridGatewayEnabled() &&
        await _connectivity.isOnline()) {
      await _uploadGatewayPacket(
        payload: payload,
        relayedByUserId: currentUser.uid,
      );
    }

    if (!_preferences.getHybridRelayEnabled()) {
      return;
    }

    if (relayHopsLeft > 0) {
      await _queue.insert(
        HybridLocalMessage(
          localId: 0,
          messageUuid: messageUuid,
          chatId: chatId,
          senderId: payload['senderId'] as String? ?? '',
          senderName: payload['senderName'] as String? ?? 'Cercano',
          recipientId: recipientId,
          text: payload['text'] as String? ?? '',
          createdAtMs: payload['createdAtMs'] as int? ??
              DateTime.now().millisecondsSinceEpoch,
          direction: 'relay',
          status: 'mesh_pending',
          relayHopsLeft: relayHopsLeft - 1,
          lastError: '',
          packetType: 'message',
          originalSenderId: originalSenderId,
          retryCount: 0,
          lastAttemptAtMs: 0,
          attachmentPath: '',
          attachmentName: '',
          voiceDurationMs: 0,
        ),
      );
      await flushPendingToMesh();
    }
  }

  Future<void> _bindGatewayPackets() async {
    await _gatewayPacketsSubscription?.cancel();
    final currentUser = await _profileRepository.getCurrentUser();
    if (currentUser == null) return;
    _gatewayPacketsSubscription = _firestore
        .collection('hybrid_gateway_packets')
        .where('recipientId', isEqualTo: currentUser.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) async {
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final messageUuid = data['messageUuid'] as String? ?? '';
        if (messageUuid.isEmpty || await _queue.hasSeenPacket(messageUuid)) {
          await doc.reference.set(
            {'status': 'ignored'},
            SetOptions(merge: true),
          );
          continue;
        }
        await _queue.markPacketSeen(messageUuid, packetType: 'message');
        await _queue.insert(
          HybridLocalMessage(
            localId: 0,
            messageUuid: messageUuid,
            chatId: data['chatId'] as String? ?? '',
            senderId: data['senderId'] as String? ?? '',
            senderName: data['senderName'] as String? ?? 'Gateway',
            recipientId: currentUser.uid,
            text: data['text'] as String? ?? '',
            createdAtMs: data['createdAtMs'] as int? ??
                DateTime.now().millisecondsSinceEpoch,
            direction: 'incoming',
            status: 'gateway_received',
            relayHopsLeft: 0,
            lastError: '',
            packetType: 'message',
            originalSenderId: data['originalSenderId'] as String? ??
                data['senderId'] as String? ??
                '',
            retryCount: 0,
            lastAttemptAtMs: 0,
            attachmentPath: '',
            attachmentName: '',
            voiceDurationMs: 0,
          ),
        );
        await doc.reference.set(
          {
            'status': 'delivered',
            'deliveredAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    });
  }

  Future<void> _uploadGatewayPacket({
    required Map<String, dynamic> payload,
    required String relayedByUserId,
  }) async {
    final messageUuid = payload['messageUuid'] as String? ?? '';
    if (messageUuid.isEmpty) return;
    await _firestore.collection('hybrid_gateway_packets').doc(messageUuid).set({
      'messageUuid': messageUuid,
      'chatId': payload['chatId'] as String? ?? '',
      'senderId': payload['senderId'] as String? ?? '',
      'senderName': payload['senderName'] as String? ?? 'Nodo',
      'recipientId': payload['recipientId'] as String? ?? '',
      'text': payload['text'] as String? ?? '',
      'createdAtMs': payload['createdAtMs'] as int? ??
          DateTime.now().millisecondsSinceEpoch,
      'originalSenderId': payload['originalSenderId'] as String? ??
          payload['senderId'] as String? ??
          '',
      'relayedByUserId': relayedByUserId,
      'status': 'pending',
      'relayedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> _persistOfflineFile({
    File? sourceFile,
    Uint8List? bytes,
    String? fileName,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final offlineDir = Directory(path.join(directory.path, 'offline_queue'));
    if (!await offlineDir.exists()) {
      await offlineDir.create(recursive: true);
    }
    final resolvedName = fileName ??
        (sourceFile != null
            ? path.basename(sourceFile.path)
            : 'file_${DateTime.now().millisecondsSinceEpoch}');
    final targetPath = path.join(
      offlineDir.path,
      '${DateTime.now().millisecondsSinceEpoch}_$resolvedName',
    );
    if (sourceFile != null) {
      await sourceFile.copy(targetPath);
      return targetPath;
    }
    if (bytes != null) {
      final target = File(targetPath);
      await target.writeAsBytes(bytes, flush: true);
      return target.path;
    }
    throw Exception('No se pudo conservar el archivo offline.');
  }

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    await _nearbySubscription?.cancel();
    await _nearbyStateSubscription?.cancel();
    await _gatewayPacketsSubscription?.cancel();
    _meshRetryTimer?.cancel();
  }
}
