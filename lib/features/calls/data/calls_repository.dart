import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../shared/models/active_call_session.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/call_invite.dart';
import '../../../shared/models/call_log.dart';
import '../../linked_devices/data/linked_devices_repository.dart';
import '../../profile/data/profile_repository.dart';

final callsRepositoryProvider = Provider<CallsRepository>((ref) {
  return CallsRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseAuthProvider),
    ref.watch(profileRepositoryProvider),
  );
});

final callLogsProvider = StreamProvider<List<CallLog>>((ref) {
  final effectiveUserId = ref.watch(effectiveMessagingUserIdProvider);
  return ref.watch(callsRepositoryProvider).watchCallLogsFor(effectiveUserId);
});

final incomingCallInviteProvider = StreamProvider<CallInvite?>((ref) {
  final effectiveUserId = ref.watch(effectiveMessagingUserIdProvider);
  return ref.watch(callsRepositoryProvider).watchIncomingCallInviteFor(
        effectiveUserId,
      );
});

final activeCallSessionProvider =
    StreamProvider.family<ActiveCallSession?, String>((ref, userId) {
  return ref.watch(callsRepositoryProvider).watchActiveCallFor(userId);
});

final missedCallsCountProvider = Provider<int>((ref) {
  final logs = ref.watch(callLogsProvider).valueOrNull ?? const <CallLog>[];
  return logs
      .where((log) => log.direction == 'incoming' && log.status == 'missed')
      .length;
});

class CallsRepository {
  CallsRepository(this._firestore, this._auth, this._profileRepository);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final ProfileRepository _profileRepository;
  CollectionReference<Map<String, dynamic>> get _calls =>
      _firestore.collection('calls');

  CollectionReference<Map<String, dynamic>> get _myCallLogs => _firestore
      .collection('users')
      .doc(_auth.currentUser!.uid)
      .collection('call_logs');

  CollectionReference<Map<String, dynamic>> _callLogsFor(String userId) =>
      _firestore.collection('users').doc(userId).collection('call_logs');

  CollectionReference<Map<String, dynamic>> get _desktopOutbox =>
      _firestore.collection('desktop_outbox');

  CollectionReference<Map<String, dynamic>> _incomingCallsFor(String userId) =>
      _firestore.collection('users').doc(userId).collection('incoming_calls');

  DocumentReference<Map<String, dynamic>> _activeCallFor(String userId) =>
      _firestore
          .collection('users')
          .doc(userId)
          .collection('active_call')
          .doc('current');

  Stream<List<CallLog>> watchCallLogs() {
    return watchCallLogsFor(_auth.currentUser!.uid);
  }

