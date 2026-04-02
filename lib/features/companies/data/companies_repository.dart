import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stream_chat_flutter_core/stream_chat_flutter_core.dart' as stream;

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/services/stream_chat_service.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/company.dart';
import '../../../shared/models/company_member_profile.dart';

final companiesRepositoryProvider = Provider<CompaniesRepository>((ref) {
  return CompaniesRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseAuthProvider),
    ref.watch(streamChatServiceProvider),
  );
});

final currentUserCompaniesProvider = StreamProvider<List<Company>>((ref) {
  return ref
      .watch(companiesRepositoryProvider)
      .watchCurrentUserCompanies(onlyActive: true);
});

final allCurrentUserCompaniesProvider = StreamProvider<List<Company>>((ref) {
  return ref
      .watch(companiesRepositoryProvider)
      .watchCurrentUserCompanies(onlyActive: false);
});

final companyProvider =
    StreamProvider.family<Company?, String>((ref, companyId) {
  return ref.watch(companiesRepositoryProvider).watchCompany(companyId);
});

final companyMembersProvider =
    StreamProvider.family<List<AppUser>, String>((ref, companyId) {
  return ref.watch(companiesRepositoryProvider).watchCompanyMembers(companyId);
});

final companyMemberContactsProvider =
    StreamProvider.family<List<CompanyMemberContact>, String>((ref, companyId) {
  return ref
      .watch(companiesRepositoryProvider)
      .watchCompanyMemberContacts(companyId);
});

final myCompanyMemberProfileProvider =
    StreamProvider.family<CompanyMemberProfile?, String>((ref, companyId) {
  return ref
      .watch(companiesRepositoryProvider)
      .watchMyCompanyMemberProfile(companyId);
});

final companyMemberProfileProvider = StreamProvider.family<
    CompanyMemberProfile?,
    ({String companyId, String userId})>((ref, params) {
  return ref.watch(companiesRepositoryProvider).watchCompanyMemberProfile(
        companyId: params.companyId,
        userId: params.userId,
      );
});

class CompaniesRepository {
  CompaniesRepository(this._firestore, this._auth, this._streamChatService);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final StreamChatService _streamChatService;

  String? get _uid => _auth.currentUser?.uid;
  stream.StreamChatClient? get _streamClient => _streamChatService.client;

  CollectionReference<Map<String, dynamic>> get _companies =>
      _firestore.collection('companies');
  CollectionReference<Map<String, dynamic>> get _chats =>
      _firestore.collection('chats');
  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> _memberProfiles(String companyId) =>
      _companies.doc(companyId).collection('members');

  Stream<List<Company>> watchCurrentUserCompanies({
    bool onlyActive = true,
  }) {
    final uid = _uid;
    if (uid == null || uid.isEmpty) {
      return Stream.value(const []);
    }

    return _firestore
        .collection('companies')
        .where('memberIds', arrayContains: uid)
        .snapshots()
        .map((snapshot) {
      final companies = snapshot.docs.map(Company.fromDoc).where((company) {
        return !onlyActive || company.isActive;
      }).toList()
        ..sort((a, b) {
          final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });
      return companies;
    });
  }

