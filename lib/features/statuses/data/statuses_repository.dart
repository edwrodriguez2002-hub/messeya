import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/services/cloudinary_media_service.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/status_item.dart';
import '../../linked_devices/data/linked_devices_repository.dart';
import '../../chats/data/chats_repository.dart';
import '../../messages/data/messages_repository.dart';
import '../../profile/data/profile_repository.dart';

final statusesRepositoryProvider = Provider<StatusesRepository>((ref) {
  return StatusesRepository(
    ref.watch(firestoreProvider),
    ref.watch(cloudinaryMediaServiceProvider),
    ref.watch(profileRepositoryProvider),
    ref.watch(chatsRepositoryProvider),
    ref.watch(messagesRepositoryProvider),
  );
});

final statusesProvider = StreamProvider<List<StatusItem>>((ref) {
  final viewerUid = ref.watch(effectiveMessagingUserIdProvider);
  return ref.watch(statusesRepositoryProvider).watchStatusesFor(viewerUid);
});

final unreadStatusesCountProvider = Provider<int>((ref) {
  final currentUid = ref.watch(effectiveMessagingUserIdProvider);
  final statuses =
      ref.watch(statusesProvider).valueOrNull ?? const <StatusItem>[];
  return statuses
      .where((status) => !status.viewedBy.contains(currentUid))
      .length;
});

final hiddenStatusContactsProvider = StreamProvider<List<AppUser>>((ref) {
  return ref.watch(statusesRepositoryProvider).watchHiddenStatusContacts();
});

final hiddenStatusIdsProvider = StreamProvider<List<String>>((ref) {
  return ref.watch(statusesRepositoryProvider).watchHiddenStatusContactIds();
});

final statusViewersProvider =
    FutureProvider.family<List<String>, List<String>>((ref, viewerIds) async {
  if (viewerIds.isEmpty) return const [];
  final firestore = ref.watch(firestoreProvider);
  final futures =
      viewerIds.map((id) => firestore.collection('users').doc(id).get());
  final docs = await Future.wait(futures);
  return docs
      .where((doc) => doc.exists)
      .map((doc) => (doc.data()?['name'] as String?) ?? 'Usuario')
      .toList();
});

class StatusesRepository {
  StatusesRepository(
    this._firestore,
    this._cloudinary,
    this._profileRepository,
    this._chatsRepository,
    this._messagesRepository,
  );

  final FirebaseFirestore _firestore;
  final CloudinaryMediaService _cloudinary;
  final ProfileRepository _profileRepository;
  final ChatsRepository _chatsRepository;
  final MessagesRepository _messagesRepository;

  CollectionReference<Map<String, dynamic>> get _statuses =>
      _firestore.collection('statuses');

  String get _uid => _profileRepository.currentUid;

  Stream<List<StatusItem>> watchStatuses() {
    return watchStatusesFor(_uid);
  }

  Stream<List<StatusItem>> watchStatusesFor(String viewerUid) {
    return _statuses
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap(
      (snapshot) async {
        final hiddenIds = await watchHiddenStatusContactIdsFor(viewerUid).first;
        return snapshot.docs.map(StatusItem.fromDoc).where((status) {
          final expiresAt = status.expiresAt;
          final notExpired =
              expiresAt == null || expiresAt.isAfter(DateTime.now());
          final notHiddenByAuthor = !status.hiddenFor.contains(viewerUid);
          final visibleForViewer =
              status.visibleTo.isEmpty || status.visibleTo.contains(viewerUid);
          final authorNotMuted = !hiddenIds.contains(status.userId);
          return notExpired &&
              notHiddenByAuthor &&
              authorNotMuted &&
              visibleForViewer;
        }).toList();
      },
    );
  }

  Stream<List<String>> watchHiddenStatusContactIds() {
    return watchHiddenStatusContactIdsFor(_uid);
  }

