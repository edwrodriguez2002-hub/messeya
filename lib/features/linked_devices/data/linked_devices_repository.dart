import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/services/app_preferences_service.dart';
import '../../auth/data/auth_repository.dart';
import '../../../shared/models/desktop_client_session.dart';
import '../../../shared/models/device_pairing_session.dart';
import '../../../shared/models/linked_device.dart';

final linkedDevicesRepositoryProvider =
    Provider<LinkedDevicesRepository>((ref) {
  return LinkedDevicesRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseAuthProvider),
  );
});

final linkedDevicesProvider = StreamProvider<List<LinkedDevice>>((ref) {
  return ref.watch(linkedDevicesRepositoryProvider).watchLinkedDevices();
});

final devicePairingSessionProvider =
    StreamProvider.family<DevicePairingSession?, String>((ref, sessionId) {
  return ref
      .watch(linkedDevicesRepositoryProvider)
      .watchPairingSession(sessionId);
});

final desktopClientSessionProvider =
    StreamProvider<DesktopClientSession?>((ref) {
  return ref.watch(linkedDevicesRepositoryProvider).watchDesktopClientSession();
});

final effectiveMessagingUserIdProvider = Provider<String>((ref) {
  final authUser = ref.watch(currentUserProvider);
  if (authUser == null) return '';
  if (!authUser.isAnonymous) return authUser.uid;
  final session = ref.watch(desktopClientSessionProvider).valueOrNull;
  if (session?.ownerUid.isNotEmpty == true) {
    return session!.ownerUid;
  }
  return ref.watch(appPreferencesServiceProvider).getDesktopLinkedOwnerUid();
});

class LinkedDevicesRepository {
  LinkedDevicesRepository(this._firestore, this._auth);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _pairingSessions =>
      _firestore.collection('device_pairing_sessions');
  CollectionReference<Map<String, dynamic>> get _desktopClients =>
      _firestore.collection('desktop_clients');

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  String get _uid => _auth.currentUser!.uid;

  Stream<List<LinkedDevice>> watchLinkedDevices() {
    if (_auth.currentUser == null || _auth.currentUser!.isAnonymous) {
      return Stream.value(const <LinkedDevice>[]);
    }
    return _users
        .doc(_uid)
        .collection('linked_devices')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(LinkedDevice.fromDoc).toList());
  }

  Stream<DevicePairingSession?> watchPairingSession(String sessionId) {
    return _pairingSessions.doc(sessionId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return DevicePairingSession.fromDoc(doc);
    });
  }

  Stream<DesktopClientSession?> watchDesktopClientSession() {
    final currentUser = _auth.currentUser;
    if (currentUser == null || !currentUser.isAnonymous) {
      return Stream.value(null);
    }
    return _desktopClients.doc(currentUser.uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return DesktopClientSession.fromDoc(doc);
    });
  }

  Future<DevicePairingSession> fetchPairingSession(String sessionId) async {
    final snapshot = await _pairingSessions.doc(sessionId).get();
    if (!snapshot.exists) {
      throw Exception('No encontramos ese codigo de vinculacion.');
    }
    return DevicePairingSession.fromDoc(snapshot);
  }

  Future<String> createPairingSession({
    required String platform,
    required String deviceLabel,
  }) async {
    final sessionRef = _pairingSessions.doc();
    final expiresAt = DateTime.now().add(const Duration(minutes: 10));
    await sessionRef.set({
      'creatorUid': _uid,
      'platform': platform,
      'deviceLabel': deviceLabel,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'ownerUid': '',
      'ownerName': '',
      'ownerUsername': '',
      'linkedDeviceId': '',
      'linkedAt': null,
    });
    return sessionRef.id;
  }

  Future<LinkedDevice> approvePairingSession(String sessionId) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.isAnonymous) {
      throw Exception('Inicia sesion en Android para vincular Windows.');
    }

    final userSnapshot = await _users.doc(_uid).get();
    final userData = userSnapshot.data() ?? const <String, dynamic>{};
    final ownerName = userData['name'] as String? ?? 'Usuario';
    final ownerUsername = userData['username'] as String? ?? '';

    return _firestore.runTransaction((transaction) async {
      final sessionRef = _pairingSessions.doc(sessionId);
      final sessionSnapshot = await transaction.get(sessionRef);
      if (!sessionSnapshot.exists) {
        throw Exception('La solicitud de vinculacion no existe.');
      }
      final session = DevicePairingSession.fromDoc(sessionSnapshot);
      if (!session.isPending) {
        throw Exception('La solicitud ya no esta disponible.');
      }
      if (session.platform != 'windows') {
        throw Exception('Ese QR no corresponde a una sesion de Windows.');
      }

      final linkedDeviceRef =
          _users.doc(_uid).collection('linked_devices').doc();
      final desktopClientRef = _desktopClients.doc(session.creatorUid);
      transaction.set(linkedDeviceRef, {
        'ownerUid': _uid,
        'pairingSessionId': sessionId,
        'creatorUid': session.creatorUid,
        'platform': session.platform,
        'deviceLabel': session.deviceLabel,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
        'revokedAt': null,
        'ownerName': ownerName,
        'ownerUsername': ownerUsername,
      });
      transaction.set(
          desktopClientRef,
          {
            'creatorUid': session.creatorUid,
            'ownerUid': _uid,
            'ownerName': ownerName,
            'ownerUsername': ownerUsername,
            'linkedDeviceId': linkedDeviceRef.id,
            'status': 'active',
            'lastActiveAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
      transaction.update(sessionRef, {
        'status': 'linked',
        'ownerUid': _uid,
        'ownerName': ownerName,
        'ownerUsername': ownerUsername,
        'linkedDeviceId': linkedDeviceRef.id,
        'linkedAt': FieldValue.serverTimestamp(),
      });

      return LinkedDevice(
        id: linkedDeviceRef.id,
        ownerUid: _uid,
        pairingSessionId: sessionId,
        creatorUid: session.creatorUid,
        platform: session.platform,
        deviceLabel: session.deviceLabel,
        status: 'active',
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
        revokedAt: null,
        ownerName: ownerName,
        ownerUsername: ownerUsername,
      );
    });
  }

  Future<void> revokeLinkedDevice(LinkedDevice device) async {
    if (_auth.currentUser == null || _auth.currentUser!.isAnonymous) {
      throw Exception('Solo puedes gestionar dispositivos desde tu cuenta.');
    }
    final now = FieldValue.serverTimestamp();
    await _users.doc(_uid).collection('linked_devices').doc(device.id).set({
      'status': 'revoked',
      'revokedAt': now,
      'lastActiveAt': now,
    }, SetOptions(merge: true));
    await _desktopClients.doc(device.creatorUid).set({
      'status': 'revoked',
      'lastActiveAt': now,
    }, SetOptions(merge: true));
    if (device.pairingSessionId.isNotEmpty) {
      await _pairingSessions.doc(device.pairingSessionId).set({
        'status': 'revoked',
      }, SetOptions(merge: true));
    }
  }
}
