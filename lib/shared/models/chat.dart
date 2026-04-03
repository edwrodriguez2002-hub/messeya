import 'package:cloud_firestore/cloud_firestore.dart';

class Chat {
  const Chat({
    required this.id,
    required this.members,
    required this.memberNames,
    required this.memberUsernames,
    required this.memberPhotos,
    required this.createdAt,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.lastMessageSenderId,
    required this.type,
    required this.title,
    required this.description,
    required this.adminIds,
    required this.moderatorIds,
    required this.pinnedBy,
    required this.archivedBy,
    required this.typingUsers,
    required this.recordingUsers,
    required this.ownerId,
    required this.photoUrl,
    required this.coverUrl,
    required this.inviteCode,
    required this.pinnedMessageId,
    required this.onlyAdminsCanPost,
    required this.directMessageRequestStatus,
    required this.directMessageRequestInitiatorId,
    required this.directMessageRequestRecipientId,
    required this.directMessageRequestLimit,
    required this.directMessageRequestSentCount,
    required this.unreadCounts,
    this.scope = 'personal',
    this.companyId = '',
    this.companyName = '',
    this.companyVisibility = '',
    this.companyChannelKind = '',
    this.isDefaultCompanyChannel = false,
  });

  final String id;
  final List<String> members;
  final Map<String, String> memberNames;
  final Map<String, String> memberUsernames;
  final Map<String, String> memberPhotos;
  final DateTime? createdAt;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final String lastMessageSenderId;
  final String type;
  final String title;
  final String description;
  final List<String> adminIds;
  final List<String> moderatorIds;
  final List<String> pinnedBy;
  final List<String> archivedBy;
  final List<String> typingUsers;
  final List<String> recordingUsers;
  final String ownerId;
  final String photoUrl;
  final String coverUrl;
  final String inviteCode;
  final String pinnedMessageId;
  final bool onlyAdminsCanPost;
  final String directMessageRequestStatus;
  final String directMessageRequestInitiatorId;
  final String directMessageRequestRecipientId;
  final int directMessageRequestLimit;
  final int directMessageRequestSentCount;
  final Map<String, int> unreadCounts;
  final String scope;
  final String companyId;
  final String companyName;
  final String companyVisibility;
  final String companyChannelKind;
  final bool isDefaultCompanyChannel;

  factory Chat.fromMap(String id, Map<String, dynamic> map) {
    return Chat(
      id: id,
      members: List<String>.from(map['members'] as List? ?? const []),
      memberNames: Map<String, String>.from(
        map['memberNames'] as Map? ?? const <String, String>{},
      ),
      memberUsernames: Map<String, String>.from(
        map['memberUsernames'] as Map? ?? const <String, String>{},
      ),
      memberPhotos: Map<String, String>.from(
        map['memberPhotos'] as Map? ?? const <String, String>{},
      ),
      createdAt: _fromTimestamp(map['createdAt']),
      lastMessage: map['lastMessage'] as String? ?? '',
      lastMessageAt: _fromTimestamp(map['lastMessageAt']),
      lastMessageSenderId: map['lastMessageSenderId'] as String? ?? '',
      type: map['type'] as String? ?? 'direct',
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      adminIds: List<String>.from(map['adminIds'] as List? ?? const []),
      moderatorIds: List<String>.from(
        map['moderatorIds'] as List? ?? const [],
      ),
      pinnedBy: List<String>.from(map['pinnedBy'] as List? ?? const []),
      archivedBy: List<String>.from(map['archivedBy'] as List? ?? const []),
      typingUsers: List<String>.from(map['typingUsers'] as List? ?? const []),
      recordingUsers:
          List<String>.from(map['recordingUsers'] as List? ?? const []),
      ownerId: map['ownerId'] as String? ?? '',
      photoUrl: map['photoUrl'] as String? ?? '',
      coverUrl: map['coverUrl'] as String? ?? '',
      inviteCode: map['inviteCode'] as String? ?? '',
      pinnedMessageId: map['pinnedMessageId'] as String? ?? '',
      onlyAdminsCanPost: map['onlyAdminsCanPost'] as bool? ?? false,
      directMessageRequestStatus:
          map['directMessageRequestStatus'] as String? ?? 'accepted',
      directMessageRequestInitiatorId:
          map['directMessageRequestInitiatorId'] as String? ?? '',
      directMessageRequestRecipientId:
          map['directMessageRequestRecipientId'] as String? ?? '',
      directMessageRequestLimit: map['directMessageRequestLimit'] as int? ?? 3,
      directMessageRequestSentCount:
          map['directMessageRequestSentCount'] as int? ?? 0,
      unreadCounts: Map<String, int>.from(
        (map['unreadCounts'] as Map? ?? const <String, int>{}).map(
          (key, value) =>
              MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
        ),
      ),
      scope: map['scope'] as String? ?? 'personal',
      companyId: map['companyId'] as String? ?? '',
      companyName: map['companyName'] as String? ?? '',
      companyVisibility: map['companyVisibility'] as String? ?? '',
      companyChannelKind: map['companyChannelKind'] as String? ?? '',
      isDefaultCompanyChannel: map['isDefaultCompanyChannel'] as bool? ?? false,
    );
  }

  factory Chat.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? <String, dynamic>{};
    return Chat.fromMap(doc.id, map);
  }

  Map<String, dynamic> toMap() {
    return {
      'members': members,
      'memberNames': memberNames,
      'memberUsernames': memberUsernames,
      'memberPhotos': memberPhotos,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'lastMessage': lastMessage,
      'lastMessageAt':
          lastMessageAt == null ? null : Timestamp.fromDate(lastMessageAt!),
      'lastMessageSenderId': lastMessageSenderId,
      'type': type,
      'title': title,
      'description': description,
      'adminIds': adminIds,
      'moderatorIds': moderatorIds,
      'pinnedBy': pinnedBy,
      'archivedBy': archivedBy,
      'typingUsers': typingUsers,
      'recordingUsers': recordingUsers,
      'ownerId': ownerId,
      'photoUrl': photoUrl,
      'coverUrl': coverUrl,
      'inviteCode': inviteCode,
      'pinnedMessageId': pinnedMessageId,
      'onlyAdminsCanPost': onlyAdminsCanPost,
      'directMessageRequestStatus': directMessageRequestStatus,
      'directMessageRequestInitiatorId': directMessageRequestInitiatorId,
      'directMessageRequestRecipientId': directMessageRequestRecipientId,
      'directMessageRequestLimit': directMessageRequestLimit,
      'directMessageRequestSentCount': directMessageRequestSentCount,
      'unreadCounts': unreadCounts,
      'scope': scope,
      'companyId': companyId,
      'companyName': companyName,
      'companyVisibility': companyVisibility,
      'companyChannelKind': companyChannelKind,
      'isDefaultCompanyChannel': isDefaultCompanyChannel,
    };
  }

  String otherMemberId(String currentUserId) {
    return members.firstWhere((id) => id != currentUserId, orElse: () => '');
  }

  static DateTime? _fromTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }
}
