import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stream_chat_flutter_core/stream_chat_flutter_core.dart' as stream;

import '../../../core/services/app_preferences_service.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../../core/services/cloudinary_media_service.dart';
import '../../../core/services/stream_chat_service.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/models/chat.dart';

final chatsRepositoryProvider = Provider<ChatsRepository>((ref) {
  return ChatsRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseAuthProvider),
    ref.watch(cloudinaryMediaServiceProvider),
    ref.watch(appPreferencesServiceProvider),
    ref.watch(streamChatServiceProvider),
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

final companyChatsProvider =
    StreamProvider.family<List<Chat>, String>((ref, companyId) {
  return ref.watch(chatsRepositoryProvider).watchCompanyChats(companyId);
});

final chatProvider = StreamProvider.family<Chat?, String>((ref, chatId) {
  return ref.watch(chatsRepositoryProvider).watchChat(chatId);
});

class ChatsRepository {
  ChatsRepository(
    this._firestore,
    this._auth,
    this._cloudinary,
    this._preferences,
    this._streamChatService,
  );

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final CloudinaryMediaService _cloudinary;
  final AppPreferencesService _preferences;
  final StreamChatService _streamChatService;

  CollectionReference<Map<String, dynamic>> get _chats =>
      _firestore.collection('chats');

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  String get _uid => _auth.currentUser!.uid;
  stream.StreamChatClient? get _streamClient => _streamChatService.client;
  // Firestore vuelve a ser la fuente principal para chats en cliente.
  bool get _useStream => false;

  Stream<List<Chat>> watchUserChats() {
    return watchUserChatsFor(_uid);
  }

  Stream<List<Chat>> watchUserChatsFor(String userId) {
    if (_canUseStreamForUser(userId)) {
      return _watchStreamUserChatsFor(userId);
    }

    return _chats
        .where('members', arrayContains: userId)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs.map(Chat.fromDoc).where((chat) {
        return chat.scope != 'company' && !chat.archivedBy.contains(userId);
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
    if (_canUseStreamForUser(userId)) {
      return _watchStreamUserChatsFor(userId).map(
        (items) => items.where((chat) => chat.archivedBy.contains(userId)).toList(),
      );
    }

    return _chats
        .where('members', arrayContains: userId)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs.map(Chat.fromDoc).where((chat) {
        return chat.scope != 'company' && chat.archivedBy.contains(userId);
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
    if (_canUseStreamForUser(_uid)) {
      return _watchStreamChat(chatId, _uid);
    }

    return _chats.doc(chatId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Chat.fromDoc(doc);
    });
  }

  Stream<List<Chat>> watchCompanyChats(String companyId) {
    if (_canUseStreamForUser(_uid)) {
      return _watchStreamUserChatsFor(_uid).map(
        (items) => items.where((chat) {
          return chat.companyId == companyId &&
              chat.scope == 'company' &&
              !chat.archivedBy.contains(_uid);
        }).toList(),
      );
    }

    return _chats
        .where('members', arrayContains: _uid)
        .where('scope', isEqualTo: 'company')
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs
          .map(Chat.fromDoc)
          .where((chat) =>
              chat.companyId == companyId && !chat.archivedBy.contains(_uid))
          .toList();

      items.sort((a, b) {
        final aPinned = a.pinnedBy.contains(_uid);
        final bPinned = b.pinnedBy.contains(_uid);
        if (aPinned != bPinned) return aPinned ? -1 : 1;
        final aTime = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      return items;
    });
  }

  Future<void> setTyping({
    required String chatId,
    required bool isTyping,
  }) async {
    if (!_useStream) {
      await _chats.doc(chatId).update({
        'typingUsers': isTyping
            ? FieldValue.arrayUnion([_uid])
            : FieldValue.arrayRemove([_uid]),
      });
      return;
    }

    final channel = await _resolveStreamChannel(chatId);
    if (isTyping) {
      await channel.keyStroke();
    } else {
      await channel.stopTyping();
    }
  }

  Future<void> setRecording({
    required String chatId,
    required bool isRecording,
  }) async {
    return;
  }

  Future<void> togglePinned(String chatId, {required bool pinned}) async {
    if (!_useStream) {
      await _chats.doc(chatId).update({
        'pinnedBy': pinned
            ? FieldValue.arrayUnion([_uid])
            : FieldValue.arrayRemove([_uid]),
      });
      return;
    }

    final channel = await _resolveStreamChannel(chatId);
    if (pinned) {
      await channel.pin();
    } else {
      await channel.unpin();
    }
  }

  Future<void> toggleArchived(String chatId, {required bool archived}) async {
    if (!_useStream) {
      await _chats.doc(chatId).update({
        'archivedBy': archived
            ? FieldValue.arrayUnion([_uid])
            : FieldValue.arrayRemove([_uid]),
      });
      return;
    }

    final channel = await _resolveStreamChannel(chatId);
    if (archived) {
      await channel.archive();
    } else {
      await channel.unarchive();
    }
  }

  Future<void> resetUnreadCount(String chatId, {String? userId}) async {
    if (!_useStream) {
      final targetUserId = userId ?? _uid;
      await _chats.doc(chatId).update({'unreadCounts.$targetUserId': 0});
      return;
    }

    final channel = await _resolveStreamChannel(chatId);
    await channel.markRead();
  }

  Future<void> updateMemberRole({
    required String chatId,
    required String userId,
    required String role,
    required bool enabled,
  }) async {
    if (!_useStream) {
      final field = role == 'admin' ? 'adminIds' : 'moderatorIds';
      await _chats.doc(chatId).update({
        field: enabled
            ? FieldValue.arrayUnion([userId])
            : FieldValue.arrayRemove([userId]),
      });
      return;
    }

    final field = role == 'admin' ? 'adminIds' : 'moderatorIds';
    final channel = await _resolveStreamChannel(chatId);
    final values = _resolveStringList(channel.extraData[field]);
    final updated = enabled
        ? <String>{...values, userId}.toList()
        : values.where((value) => value != userId).toList();
    await channel.updatePartial(set: {field: updated});
  }

  Future<void> removeMember({
    required String chatId,
    required AppUser user,
  }) async {
    if (!_useStream) {
      final chatRef = _chats.doc(chatId);
      final snapshot = await chatRef.get();
      final data = snapshot.data() ?? const <String, dynamic>{};
      final memberNames =
          Map<String, dynamic>.from(data['memberNames'] as Map? ?? const {});
      final memberUsernames = Map<String, dynamic>.from(
        data['memberUsernames'] as Map? ?? const {},
      );
      final memberPhotos =
          Map<String, dynamic>.from(data['memberPhotos'] as Map? ?? const {});

      memberNames.remove(user.uid);
      memberUsernames.remove(user.uid);
      memberPhotos.remove(user.uid);

      await chatRef.update({
        'members': FieldValue.arrayRemove([user.uid]),
        'memberNames': memberNames,
        'memberUsernames': memberUsernames,
        'memberPhotos': memberPhotos,
        'adminIds': FieldValue.arrayRemove([user.uid]),
        'moderatorIds': FieldValue.arrayRemove([user.uid]),
      });
      return;
    }

    final channel = await _resolveStreamChannel(chatId);
    final memberNames = _resolveStringMap(channel.extraData['memberNames'])
      ..remove(user.uid);
    final memberUsernames = _resolveStringMap(channel.extraData['memberUsernames'])
      ..remove(user.uid);
    final memberPhotos = _resolveStringMap(channel.extraData['memberPhotos'])
      ..remove(user.uid);
    final adminIds = _resolveStringList(channel.extraData['adminIds'])
        .where((value) => value != user.uid)
        .toList();
    final moderatorIds = _resolveStringList(channel.extraData['moderatorIds'])
        .where((value) => value != user.uid)
        .toList();

    await channel.removeMembers([user.uid]);
    await channel.updatePartial(set: {
      'memberNames': memberNames,
      'memberUsernames': memberUsernames,
      'memberPhotos': memberPhotos,
      'adminIds': adminIds,
      'moderatorIds': moderatorIds,
    });
  }

  Future<void> transferOwnership({
    required String chatId,
    required AppUser newOwner,
  }) async {
    if (!_useStream) {
      await _chats.doc(chatId).update({
        'ownerId': newOwner.uid,
        'adminIds': FieldValue.arrayUnion([newOwner.uid]),
      });
      return;
    }

    final channel = await _resolveStreamChannel(chatId);
    final adminIds = <String>{
      ..._resolveStringList(channel.extraData['adminIds']),
      newOwner.uid,
    }.toList();
    await channel.updatePartial(set: {
      'ownerId': newOwner.uid,
      'adminIds': adminIds,
    });
  }

  Future<void> setOnlyAdminsCanPost({
    required String chatId,
    required bool enabled,
  }) async {
    if (!_useStream) {
      await _chats.doc(chatId).update({
        'onlyAdminsCanPost': enabled,
      });
      return;
    }

    final channel = await _resolveStreamChannel(chatId);
    await channel.updatePartial(set: {
      'onlyAdminsCanPost': enabled,
    });
  }

  Future<void> pinPost({
    required String chatId,
    required String messageId,
  }) async {
    if (!_useStream) {
      await _chats.doc(chatId).update({
        'pinnedMessageId': messageId,
      });
      return;
    }

    final channel = await _resolveStreamChannel(chatId);
    await channel.updatePartial(set: {
      'pinnedMessageId': messageId,
    });
  }

  Future<void> clearPinnedPost(String chatId) async {
    if (!_useStream) {
      await _chats.doc(chatId).update({
        'pinnedMessageId': '',
      });
      return;
    }

    final channel = await _resolveStreamChannel(chatId);
    await channel.updatePartial(set: {
      'pinnedMessageId': '',
    });
  }

  Future<void> updateSpaceDetails({
    required String chatId,
    required String title,
    required String description,
  }) async {
    if (!_useStream) {
      await _chats.doc(chatId).update({
        'title': title.trim(),
        'description': description.trim(),
      });
      return;
    }

    final channel = await _resolveStreamChannel(chatId);
    await channel.updatePartial(set: {
      'title': title.trim(),
      'name': title.trim(),
      'description': description.trim(),
    });
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
    if (!_useStream) {
      await _chats.doc(chatId).update(updates);
      return;
    }
    if (updates['photoUrl'] case final photoUrl?) {
      updates['image'] = photoUrl;
    }
    final channel = await _resolveStreamChannel(chatId);
    await channel.updatePartial(set: updates);
  }

  String buildInviteLink(Chat chat) {
    return 'messeya://join/${chat.inviteCode.isEmpty ? chat.id : chat.inviteCode}';
  }

  Future<String> regenerateInviteCode(String chatId) async {
    final code = _generateInviteCode();
    if (!_useStream) {
      await _chats.doc(chatId).update({
        'inviteCode': code,
      });
      return code;
    }
    final channel = await _resolveStreamChannel(chatId);
    await channel.updatePartial(set: {
      'inviteCode': code,
    });
    return code;
  }

  Future<String> joinSpaceByInviteCode(String rawCode) async {
    final code = _sanitizeInviteCode(rawCode);
    if (code.isEmpty) {
      throw Exception('El enlace o codigo no es valido.');
    }

    if (!_useStream) {
      final chats = await _chats
          .where('inviteCode', isEqualTo: code)
          .limit(1)
          .get();

      if (chats.docs.isEmpty) {
        throw Exception('No encontramos un grupo o canal con ese enlace.');
      }

      final chatRef = chats.docs.first.reference;
      final userDoc = await _users.doc(_uid).get();
      final currentName = userDoc.data()?['name'] as String? ?? 'Usuario';
      final currentUsername = userDoc.data()?['username'] as String? ?? '';
      final currentPhoto = userDoc.data()?['photoUrl'] as String? ?? '';
      final chatData = chats.docs.first.data();
      final members = List<String>.from(chatData['members'] as List? ?? const []);
      final unreadCounts = Map<String, dynamic>.from(
        chatData['unreadCounts'] as Map? ?? const <String, dynamic>{},
      );
      final memberNames =
          Map<String, dynamic>.from(chatData['memberNames'] as Map? ?? const {});
      final memberUsernames = Map<String, dynamic>.from(
        chatData['memberUsernames'] as Map? ?? const {},
      );
      final memberPhotos =
          Map<String, dynamic>.from(chatData['memberPhotos'] as Map? ?? const {});

      if (!members.contains(_uid)) {
        members.add(_uid);
      }
      memberNames[_uid] = currentName;
      memberUsernames[_uid] = currentUsername;
      memberPhotos[_uid] = currentPhoto;
      unreadCounts.putIfAbsent(_uid, () => 0);

      await chatRef.update({
        'members': members,
        'memberNames': memberNames,
        'memberUsernames': memberUsernames,
        'memberPhotos': memberPhotos,
        'unreadCounts': unreadCounts,
      });

      return chatRef.id;
    }

    final client = _streamClient;
    if (client == null) {
      throw StateError('Stream Chat no esta configurado.');
    }

    final channels = await client.queryChannels(
      filter: stream.Filter.and([
        stream.Filter.equal('type', 'messaging'),
        stream.Filter.equal('inviteCode', code),
      ]),
      state: true,
      watch: false,
      presence: false,
    ).first;

    if (channels.isEmpty) {
      throw Exception('No encontramos un grupo o canal con ese enlace.');
    }

    final channel = channels.first;
    final userDoc = await _users.doc(_uid).get();
    final currentName = userDoc.data()?['name'] as String? ?? 'Usuario';
    final currentUsername = userDoc.data()?['username'] as String? ?? '';
    final currentPhoto = userDoc.data()?['photoUrl'] as String? ?? '';

    final existingMembers = (channel.state?.members ?? const <stream.Member>[])
        .map((member) => member.userId)
        .whereType<String>()
        .toSet();
    if (!existingMembers.contains(_uid)) {
      await channel.addMembers([_uid]);
    }

    final memberNames = _resolveStringMap(channel.extraData['memberNames'])
      ..[_uid] = currentName;
    final memberUsernames = _resolveStringMap(channel.extraData['memberUsernames'])
      ..[_uid] = currentUsername;
    final memberPhotos = _resolveStringMap(channel.extraData['memberPhotos'])
      ..[_uid] = currentPhoto;

    await channel.updatePartial(set: {
      'memberNames': memberNames,
      'memberUsernames': memberUsernames,
      'memberPhotos': memberPhotos,
    });

    return channel.id ?? channel.cid?.split(':').last ?? '';
  }

  Future<String> createOrGetDirectChat(
    AppUser otherUser,
    AppUser currentUser,
  ) async {
    final ids = [currentUser.uid, otherUser.uid]..sort();
    final chatId = ids.join('_').toLowerCase();
    final onlyUntrusted = _preferences.getOnlyRequestForUntrustedContacts();

    if (!_useStream) {
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
          'adminIds': const <String>[],
          'moderatorIds': const <String>[],
          'pinnedBy': const <String>[],
          'archivedBy': const <String>[],
          'typingUsers': const <String>[],
          'recordingUsers': const <String>[],
          'ownerId': '',
          'photoUrl': '',
          'coverUrl': '',
          'inviteCode': '',
          'pinnedMessageId': '',
          'onlyAdminsCanPost': false,
          'directMessageRequestStatus':
              onlyUntrusted ? 'pending' : 'accepted',
          'directMessageRequestInitiatorId': currentUser.uid,
          'directMessageRequestRecipientId': otherUser.uid,
          'directMessageRequestLimit': onlyUntrusted
              ? _preferences.getDirectMessageRequestLimit()
              : 0,
          'directMessageRequestSentCount': 0,
          'unreadCounts': {
            currentUser.uid: 0,
            otherUser.uid: 0,
          },
          'scope': 'personal',
          'companyId': '',
          'companyName': '',
        });
      }

      return chatId;
    }

    await _ensureStreamChannelForDirectChat(
      chatId: chatId,
      currentUser: currentUser,
      otherUser: otherUser,
      onlyRequestForUntrustedContacts: onlyUntrusted,
    );

    return chatId;
  }

  Future<String> createSpace({
    required String type,
    required String title,
    required String description,
    required AppUser currentUser,
    required List<AppUser> selectedUsers,
  }) async {
    final chatId = _chats.doc().id.toLowerCase();

    if (!_useStream) {
      final members = <AppUser>[currentUser, ...selectedUsers];
      await _chats.doc(chatId).set({
        'members': members.map((user) => user.uid).toList(),
        'memberNames': {
          for (final user in members) user.uid: user.name,
        },
        'memberUsernames': {
          for (final user in members) user.uid: user.username,
        },
        'memberPhotos': {
          for (final user in members) user.uid: user.photoUrl,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageSenderId': '',
        'type': type,
        'title': title.trim(),
        'description': description.trim(),
        'adminIds': [currentUser.uid],
        'moderatorIds': const <String>[],
        'pinnedBy': const <String>[],
        'archivedBy': const <String>[],
        'typingUsers': const <String>[],
        'recordingUsers': const <String>[],
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
          for (final user in members) user.uid: 0,
        },
        'scope': 'personal',
        'companyId': '',
        'companyName': '',
      });
      return chatId;
    }

    await _ensureStreamChannelForSpace(
      chatId: chatId,
      type: type,
      title: title,
      description: description,
      currentUser: currentUser,
      selectedUsers: selectedUsers,
    );

    return chatId;
  }

  Future<void> updateDirectMessageRequest({
    required String chatId,
    required String status,
  }) async {
    if (!_useStream) {
      final chatRef = _chats.doc(chatId);
      final snapshot = await chatRef.get();
      final data = snapshot.data() ?? const <String, dynamic>{};
      final initiatorId =
          data['directMessageRequestInitiatorId'] as String? ?? '';
      final recipientId =
          data['directMessageRequestRecipientId'] as String? ?? '';

      await chatRef.update({
        'directMessageRequestStatus': status,
        if (status == 'accepted') 'directMessageRequestSentCount': 0,
      });

      if (status == 'accepted' &&
          initiatorId.isNotEmpty &&
          recipientId.isNotEmpty) {
        final now = FieldValue.serverTimestamp();
        final batch = _firestore.batch();
        batch.set(
          _users.doc(initiatorId).collection('contacts').doc(recipientId),
          {'addedAt': now},
        );
        batch.set(
          _users.doc(recipientId).collection('contacts').doc(initiatorId),
          {'addedAt': now},
        );
        await batch.commit();
      }
      return;
    }

    final channel = await _resolveStreamChannel(chatId);
    final initiatorId =
        channel.extraData['directMessageRequestInitiatorId'] as String? ?? '';
    final recipientId =
        channel.extraData['directMessageRequestRecipientId'] as String? ?? '';

    await channel.updatePartial(set: {
      'directMessageRequestStatus': status,
      if (status == 'accepted') 'directMessageRequestSentCount': 0,
    });

    if (status == 'accepted' && initiatorId.isNotEmpty && recipientId.isNotEmpty) {
      final now = FieldValue.serverTimestamp();

      final batch = _firestore.batch();
      batch.set(
        _users.doc(initiatorId).collection('contacts').doc(recipientId),
        {'addedAt': now},
      );
      batch.set(
        _users.doc(recipientId).collection('contacts').doc(initiatorId),
        {'addedAt': now},
      );
      await batch.commit();
    }
  }

  Future<List<String>> getAcceptedDirectContactIds(String userId) async {
    if (!_canUseStreamForUser(userId)) {
      final chats = await _firestore
          .collection('chats')
          .where('members', arrayContains: userId)
          .where('type', isEqualTo: 'direct')
          .get();
      final contacts = <String>{userId};
      for (final doc in chats.docs) {
        final data = doc.data();
        final status =
            data['directMessageRequestStatus'] as String? ?? 'accepted';
        if (status != 'accepted') continue;
        final members = List<String>.from(data['members'] as List? ?? const []);
        for (final memberId in members) {
          if (memberId != userId) contacts.add(memberId);
        }
      }
      return contacts.toList();
    }

    final chats = await _watchStreamUserChatsFor(userId).first;
    final contacts = <String>{userId};
    for (final chat in chats) {
      if (chat.type != 'direct') continue;
      if (chat.directMessageRequestStatus != 'accepted') continue;
      for (final memberId in chat.members) {
        if (memberId != userId) {
          contacts.add(memberId);
        }
      }
    }
    return contacts.toList();
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

  bool _canUseStreamForUser(String userId) {
    final authUser = _auth.currentUser;
    return _useStream && authUser != null && authUser.uid == userId;
  }

  Stream<List<Chat>> _watchStreamUserChatsFor(String userId) {
    return Stream.fromFuture(_streamChatService.waitForConnectedClient())
        .asyncExpand((client) {
      if (client == null) {
        return Stream.value(const <Chat>[]);
      }

      return client
          .queryChannels(
            filter: stream.Filter.and([
              stream.Filter.equal('type', 'messaging'),
              stream.Filter.in_('members', [userId]),
            ]),
            channelStateSort: [
              stream.SortOption<stream.ChannelState>.desc(
                stream.ChannelSortKey.lastMessageAt,
              ),
            ],
            state: true,
            watch: true,
            presence: true,
          )
          .map((channels) {
            final chats = channels
                .map((channel) => _mapStreamChat(channel, userId))
                .where((chat) =>
                    chat.scope != 'company' &&
                    !chat.archivedBy.contains(userId))
                .toList();

            chats.sort((a, b) {
              final aPinned = a.pinnedBy.contains(userId);
              final bPinned = b.pinnedBy.contains(userId);
              if (aPinned != bPinned) return aPinned ? -1 : 1;
              final aTime =
                  a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bTime =
                  b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bTime.compareTo(aTime);
            });

            return chats;
          });
    });
  }

  Stream<Chat?> _watchStreamChat(String chatId, String userId) {
    return _watchStreamUserChatsFor(userId).map((items) {
      for (final chat in items) {
        if (chat.id == chatId) return chat;
      }
      return null;
    });
  }

  Future<stream.Channel> _resolveStreamChannel(String chatId) async {
    final client = await _streamChatService.requireConnectedClient();

    final channel = client.channel('messaging', id: chatId);
    if (channel.state == null) {
      await channel.watch();
    }
    return channel;
  }

  Chat _mapStreamChat(stream.Channel channel, String currentUserId) {
    final extraData = channel.extraData;
    final members = channel.state?.members ?? const <stream.Member>[];
    final memberIds = members
        .map((member) => member.userId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();
    final memberNames = _resolveMemberNames(members, extraData);
    final memberUsernames = _resolveStringMap(extraData['memberUsernames']);
    final memberPhotos = _resolveMemberPhotos(members, extraData);
    final lastMessage = channel.state?.messages.isNotEmpty == true
        ? _previewStreamMessage(channel.state!.messages.last)
        : '';
    final lastMessageSenderId =
        channel.state?.messages.isNotEmpty == true ? channel.state!.messages.last.user?.id ?? '' : '';
    final channelType =
        (extraData['messeya_chat_type'] as String? ?? (channel.memberCount == 2 ? 'direct' : 'group')).trim();
    final scope = (extraData['scope'] as String? ?? 'personal').trim();
    final title = (extraData['title'] as String? ?? channel.name ?? '').trim();
    final photoUrl = (extraData['photoUrl'] as String? ?? channel.image ?? '').trim();

    return Chat(
      id: channel.id ?? channel.cid?.split(':').last ?? '',
      members: memberIds,
      memberNames: memberNames,
      memberUsernames: memberUsernames,
      memberPhotos: memberPhotos,
      createdAt: channel.createdAt?.toLocal(),
      lastMessage: lastMessage,
      lastMessageAt: channel.lastMessageAt?.toLocal() ?? channel.createdAt?.toLocal(),
      lastMessageSenderId: lastMessageSenderId,
      type: channelType.isEmpty ? 'direct' : channelType,
      title: title,
      description: (extraData['description'] as String? ?? '').trim(),
      adminIds: _resolveStringList(extraData['adminIds']),
      moderatorIds: _resolveStringList(extraData['moderatorIds']),
      pinnedBy: channel.isPinned ? <String>[currentUserId] : const <String>[],
      archivedBy: channel.isArchived ? <String>[currentUserId] : const <String>[],
      typingUsers: (channel.state?.typingEvents.keys ?? const <stream.User>[])
          .map((user) => user.id)
          .where((id) => id != currentUserId)
          .toList(),
      recordingUsers: const <String>[],
      ownerId: (extraData['ownerId'] as String? ?? channel.createdBy?.id ?? '').trim(),
      photoUrl: photoUrl,
      coverUrl: (extraData['coverUrl'] as String? ?? '').trim(),
      inviteCode: (extraData['inviteCode'] as String? ?? '').trim(),
      pinnedMessageId: (extraData['pinnedMessageId'] as String? ?? '').trim(),
      onlyAdminsCanPost: extraData['onlyAdminsCanPost'] as bool? ?? false,
      directMessageRequestStatus:
          (extraData['directMessageRequestStatus'] as String? ?? 'accepted').trim(),
      directMessageRequestInitiatorId:
          (extraData['directMessageRequestInitiatorId'] as String? ?? '').trim(),
      directMessageRequestRecipientId:
          (extraData['directMessageRequestRecipientId'] as String? ?? '').trim(),
      directMessageRequestLimit:
          (extraData['directMessageRequestLimit'] as num?)?.toInt() ?? 0,
      directMessageRequestSentCount:
          (extraData['directMessageRequestSentCount'] as num?)?.toInt() ?? 0,
      unreadCounts: <String, int>{
        currentUserId: channel.state?.unreadCount ?? 0,
      },
      scope: scope.isEmpty ? 'personal' : scope,
      companyId: (extraData['companyId'] as String? ?? '').trim(),
      companyName: (extraData['companyName'] as String? ?? '').trim(),
    );
  }

  Map<String, String> _resolveMemberNames(
    List<stream.Member> members,
    Map<String, Object?> extraData,
  ) {
    final names = _resolveStringMap(extraData['memberNames']);
    for (final member in members) {
      final userId = member.userId;
      final name = member.user?.name.trim() ?? '';
      if (userId == null || userId.isEmpty || name.isEmpty) continue;
      names[userId] = name;
    }
    return names;
  }

  Map<String, String> _resolveMemberPhotos(
    List<stream.Member> members,
    Map<String, Object?> extraData,
  ) {
    final photos = _resolveStringMap(extraData['memberPhotos']);
    for (final member in members) {
      final userId = member.userId;
      final photo = member.user?.image?.trim() ?? '';
      if (userId == null || userId.isEmpty || photo.isEmpty) continue;
      photos[userId] = photo;
    }
    return photos;
  }

  Map<String, String> _resolveStringMap(Object? rawValue) {
    if (rawValue is! Map) return <String, String>{};
    return rawValue.map(
      (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
    );
  }

  List<String> _resolveStringList(Object? rawValue) {
    if (rawValue is! List) return const <String>[];
    return rawValue.map((value) => value.toString()).toList();
  }

  String _previewStreamMessage(stream.Message message) {
    final subject = (message.extraData['subject'] as String? ?? '').trim();
    if (subject.isNotEmpty) return subject;

    final text = (message.text ?? '').trim();
    if (text.isNotEmpty) return text;

    if (message.attachments.isNotEmpty) {
      return 'Archivo adjunto';
    }

    return '';
  }

  Future<void> _ensureStreamChannelForDirectChat({
    required String chatId,
    required AppUser currentUser,
    required AppUser otherUser,
    required bool onlyRequestForUntrustedContacts,
  }) async {
    final client = await _streamChatService.requireConnectedClient();

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
        'directMessageRequestStatus':
            onlyRequestForUntrustedContacts ? 'pending' : 'accepted',
        'directMessageRequestInitiatorId': currentUser.uid,
        'directMessageRequestRecipientId': otherUser.uid,
        'directMessageRequestLimit': onlyRequestForUntrustedContacts
            ? _preferences.getDirectMessageRequestLimit()
            : 0,
        'directMessageRequestSentCount': 0,
        'scope': 'personal',
        'companyId': '',
        'companyName': '',
      },
    );

    await channel.watch();
  }

  Future<void> _ensureStreamChannelForSpace({
    required String chatId,
    required String type,
    required String title,
    required String description,
    required AppUser currentUser,
    required List<AppUser> selectedUsers,
  }) async {
    final client = await _streamChatService.requireConnectedClient();

    final members = <AppUser>[currentUser, ...selectedUsers];
    final memberIds = members.map((user) => user.uid).toList();

    final channel = client.channel(
      'messaging',
      id: chatId,
      extraData: {
        'members': memberIds,
        'name': title.trim(),
        'title': title.trim(),
        'description': description.trim(),
        'memberNames': {
          for (final user in members) user.uid: user.name,
        },
        'memberUsernames': {
          for (final user in members) user.uid: user.username,
        },
        'memberPhotos': {
          for (final user in members) user.uid: user.photoUrl,
        },
        'messeya_chat_type': type,
        'adminIds': [currentUser.uid],
        'moderatorIds': const <String>[],
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
        'scope': 'personal',
        'companyId': '',
        'companyName': '',
      },
    );

    await channel.watch();
  }
}