  Stream<List<CallLog>> watchCallLogsFor(String userId) {
    if (userId.isEmpty) return Stream.value(const <CallLog>[]);
    return _callLogsFor(userId)
        .orderBy('startedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(CallLog.fromDoc).toList());
  }

  Stream<CallInvite?> watchIncomingCallInviteFor(String userId) {
    if (userId.isEmpty) return Stream.value(null);
    return _incomingCallsFor(userId)
        .where('status', isEqualTo: 'ringing')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      return CallInvite.fromDoc(snapshot.docs.first);
    });
  }

  Stream<ActiveCallSession?> watchActiveCallFor(String userId) {
    if (userId.isEmpty) return Stream.value(null);
    return _activeCallFor(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return ActiveCallSession.fromDoc(doc);
    });
  }

  Future<void> startCall({
    required AppUser contact,
    required String type,
  }) async {
    final me = await _profileRepository.getCurrentUser();
    if (me == null) throw Exception('No se encontro tu perfil.');

    final now = FieldValue.serverTimestamp();
    final callRef = _calls.doc();
    final myLog = _myCallLogs.doc();
    final theirLog = _firestore
        .collection('users')
        .doc(contact.uid)
        .collection('call_logs')
        .doc();

    final outgoing = {
      'contactId': contact.uid,
      'contactName': contact.name,
      'contactUsername': contact.username,
      'contactPhoto': contact.photoUrl,
      'type': type,
      'direction': 'outgoing',
      'status': 'started',
      'startedAt': now,
    };

    final incoming = {
      'contactId': me.uid,
      'contactName': me.name,
      'contactUsername': me.username,
      'contactPhoto': me.photoUrl,
      'type': type,
      'direction': 'incoming',
      'status': 'missed',
      'startedAt': now,
    };
    final incomingCall = _incomingCallsFor(contact.uid).doc();

    final batch = _firestore.batch();
    batch.set(myLog, outgoing);
    batch.set(theirLog, incoming);
    batch.set(callRef, {
      'callerUid': me.uid,
      'calleeUid': contact.uid,
      'type': type,
      'status': 'ringing',
      'createdAt': now,
      'updatedAt': now,
    });
    batch.set(incomingCall, {
      'callId': callRef.id,
      'callerUid': me.uid,
      'callerName': me.name,
      'callerUsername': me.username,
      'callerPhoto': me.photoUrl,
      'type': type,
      'status': 'ringing',
      'createdAt': now,
      'callerLogId': myLog.id,
      'receiverLogId': theirLog.id,
    });
    batch.set(_activeCallFor(me.uid), {
      'callId': callRef.id,
      'contactId': contact.uid,
      'contactName': contact.name,
      'contactUsername': contact.username,
      'contactPhoto': contact.photoUrl,
      'type': type,
      'status': 'ringing',
      'direction': 'outgoing',
      'screenSharing': false,
      'startedAt': now,
    });
    batch.set(_activeCallFor(contact.uid), {
      'callId': callRef.id,
      'contactId': me.uid,
      'contactName': me.name,
      'contactUsername': me.username,
      'contactPhoto': me.photoUrl,
      'type': type,
      'status': 'ringing',
      'direction': 'incoming',
      'screenSharing': false,
      'startedAt': now,
    });
    await batch.commit();
  }

  Future<void> answerIncomingCall(CallInvite invite) async {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null) return;
    final batch = _firestore.batch();
    batch.set(
      _incomingCallsFor(currentUid).doc(invite.id),
      {
        'status': 'accepted',
        'answeredAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    if (invite.receiverLogId.isNotEmpty) {
      batch.set(
        _callLogsFor(currentUid).doc(invite.receiverLogId),
        {
          'status': 'accepted',
        },
        SetOptions(merge: true),
      );
    }
    if (invite.callerLogId.isNotEmpty) {
      batch.set(
        _callLogsFor(invite.callerUid).doc(invite.callerLogId),
        {
          'status': 'accepted',
        },
        SetOptions(merge: true),
      );
    }
    batch.set(
      _activeCallFor(currentUid),
      {
        'status': 'active',
      },
      SetOptions(merge: true),
    );
    batch.set(
      _activeCallFor(invite.callerUid),
      {
        'status': 'active',
      },
      SetOptions(merge: true),
    );
    if (invite.callId.isNotEmpty) {
      batch.set(
        _calls.doc(invite.callId),
        {
          'status': 'active',
          'answeredAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> rejectIncomingCall(CallInvite invite) async {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null) return;
    final batch = _firestore.batch();
    batch.set(
      _incomingCallsFor(currentUid).doc(invite.id),
      {
        'status': 'rejected',
        'endedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    if (invite.receiverLogId.isNotEmpty) {
      batch.set(
        _callLogsFor(currentUid).doc(invite.receiverLogId),
        {
          'status': 'rejected',
        },
        SetOptions(merge: true),
      );
    }
    if (invite.callerLogId.isNotEmpty) {
      batch.set(
        _callLogsFor(invite.callerUid).doc(invite.callerLogId),
        {
          'status': 'missed',
        },
        SetOptions(merge: true),
      );
    }
    batch.set(
      _activeCallFor(currentUid),
      {
        'status': 'rejected',
      },
      SetOptions(merge: true),
    );
    batch.set(
      _activeCallFor(invite.callerUid),
      {
        'status': 'rejected',
      },
      SetOptions(merge: true),
    );
    if (invite.callId.isNotEmpty) {
      batch.set(
        _calls.doc(invite.callId),
        {
          'status': 'rejected',
          'endedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> acceptActiveCall(String userId) async {
    final session = await _activeCallFor(userId).get();
    final data = session.data();
    if (data == null) return;
    final contactId = data['contactId'] as String? ?? '';
    if (contactId.isEmpty) return;
    final batch = _firestore.batch();
    batch.set(
        _activeCallFor(userId), {'status': 'active'}, SetOptions(merge: true));
    batch.set(
      _activeCallFor(contactId),
      {'status': 'active'},
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<void> switchCallType(String userId) async {
    final session = await _activeCallFor(userId).get();
    final data = session.data();
    if (data == null) return;
    final contactId = data['contactId'] as String? ?? '';
    final currentType = data['type'] as String? ?? 'audio';
    final nextType = currentType == 'video' ? 'audio' : 'video';
    final callId = data['callId'] as String? ?? '';
    final batch = _firestore.batch();
    batch.set(
        _activeCallFor(userId), {'type': nextType}, SetOptions(merge: true));
    if (contactId.isNotEmpty) {
      batch.set(_activeCallFor(contactId), {'type': nextType},
          SetOptions(merge: true));
    }
    if (callId.isNotEmpty) {
      batch.set(
        _calls.doc(callId),
        {
          'type': nextType,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> toggleScreenSharing(String userId) async {
    final session = await _activeCallFor(userId).get();
    final data = session.data();
    if (data == null) return;
    final contactId = data['contactId'] as String? ?? '';
    final current = data['screenSharing'] as bool? ?? false;
    final next = !current;
    final callId = data['callId'] as String? ?? '';
    final batch = _firestore.batch();
    batch.set(
      _activeCallFor(userId),
      {'screenSharing': next},
      SetOptions(merge: true),
    );
    if (contactId.isNotEmpty) {
      batch.set(
        _activeCallFor(contactId),
        {'screenSharing': next},
        SetOptions(merge: true),
      );
    }
    if (callId.isNotEmpty) {
      batch.set(
        _calls.doc(callId),
        {
          'screenSharing': next,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> endActiveCall(String userId) async {
    final session = await _activeCallFor(userId).get();
    final data = session.data();
    if (data == null) return;
    final contactId = data['contactId'] as String? ?? '';
    final callId = data['callId'] as String? ?? '';
    final batch = _firestore.batch();
    batch.set(
        _activeCallFor(userId), {'status': 'ended'}, SetOptions(merge: true));
    if (contactId.isNotEmpty) {
      batch.set(
        _activeCallFor(contactId),
        {'status': 'ended'},
        SetOptions(merge: true),
      );
    }
    if (callId.isNotEmpty) {
      batch.set(
        _calls.doc(callId),
        {
          'status': 'ended',
          'endedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> enqueueLinkedDesktopCallRequest({
    required String ownerUid,
    required AppUser contact,
    required String type,
  }) async {
    final creatorUid = _auth.currentUser?.uid;
    if (creatorUid == null) {
      throw Exception('No encontramos la sesion de Windows.');
    }
    await _desktopOutbox.doc().set({
      'creatorUid': creatorUid,
      'ownerUid': ownerUid,
      'type': 'call_request',
      'callType': type,
      'contactUid': contact.uid,
      'contactName': contact.name,
      'contactUsername': contact.username,
      'contactPhoto': contact.photoUrl,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> processDesktopCallRequest(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) async {
    final data = document.data();
    final ownerUid = data['ownerUid'] as String? ?? '';
    if (ownerUid.isEmpty || _auth.currentUser?.uid != ownerUid) return;
    if ((data['type'] as String? ?? '') != 'call_request') return;

    await startCall(
      contact: AppUser(
        uid: data['contactUid'] as String? ?? '',
        username: data['contactUsername'] as String? ?? '',
        usernameLower: (data['contactUsername'] as String? ?? '').toLowerCase(),
        name: data['contactName'] as String? ?? 'Contacto',
        email: '',
        photoUrl: data['contactPhoto'] as String? ?? '',
        bio: '',
        createdAt: null,
        isOnline: false,
        lastSeen: null,
      ),
      type: data['callType'] as String? ?? 'audio',
    );
    await document.reference.set({
      'status': 'processed',
      'processedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
