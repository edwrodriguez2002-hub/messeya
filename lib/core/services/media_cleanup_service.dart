import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../firebase/firebase_providers.dart';
import '../../features/profile/data/profile_repository.dart';

final mediaCleanupServiceProvider = Provider<MediaCleanupService>((ref) {
  return MediaCleanupService(
    ref.watch(firestoreProvider),
    ref.watch(profileRepositoryProvider),
  );
});

class MediaCleanupService {
  MediaCleanupService(this._firestore, this._profileRepository);

  final FirebaseFirestore _firestore;
  final ProfileRepository _profileRepository;

  Timer? _timer;
  bool _running = false;

  CollectionReference<Map<String, dynamic>> get _statuses =>
      _firestore.collection('statuses');

  CollectionReference<Map<String, dynamic>> get _jobs =>
      _firestore.collection('media_cleanup_jobs');

  Future<void> initialize() async {
    if (_timer != null) return;
    await runSweep();
    _timer = Timer.periodic(
      const Duration(hours: 1),
      (_) => unawaited(runSweep()),
    );
  }

  Future<void> runSweep() async {
    if (_running) return;
    final uid = _profileRepository.currentUid;
    if (uid.isEmpty) return;

    _running = true;
    try {
      await _cleanupExpiredStatuses(uid);
      await _queueExpiredChatAttachments(uid);
    } finally {
      _running = false;
    }
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _cleanupExpiredStatuses(String uid) async {
    final now = Timestamp.now();
    final snapshot = await _statuses
        .where('userId', isEqualTo: uid)
        .where('expiresAt', isLessThanOrEqualTo: now)
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final mediaPublicId = data['mediaPublicId'] as String? ?? '';
      final mediaResourceType = data['mediaResourceType'] as String? ?? '';
      final mediaFolder = data['mediaFolder'] as String? ?? '';

      if (mediaPublicId.isNotEmpty) {
        await _jobs.doc('status_${doc.id}').set({
          'ownerId': uid,
          'kind': 'status',
          'sourceId': doc.id,
          'chatId': '',
          'resourceType': mediaResourceType,
          'publicId': mediaPublicId,
          'folder': mediaFolder,
          'requestedAt': FieldValue.serverTimestamp(),
          'executeAfter': now,
          'status': 'queued',
        }, SetOptions(merge: true));
      }

      await doc.reference.delete();
    }
  }

  Future<void> _queueExpiredChatAttachments(String uid) async {
    final now = Timestamp.now();
    final snapshot = await _firestore
        .collectionGroup('messages')
        .where('senderId', isEqualTo: uid)
        .where('attachmentCleanupAfter', isLessThanOrEqualTo: now)
        .get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final cleanupQueuedAt = data['attachmentCleanupQueuedAt'];
      final attachmentUrl = data['attachmentUrl'] as String? ?? '';
      final publicId = data['attachmentPublicId'] as String? ?? '';
      if (cleanupQueuedAt != null ||
          attachmentUrl.isEmpty ||
          publicId.isEmpty) {
        continue;
      }

      final chatId = data['chatId'] as String? ?? '';
      await _jobs.doc('message_${chatId}_${doc.id}').set({
        'ownerId': uid,
        'kind': 'chat_attachment',
        'sourceId': doc.id,
        'chatId': chatId,
        'resourceType': data['attachmentResourceType'] as String? ?? '',
        'publicId': publicId,
        'folder': data['attachmentFolder'] as String? ?? '',
        'requestedAt': FieldValue.serverTimestamp(),
        'executeAfter': now,
        'status': 'queued',
      }, SetOptions(merge: true));

      await doc.reference.update({
        'attachmentCleanupQueuedAt': FieldValue.serverTimestamp(),
        'attachmentCleanupStatus': 'queued',
      });
    }
  }
}
