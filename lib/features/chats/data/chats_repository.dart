import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_preferences_service.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/services/cloudinary_media_service.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/chat.dart';

final chatsRepositoryProvider = Provider<ChatsRepository>((ref) {
  return ChatsRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseAuthProvider),
    ref.watch(cloudinaryMediaServiceProvider),
    ref.watch(appPreferencesServiceProvider),
  );
});

final userChatsProvider = StreamProvider<List<Chat>>((ref) {
  return ref.watch(chatsRepositoryProvider).watchUserChats();
});

final userChatsForProvider =
    StreamProvider.family<List<Chat>, String>((ref, userId) {
  return ref.watch(chatsRepositoryProvider).watchUserChatsFor(userId);
});

final archivedChatsProvider = StreamProvider<List<Chat>>((ref) {
  return ref.watch(chatsRepositoryProvider).watchArchivedChats();
});

final chatProvider = StreamProvider.family<Chat?, String>((ref, chatId) {
  return ref.watch(chatsRepositoryProvider).watchChat(chatId);
});

class ChatsRepository {
  ChatsRepository(
      this._firestore, this._auth, this._cloudinary, this._preferences);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final CloudinaryMediaService _cloudinary;
  final AppPreferencesService _preferences;

  CollectionReference<Map<String, dynamic>> get _chats =>
      _firestore.collection('chats');

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  String get _uid => _auth.currentUser!.uid;

  Stream<List<Chat>> watchUserChats() {
    return watchUserChatsFor(_uid);
  }

  Stream<List<Chat>> watchUserChatsFor(String userId) {
    return _chats
        .where('members', arrayContains: userId)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs.map(Chat.fromDoc).where((chat) {
        return !chat.archivedBy.contains(userId);
      }).toList();

      items.sort((a, b) {
        final aPinned = a.pinnedBy.contains(userId);
        final bPinned = b.pinnedBy.contains(userId);
        if (aPinned != bPinned) return aPinned ? -1 : 1;
        final aTime = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      return items;
    });
  }

  Stream<List<Chat>> watchArchivedChats() {
    return watchArchivedChatsFor(_uid);
  }

  Stream<List<Chat>> watchArchivedChatsFor(String userId) {
    return _chats
        .where('members', arrayContains: userId)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs.map(Chat.fromDoc).where((chat) {
        return chat.archivedBy.contains(userId);
      }).toList();

      items.sort((a, b) {
        final aTime = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      return items;
    });
  }