  Stream<Company?> watchCompany(String companyId) {
    if (companyId.isEmpty) return Stream.value(null);
    return _companies.doc(companyId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Company.fromDoc(doc);
    });
  }

  Stream<List<AppUser>> watchCompanyMembers(String companyId) {
    if (companyId.isEmpty) return Stream.value(const []);
    return _companies.doc(companyId).snapshots().asyncMap((doc) async {
      if (!doc.exists) return const <AppUser>[];
      final company = Company.fromDoc(doc);
      final ids = company.memberIds.where((id) => id.isNotEmpty).toList();
      if (ids.isEmpty) return const <AppUser>[];

      final members = <AppUser>[];
      for (var index = 0; index < ids.length; index += 30) {
        final chunk = ids.skip(index).take(30).toList();
        final snapshot =
            await _users.where(FieldPath.documentId, whereIn: chunk).get();
        members.addAll(snapshot.docs.map(AppUser.fromDoc));
      }

      members.sort((left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()));
      return members;
    });
  }

  Stream<List<CompanyMemberContact>> watchCompanyMemberContacts(
      String companyId) {
    if (companyId.isEmpty) return Stream.value(const []);
    return watchCompany(companyId).asyncMap((company) async {
      if (company == null) return const <CompanyMemberContact>[];
      final members = await watchCompanyMembers(companyId).first;
      final profileSnapshots = await _memberProfiles(companyId).get();
      final profiles = {
        for (final doc in profileSnapshots.docs)
          doc.id: CompanyMemberProfile.fromDoc(doc, companyId: companyId),
      };

      final contacts = members
          .map((user) {
            return CompanyMemberContact(
              user: user,
              profile: profiles[user.uid] ??
                  CompanyMemberProfile.empty(
                    companyId: companyId,
                    userId: user.uid,
                  ),
            );
          })
          .where((contact) => contact.profile.isVisible)
          .toList()
        ..sort((left, right) => left.displayName.toLowerCase().compareTo(
              right.displayName.toLowerCase(),
            ));

      return contacts;
    });
  }

  Stream<CompanyMemberProfile?> watchMyCompanyMemberProfile(String companyId) {
    final uid = _uid;
    if (uid == null || uid.isEmpty || companyId.isEmpty) {
      return Stream.value(null);
    }
    return _memberProfiles(companyId).doc(uid).snapshots().map((doc) {
      if (!doc.exists) {
        return CompanyMemberProfile.empty(companyId: companyId, userId: uid);
      }
      return CompanyMemberProfile.fromDoc(doc, companyId: companyId);
    });
  }

  Stream<CompanyMemberProfile?> watchCompanyMemberProfile({
    required String companyId,
    required String userId,
  }) {
    if (companyId.isEmpty || userId.isEmpty) {
      return Stream.value(null);
    }
    return _memberProfiles(companyId).doc(userId).snapshots().map((doc) {
      if (!doc.exists) {
        return CompanyMemberProfile.empty(companyId: companyId, userId: userId);
      }
      return CompanyMemberProfile.fromDoc(doc, companyId: companyId);
    });
  }

  Future<String> createCompany({
    required AppUser owner,
    required String name,
    required String description,
    List<AppUser> initialMembers = const [],
  }) async {
    final companyRef = _companies.doc();
    final memberIds = <String>{
      owner.uid,
      ...initialMembers.map((user) => user.uid)
    };
    final batch = _firestore.batch();

    batch.set(companyRef, {
      'name': name.trim(),
      'description': description.trim(),
      'ownerId': owner.uid,
      'adminIds': [owner.uid],
      'memberIds': memberIds.toList(),
      'planStatus': 'trial',
      'planName': 'business',
      'planSource': '',
      'logoUrl': '',
      'subscriptionProductId': '',
      'subscriptionBasePlanId': '',
      'subscriptionOfferId': '',
      'subscriptionRenewsAt': null,
      'billingLastVerifiedAt': null,
      'billingStatusMessage': 'Activa tu suscripcion desde Google Play.',
      'createdAt': FieldValue.serverTimestamp(),
    });

    for (final user in [owner, ...initialMembers]) {
      batch.set(
        companyRef.collection('members').doc(user.uid),
        _defaultMemberProfileData(user),
      );
    }

    await batch.commit();

    return companyRef.id;
  }

  Future<void> addMembers({
    required String companyId,
    required List<AppUser> users,
  }) async {
    if (users.isEmpty) return;
    final companyRef = _companies.doc(companyId);
    final batch = _firestore.batch();
    batch.set(
        companyRef,
        {
          'memberIds':
              FieldValue.arrayUnion(users.map((user) => user.uid).toList()),
        },
        SetOptions(merge: true));

    for (final user in users) {
      batch.set(
        _memberProfiles(companyId).doc(user.uid),
        _defaultMemberProfileData(user),
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }

  Future<void> removeMember({
    required String companyId,
    required String userId,
  }) async {
    final batch = _firestore.batch();
    batch.set(
        _companies.doc(companyId),
        {
          'memberIds': FieldValue.arrayRemove([userId]),
          'adminIds': FieldValue.arrayRemove([userId]),
        },
        SetOptions(merge: true));
    batch.delete(_memberProfiles(companyId).doc(userId));
    await batch.commit();
  }

  Future<void> setAdmin({
    required String companyId,
    required String userId,
    required bool enabled,
  }) async {
    await _companies.doc(companyId).set({
      'adminIds': enabled
          ? FieldValue.arrayUnion([userId])
          : FieldValue.arrayRemove([userId]),
    }, SetOptions(merge: true));
  }

  Future<String> createCompanyChannel({
    required Company company,
    required AppUser currentUser,
    required String title,
    required String description,
    required bool onlyAdminsCanPost,
    List<AppUser> selectedUsers = const [],
  }) async {
    final chatRef = _chats.doc(_chats.doc().id.toLowerCase());
    final members = <String>{
      currentUser.uid,
      ...company.memberIds,
      ...selectedUsers.map((user) => user.uid),
    }.toList();

    final usersSnapshot = await _firestore
        .collection('users')
        .where(FieldPath.documentId, whereIn: members.take(30).toList())
        .get();

    final memberNames = <String, String>{};
    final memberUsernames = <String, String>{};
    final memberPhotos = <String, String>{};

    for (final doc in usersSnapshot.docs) {
      final user = AppUser.fromDoc(doc);
      memberNames[user.uid] = user.name;
      memberUsernames[user.uid] = user.username;
      memberPhotos[user.uid] = user.photoUrl;
    }

    await chatRef.set({
      'members': members,
      'memberNames': memberNames,
      'memberUsernames': memberUsernames,
      'memberPhotos': memberPhotos,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderId': '',
      'type': 'channel',
      'title': title.trim(),
      'description': description.trim(),
      'adminIds': company.adminIds,
      'moderatorIds': [],
      'pinnedBy': [],
      'archivedBy': [],
      'typingUsers': [],
      'recordingUsers': [],
      'ownerId': company.ownerId,
      'photoUrl': company.logoUrl,
      'coverUrl': '',
      'inviteCode': '',
      'pinnedMessageId': '',
      'onlyAdminsCanPost': onlyAdminsCanPost,
      'directMessageRequestStatus': 'accepted',
      'directMessageRequestInitiatorId': '',
      'directMessageRequestRecipientId': '',
      'directMessageRequestLimit': 0,
      'directMessageRequestSentCount': 0,
      'unreadCounts': {
        for (final memberId in members) memberId: 0,
      },
      'scope': 'company',
      'companyId': company.id,
      'companyName': company.name,
    });

    await _ensureStreamCompanyChannel(
      chatId: chatRef.id,
      company: company,
      currentUser: currentUser,
      title: title,
      description: description,
      onlyAdminsCanPost: onlyAdminsCanPost,
      selectedUsers: selectedUsers,
    );

    return chatRef.id;
  }

  Future<String> createOrGetCompanyDirectChat({
    required Company company,
    required AppUser currentUser,
    required AppUser otherUser,
  }) async {
    final ids = [currentUser.uid, otherUser.uid]..sort();
    final chatId = '${company.id}_${ids.join('_')}'.toLowerCase();
    final doc = _chats.doc(chatId);
    final snapshot = await doc.get();

    if (!snapshot.exists) {
      await doc.set({
        'members': ids,
        'memberNames': {
          currentUser.uid: currentUser.name,
          otherUser.uid: otherUser.name,
        },
        'memberUsernames': {
          currentUser.uid: currentUser.username,
          otherUser.uid: otherUser.username,
        },
        'memberPhotos': {
          currentUser.uid: currentUser.photoUrl,
          otherUser.uid: otherUser.photoUrl,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageSenderId': '',
        'type': 'direct',
        'title': '',
        'description': '',
        'adminIds': [],
        'moderatorIds': [],
        'pinnedBy': [],
        'archivedBy': [],
        'typingUsers': [],
        'recordingUsers': [],
        'ownerId': '',
        'photoUrl': '',
        'coverUrl': '',
        'inviteCode': '',
        'pinnedMessageId': '',
        'onlyAdminsCanPost': false,
        'directMessageRequestStatus': 'accepted',
        'directMessageRequestInitiatorId': '',
        'directMessageRequestRecipientId': '',
        'directMessageRequestLimit': 0,
        'directMessageRequestSentCount': 0,
        'unreadCounts': {
          currentUser.uid: 0,
          otherUser.uid: 0,
        },
        'scope': 'company',
        'companyId': company.id,
        'companyName': company.name,
      });
    }

    await _ensureStreamCompanyDirectChat(
      chatId: chatId,
      company: company,
      currentUser: currentUser,
      otherUser: otherUser,
    );

    return chatId;
  }

  Future<void> saveMyCompanyMemberProfile({
    required String companyId,
    required String displayName,
    required String roleTitle,
    required String department,
    required String workEmail,
    required String workPhone,
    required String notes,
    required bool isVisible,
  }) async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) {
      throw Exception('No hay una sesion activa.');
    }

    await _memberProfiles(companyId).doc(uid).set({
      'displayName': displayName.trim(),
      'roleTitle': roleTitle.trim(),
      'department': department.trim(),
      'workEmail': workEmail.trim(),
      'workPhone': workPhone.trim(),
      'notes': notes.trim(),
      'isVisible': isVisible,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Map<String, dynamic> _defaultMemberProfileData(AppUser user) {
    return {
      'displayName': user.name,
      'roleTitle': '',
      'department': '',
      'workEmail': user.email,
      'workPhone': '',
      'notes': '',
      'isVisible': true,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> _ensureStreamCompanyChannel({
    required String chatId,
    required Company company,
    required AppUser currentUser,
    required String title,
    required String description,
    required bool onlyAdminsCanPost,
    required List<AppUser> selectedUsers,
  }) async {
    final client = _streamClient;
    if (client == null) return;

    final companyMembers = await watchCompanyMembers(company.id).first;
    final uniqueUsers = <String, AppUser>{
      currentUser.uid: currentUser,
      for (final member in companyMembers) member.uid: member,
      for (final member in selectedUsers) member.uid: member,
    };
    final users = uniqueUsers.values.toList();

    final channel = client.channel(
      'messaging',
      id: chatId,
      extraData: {
        'members': users.map((user) => user.uid).toList(),
        'name': title.trim(),
        'title': title.trim(),
        'description': description.trim(),
        'memberNames': {
          for (final user in users) user.uid: user.name,
        },
        'memberUsernames': {
          for (final user in users) user.uid: user.username,
        },
        'memberPhotos': {
          for (final user in users) user.uid: user.photoUrl,
        },
        'messeya_chat_type': 'channel',
        'adminIds': company.adminIds,
        'moderatorIds': const <String>[],
        'ownerId': company.ownerId,
        'photoUrl': company.logoUrl,
        'coverUrl': '',
        'inviteCode': '',
        'pinnedMessageId': '',
        'onlyAdminsCanPost': onlyAdminsCanPost,
        'directMessageRequestStatus': 'accepted',
        'directMessageRequestInitiatorId': '',
        'directMessageRequestRecipientId': '',
        'directMessageRequestLimit': 0,
        'directMessageRequestSentCount': 0,
        'scope': 'company',
        'companyId': company.id,
        'companyName': company.name,
      },
    );

    await channel.watch();
  }

  Future<void> _ensureStreamCompanyDirectChat({
    required String chatId,
    required Company company,
    required AppUser currentUser,
    required AppUser otherUser,
  }) async {
    final client = _streamClient;
    if (client == null) return;

    final channel = client.channel(
      'messaging',
      id: chatId,
      extraData: {
        'members': [currentUser.uid, otherUser.uid],
        'memberNames': {
          currentUser.uid: currentUser.name,
          otherUser.uid: otherUser.name,
        },
        'memberUsernames': {
          currentUser.uid: currentUser.username,
          otherUser.uid: otherUser.username,
        },
        'memberPhotos': {
          currentUser.uid: currentUser.photoUrl,
          otherUser.uid: otherUser.photoUrl,
        },
        'messeya_chat_type': 'direct',
        'title': '',
        'description': '',
        'adminIds': const <String>[],
        'moderatorIds': const <String>[],
        'ownerId': '',
        'photoUrl': '',
        'coverUrl': '',
        'inviteCode': '',
        'pinnedMessageId': '',
        'onlyAdminsCanPost': false,
        'directMessageRequestStatus': 'accepted',
        'directMessageRequestInitiatorId': '',
        'directMessageRequestRecipientId': '',
        'directMessageRequestLimit': 0,
        'directMessageRequestSentCount': 0,
        'scope': 'company',
        'companyId': company.id,
        'companyName': company.name,
      },
    );

    await channel.watch();
  }
}