  Stream<List<String>> watchHiddenStatusContactIdsFor(String viewerUid) {
    return _firestore
        .collection('users')
        .doc(viewerUid)
        .collection('hidden_status_contacts')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.id).toList());
  }

  Stream<List<AppUser>> watchHiddenStatusContacts() {
    return watchHiddenStatusContactIds().asyncMap((ids) async {
      if (ids.isEmpty) return const <AppUser>[];
      final docs = await Future.wait(
          ids.map((id) => _firestore.collection('users').doc(id).get()));
      return docs.where((doc) => doc.exists).map(AppUser.fromDoc).toList();
    });
  }

  Future<void> hideStatusesFromContact(AppUser user) async {
    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('hidden_status_contacts')
        .doc(user.uid)
        .set({
      'uid': user.uid,
      'name': user.name,
      'username': user.username,
      'photoUrl': user.photoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> showStatusesForContact(String userId) async {
    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('hidden_status_contacts')
        .doc(userId)
        .delete();
  }

  Future<void> createStatus({
    required String text,
    File? imageFile,
    File? videoFile,
  }) async {
    final currentUser = await _profileRepository.getCurrentUser();
    if (currentUser == null) {
      throw Exception('No encontramos tu perfil para publicar un estado.');
    }

    final existingStatuses = await _statuses
        .where('userId', isEqualTo: currentUser.uid)
        .where('expiresAt', isGreaterThan: Timestamp.fromDate(DateTime.now()))
        .get();
    if (existingStatuses.docs.length >= 30) {
      throw Exception(
        'Ya alcanzaste el limite de 30 estados activos. Borra alguno o espera a que expire.',
      );
    }

    final hiddenFor = await watchHiddenStatusContactIds().first;
    final visibleTo = await _acceptedStatusAudience(currentUser.uid);
    final doc = _statuses.doc();
    var mediaUrl = '';
    var mediaType = 'text';

    String mediaPublicId = '';
    String mediaResourceType = '';
    String mediaFolder = '';

    if (imageFile != null) {
      final upload = await _cloudinary.uploadImageAsset(
        file: imageFile,
        folder: 'messeya/status_media/${currentUser.uid}',
        publicId: doc.id,
      );
      mediaUrl = upload.secureUrl;
      mediaPublicId = upload.publicId;
      mediaResourceType = upload.resourceType;
      mediaFolder = upload.folder;
      mediaType = 'image';
    } else if (videoFile != null) {
      final upload = await _cloudinary.uploadVideoAsset(
        file: videoFile,
        folder: 'messeya/status_media/${currentUser.uid}',
        publicId: doc.id,
      );
      mediaUrl = upload.secureUrl;
      mediaPublicId = upload.publicId;
      mediaResourceType = upload.resourceType;
      mediaFolder = upload.folder;
      mediaType = 'video';
    }

    final expiresAt = DateTime.now().add(const Duration(hours: 24));

    await doc.set({
      'userId': currentUser.uid,
      'username': currentUser.username,
      'userName': currentUser.name,
      'userPhoto': currentUser.photoUrl,
      'text': text.trim(),
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'mediaPublicId': mediaPublicId,
      'mediaResourceType': mediaResourceType,
      'mediaFolder': mediaFolder,
      'mediaCleanupAfter': Timestamp.fromDate(expiresAt),
      'mediaCleanupQueuedAt': null,
      'viewedBy': [currentUser.uid],
      'hiddenFor': hiddenFor,
      'visibleTo': visibleTo,
    });
  }

  Future<List<String>> _acceptedStatusAudience(String currentUserId) async {
    return _chatsRepository.getAcceptedDirectContactIds(currentUserId);
  }

  Future<void> markViewed(String statusId, {String? viewerUserId}) async {
    final resolvedViewerId = viewerUserId ?? _profileRepository.currentUid;
    if (resolvedViewerId.isEmpty) return;
    await _statuses.doc(statusId).update({
      'viewedBy': FieldValue.arrayUnion([resolvedViewerId]),
    });
  }

  Future<void> deleteStatus(String statusId) async {
    final currentUser = await _profileRepository.getCurrentUser();
    if (currentUser == null) {
      throw Exception('Tu sesion ya no esta disponible.');
    }
    final doc = await _statuses.doc(statusId).get();
    if (!doc.exists) {
      throw Exception('Ese estado ya no existe.');
    }
    final status = StatusItem.fromDoc(doc);
    if (status.userId != currentUser.uid) {
      throw Exception('Solo puedes borrar tus propios estados.');
    }
    await _statuses.doc(statusId).delete();
  }

  Future<void> replyToStatus({
    required StatusItem status,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw Exception('Escribe una respuesta para el estado.');
    }
    final currentUser = await _profileRepository.getCurrentUser();
    if (currentUser == null) {
      throw Exception('Tu sesion ya no esta disponible.');
    }
    if (status.userId == currentUser.uid) {
      throw Exception('No puedes responder tu propio estado.');
    }
    final targetUserDoc =
        await _firestore.collection('users').doc(status.userId).get();
    if (!targetUserDoc.exists) {
      throw Exception('No encontramos al usuario de ese estado.');
    }
    final targetUser = AppUser.fromDoc(targetUserDoc);
    final chatId = await _chatsRepository.createOrGetDirectChat(
      targetUser,
      currentUser,
    );
    final prefix = switch (status.mediaType) {
      'image' => 'Respondio a tu foto de estado',
      'video' => 'Respondio a tu video de estado',
      _ => 'Respondio a tu estado',
    };
    await _messagesRepository.sendTextMessage(
      chatId: chatId,
      text: status.text.trim().isEmpty
          ? '$prefix\n$trimmed'
          : '$prefix: ${status.text.trim()}\n$trimmed',
      replyTo: null,
      replySenderName: '',
    );
  }
}
