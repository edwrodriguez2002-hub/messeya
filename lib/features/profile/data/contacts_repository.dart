import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../linked_devices/data/linked_devices_repository.dart';
import '../../../shared/models/app_user.dart';

final contactsRepositoryProvider = Provider<ContactsRepository>((ref) {
  return ContactsRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseAuthProvider),
    ref,
  );
});

final myContactUidsProvider = StreamProvider<List<String>>((ref) {
  return ref.watch(contactsRepositoryProvider).watchContactUids();
});

final isContactProvider = StreamProvider.family<bool, String>((ref, otherUid) {
  return ref.watch(contactsRepositoryProvider).watchIsContact(otherUid);
});

final incomingRequestUidsProvider = StreamProvider<List<String>>((ref) {
  return ref.watch(contactsRepositoryProvider).watchIncomingRequestUids();
});

class ContactsRepository {
  ContactsRepository(this._firestore, this._auth, this._ref);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Ref _ref;

  String get _uid => _ref.read(effectiveMessagingUserIdProvider);

  Stream<List<String>> watchContactUids() {
    final uid = _uid;
    if (uid.isEmpty) return Stream.value([]);
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('contacts')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.id).toList());
  }

  Stream<bool> watchIsContact(String otherUid) {
    final uid = _uid;
    if (uid.isEmpty || otherUid.isEmpty) return Stream.value(false);
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('contacts')
        .doc(otherUid)
        .snapshots()
        .map((doc) => doc.exists);
  }

  Future<bool> isContact(String otherUid) async {
    final uid = _uid;
    if (uid.isEmpty || otherUid.isEmpty) return false;
    final doc = await _firestore
        .collection('users')
        .doc(uid)
        .collection('contacts')
        .doc(otherUid)
        .get();
    return doc.exists;
  }

  Stream<List<String>> watchIncomingRequestUids() {
    final uid = _uid;
    if (uid.isEmpty) return Stream.value([]);
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('contact_requests')
        .where('status', isEqualTo: 'pending')
        .where('direction', isEqualTo: 'incoming')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.id).toList());
  }

  Future<void> sendRequest(String otherUid) async {
    final uid = _uid;
    if (uid.isEmpty) return;
    final batch = _firestore.batch();
    batch.set(
      _firestore.collection('users').doc(uid).collection('contact_requests').doc(otherUid),
      {'status': 'pending', 'direction': 'outgoing', 'timestamp': FieldValue.serverTimestamp()},
    );
    batch.set(
      _firestore.collection('users').doc(otherUid).collection('contact_requests').doc(uid),
      {'status': 'pending', 'direction': 'incoming', 'timestamp': FieldValue.serverTimestamp()},
    );
    await batch.commit();
  }

  Future<void> acceptRequest(String otherUid) async {
    final uid = _uid;
    if (uid.isEmpty) return;
    final batch = _firestore.batch();
    batch.set(_firestore.collection('users').doc(uid).collection('contacts').doc(otherUid), {'addedAt': FieldValue.serverTimestamp()});
    batch.set(_firestore.collection('users').doc(otherUid).collection('contacts').doc(uid), {'addedAt': FieldValue.serverTimestamp()});
    batch.delete(_firestore.collection('users').doc(uid).collection('contact_requests').doc(otherUid));
    batch.delete(_firestore.collection('users').doc(otherUid).collection('contact_requests').doc(uid));
    await batch.commit();
  }

  Future<void> addToContacts(String otherUid) async {
    final uid = _uid;
    if (uid.isEmpty || otherUid.isEmpty) return;
    final batch = _firestore.batch();
    batch.set(_firestore.collection('users').doc(uid).collection('contacts').doc(otherUid), {'addedAt': FieldValue.serverTimestamp()});
    batch.set(_firestore.collection('users').doc(otherUid).collection('contacts').doc(uid), {'addedAt': FieldValue.serverTimestamp()});
    // Limpiar solicitudes si existen
    batch.delete(_firestore.collection('users').doc(uid).collection('contact_requests').doc(otherUid));
    batch.delete(_firestore.collection('users').doc(otherUid).collection('contact_requests').doc(uid));
    await batch.commit();
  }

  Future<void> rejectRequest(String otherUid) async {
    final uid = _uid;
    if (uid.isEmpty) return;
    final batch = _firestore.batch();
    batch.delete(_firestore.collection('users').doc(uid).collection('contact_requests').doc(otherUid));
    batch.delete(_firestore.collection('users').doc(otherUid).collection('contact_requests').doc(uid));
    await batch.commit();
  }
}