  Stream<Chat?> watchChat(String chatId) {
    return _chats.doc(chatId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Chat.fromDoc(doc);
    });
  }

  Future<void> setTyping({
    required String chatId,
    required bool isTyping,
  }) async {
    final value = isTyping
        ? FieldValue.arrayUnion([_uid])
        : FieldValue.arrayRemove([_uid]);
    await _chats.doc(chatId).set({
      'typingUsers': value,
    }, SetOptions(merge: true));
  }

  Future<void> setRecording({
    required String chatId,
    required bool isRecording,
  }) async {
    final value = isRecording
        ? FieldValue.arrayUnion([_uid])
        : FieldValue.arrayRemove([_uid]);
    await _chats.doc(chatId).set({
      'recordingUsers': value,
    }, SetOptions(merge: true));
  }

  Future<void> togglePinned(String chatId, {required bool pinned}) async {
    await _chats.doc(chatId).set({
      'pinnedBy': pinned
          ? FieldValue.arrayUnion([_uid])
          : FieldValue.arrayRemove([_uid]),
    }, SetOptions(merge: true));
  }

  Future<void> toggleArchived(String chatId, {required bool archived}) async {
    await _chats.doc(chatId).set({
      'archivedBy': archived
          ? FieldValue.arrayUnion([_uid])
          : FieldValue.arrayRemove([_uid]),
      if (!archived) 'lastMessageAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateMemberRole({
    required String chatId,
    required String userId,
    required String role,
    required bool enabled,
  }) async {
    final field = role == 'admin' ? 'adminIds' : 'moderatorIds';
    await _chats.doc(chatId).set({
      field: enabled
          ? FieldValue.arrayUnion([userId])
          : FieldValue.arrayRemove([userId]),
    }, SetOptions(merge: true));
  }

  Future<void> removeMember({
    required String chatId,
    required AppUser user,
  }) async {
    await _chats.doc(chatId).set({
      'members': FieldValue.arrayRemove([user.uid]),
      'adminIds': FieldValue.arrayRemove([user.uid]),
      'moderatorIds': FieldValue.arrayRemove([user.uid]),
      'memberNames.${user.uid}': FieldValue.delete(),
      'memberUsernames.${user.uid}': FieldValue.delete(),
      'memberPhotos.${user.uid}': FieldValue.delete(),
      'typingUsers': FieldValue.arrayRemove([user.uid]),
      'recordingUsers': FieldValue.arrayRemove([user.uid]),
    }, SetOptions(merge: true));
  }

  Future<void> transferOwnership({
    required String chatId,
    required AppUser newOwner,
  }) async {
    await _chats.doc(chatId).set({
      'ownerId': newOwner.uid,
      'adminIds': FieldValue.arrayUnion([newOwner.uid]),
    }, SetOptions(merge: true));
  }

  Future<void> setOnlyAdminsCanPost({
    required String chatId,
    required bool enabled,
  }) async {
    await _chats.doc(chatId).set({
      'onlyAdminsCanPost': enabled,
    }, SetOptions(merge: true));
  }

  Future<void> pinPost({
    required String chatId,
    required String messageId,
  }) async {
    await _chats.doc(chatId).set({
      'pinnedMessageId': messageId,
    }, SetOptions(merge: true));
  }

  Future<void> clearPinnedPost(String chatId) async {
    await _chats.doc(chatId).set({
      'pinnedMessageId': '',
    }, SetOptions(merge: true));
  }

  Future<void> updateSpaceDetails({
    required String chatId,
    required String title,
    required String description,
  }) async {
    await _chats.doc(chatId).set({
      'title': title.trim(),
      'description': description.trim(),
    }, SetOptions(merge: true));
  }

  Future<void> updateSpaceMedia({
    required String chatId,
    File? photoFile,
    File? coverFile,
  }) async {
    final updates = <String, dynamic>{};
    if (photoFile != null) {
      updates['photoUrl'] = await _cloudinary.uploadImage(
        file: photoFile,
        folder: 'messeya/space_media/$chatId',
        publicId: 'photo',
      );
    }
    if (coverFile != null) {
      updates['coverUrl'] = await _cloudinary.uploadImage(
        file: coverFile,
        folder: 'messeya/space_media/$chatId',
        publicId: 'cover',
      );
    }
    if (updates.isEmpty) return;
    await _chats.doc(chatId).set(updates, SetOptions(merge: true));
  }

  String buildInviteLink(Chat chat) {
    return 'messeya://join/${chat.inviteCode.isEmpty ? chat.id : chat.inviteCode}';
  }

  Future<String> regenerateInviteCode(String chatId) async {
    final code = _generateInviteCode();
    await _chats.doc(chatId).set({
      'inviteCode': code,
    }, SetOptions(merge: true));
    return code;
  }

  Future<String> joinSpaceByInviteCode(String rawCode) async {
    final code = _sanitizeInviteCode(rawCode);
    if (code.isEmpty) {
      throw Exception('El enlace o codigo no es valido.');
    }

    final query =
        await _chats.where('inviteCode', isEqualTo: code).limit(1).get();
    if (query.docs.isEmpty) {
      throw Exception('No encontramos un grupo o canal con ese enlace.');
    }

    final chatDoc = query.docs.first;
    final userDoc = await _users.doc(_uid).get();
    final currentName = userDoc.data()?['name'] as String? ?? 'Usuario';
    final currentUsername = userDoc.data()?['username'] as String? ?? '';
    final currentPhoto = userDoc.data()?['photoUrl'] as String? ?? '';

    await chatDoc.reference.set({
      'members': FieldValue.arrayUnion([_uid]),
      'memberNames.$_uid': currentName,
      'memberUsernames.$_uid': currentUsername,
      'memberPhotos.$_uid': currentPhoto,
    }, SetOptions(merge: true));

    return chatDoc.id;
  }

  Future<String> createOrGetDirectChat(
    AppUser otherUser,
    AppUser currentUser,
  ) async {
    final ids = [currentUser.uid, otherUser.uid]..sort();
    final chatId = ids.join('_');
    final doc = _chats.doc(chatId);
    final snapshot = await doc.get();

    if (!snapshot.exists) {
      final onlyUntrusted = _preferences.getOnlyRequestForUntrustedContacts();
      final trusted = onlyUntrusted
          ? await _areMutuallyTrusted(currentUser.uid, otherUser.uid)
          : false;
      final shouldRequireRequest = onlyUntrusted ? !trusted : true;
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
        'directMessageRequestStatus':
            shouldRequireRequest ? 'pending' : 'accepted',
        'directMessageRequestInitiatorId': currentUser.uid,
        'directMessageRequestRecipientId': otherUser.uid,
        'directMessageRequestLimit': shouldRequireRequest
            ? _preferences.getDirectMessageRequestLimit()
            : 0,
        'directMessageRequestSentCount': 0,
        'unreadCounts': {
          currentUser.uid: 0,
          otherUser.uid: 0,
        },
      });
    }

    return chatId;
  }

  Future<String> createSpace({
    required String type,
    required String title,
    required String description,
    required AppUser currentUser,
    required List<AppUser> selectedUsers,
  }) async {
    final doc = _chats.doc();
    final members = <String>{
      currentUser.uid,
      ...selectedUsers.map((user) => user.uid),
    }.toList();

    final memberNames = <String, String>{
      currentUser.uid: currentUser.name,
      for (final user in selectedUsers) user.uid: user.name,
    };
    final memberUsernames = <String, String>{
      currentUser.uid: currentUser.username,
      for (final user in selectedUsers) user.uid: user.username,
    };
    final memberPhotos = <String, String>{
      currentUser.uid: currentUser.photoUrl,
      for (final user in selectedUsers) user.uid: user.photoUrl,
    };

    await doc.set({
      'members': members,
      'memberNames': memberNames,
      'memberUsernames': memberUsernames,
      'memberPhotos': memberPhotos,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderId': '',
      'type': type,
      'title': title.trim(),
      'description': description.trim(),
      'adminIds': [currentUser.uid],
      'moderatorIds': [],
      'pinnedBy': [],
      'archivedBy': [],
      'typingUsers': [],
      'recordingUsers': [],
      'ownerId': currentUser.uid,
      'photoUrl': '',
      'coverUrl': '',
      'inviteCode': _generateInviteCode(),
      'pinnedMessageId': '',
      'onlyAdminsCanPost': type == 'channel',
      'directMessageRequestStatus': 'accepted',
      'directMessageRequestInitiatorId': '',
      'directMessageRequestRecipientId': '',
      'directMessageRequestLimit': 0,
      'directMessageRequestSentCount': 0,
      'unreadCounts': {
        for (final memberId in members) memberId: 0,
      },
    });

    return doc.id;
  }

  Future<void> updateDirectMessageRequest({
    required String chatId,
    required String status,
  }) async {
    final chatSnapshot = await _chats.doc(chatId).get();
    final chat = chatSnapshot.data() ?? const <String, dynamic>{};
    final initiatorId =
        chat['directMessageRequestInitiatorId'] as String? ?? '';
    await _chats.doc(chatId).set({
      'directMessageRequestStatus': status,
      if (status == 'accepted') 'directMessageRequestSentCount': 0,
      if (status == 'declined' && _preferences.getArchiveRejectedRequests())
        'archivedBy': FieldValue.arrayUnion([initiatorId]),
    }, SetOptions(merge: true));
  }

  Future<void> allowAlwaysContact({
    required String contactUserId,
  }) async {
    await _users
        .doc(_uid)
        .collection('trusted_contacts')
        .doc(contactUserId)
        .set({
      'uid': contactUserId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> _areMutuallyTrusted(
      String currentUserId, String otherUserId) async {
    final currentTrust = await _users
        .doc(currentUserId)
        .collection('trusted_contacts')
        .doc(otherUserId)
        .get();
    final otherTrust = await _users
        .doc(otherUserId)
        .collection('trusted_contacts')
        .doc(currentUserId)
        .get();
    return currentTrust.exists && otherTrust.exists;
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    return List.generate(
      10,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  String _sanitizeInviteCode(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.contains('/join/')) {
      return trimmed.split('/join/').last.trim();
    }
    if (trimmed.contains('messeya://join/')) {
      return trimmed.split('messeya://join/').last.trim();
    }
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  }
}
