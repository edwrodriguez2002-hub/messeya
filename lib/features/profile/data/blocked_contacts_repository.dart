import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../shared/models/app_user.dart';

final blockedContactsRepositoryProvider =
    Provider<BlockedContactsRepository>((ref) {
  return BlockedContactsRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseAuthProvider),
  );
});

final blockedUserIdsProvider = StreamProvider<List<String>>((ref) {
  return ref.watch(blockedContactsRepositoryProvider).watchBlockedUserIds();
});

final blockedContactsProvider = StreamProvider<List<AppUser>>((ref) {
  return ref.watch(blockedContactsRepositoryProvider).watchBlockedContacts();
});

final isBlockedProvider = StreamProvider.family<bool, String>((ref, userId) {
  return ref.watch(blockedContactsRepositoryProvider).watchIsBlocked(userId);
});

class BlockedContactsRepository {
  BlockedContactsRepository(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> get _blockedUsersCollection =>
      _firestore.collection('users').doc(_uid).collection('blocked_users');

  Stream<List<String>> watchBlockedUserIds() {
    if (_uid == null) return Stream.value(const []);
    return _blockedUsersCollection.snapshots().map(
          (snapshot) => snapshot.docs.map((doc) => doc.id).toList(),
        );
  }

  Stream<List<AppUser>> watchBlockedContacts() {
    if (_uid == null) return Stream.value(const []);
    return _blockedUsersCollection
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
      if (snapshot.docs.isEmpty) return <AppUser>[];

      final futures = snapshot.docs.map(
        (doc) => _firestore.collection('users').doc(doc.id).get(),
      );
      final userDocs = await Future.wait(futures);
      return userDocs
          .where((doc) => doc.exists)
          .map((doc) => AppUser.fromDoc(doc))
          .toList();
    });
  }

  Stream<bool> watchIsBlocked(String userId) {
    if (_uid == null || userId.isEmpty) return Stream.value(false);
    return _blockedUsersCollection
        .doc(userId)
        .snapshots()
        .map((doc) => doc.exists);
  }

  Future<void> blockUser(AppUser user) async {
    final currentUserId = _uid;
    if (currentUserId == null) throw Exception('No hay sesion activa.');
    if (user.uid.isEmpty || user.uid == currentUserId) return;

    await _blockedUsersCollection.doc(user.uid).set({
      'userId': user.uid,
      'name': user.name,
      'username': user.username,
      'photoUrl': user.photoUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unblockUser(String userId) async {
    final currentUserId = _uid;
    if (currentUserId == null || userId.isEmpty) return;
    await _blockedUsersCollection.doc(userId).delete();
  }
}
