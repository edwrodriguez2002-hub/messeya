import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  const Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.createdAt,
    required this.type,
    required this.seenBy,
    required this.deliveredTo,
    required this.deletedFor,
    required this.deletedForAll,
    required this.attachmentUrl,
    required this.fileName,
    this.attachments = const [],
    required this.reactions,
    required this.replyToMessageId,
    required this.replyToText,
    required this.replyToSenderName,
    required this.replyToType,
    required this.voiceDurationMs,
    required this.pollQuestion,
    required this.pollOptions,
    required this.editedAt,
    required this.forwardedFromMessageId,
    required this.forwardedFromChatId,
    required this.forwardedFromSenderName,
    required this.starredBy,
    required this.viewOnce,
    required this.mediaOpenedBy,
    this.subject = '',
    this.priority = 'normal',
    this.seenAt = const {},
    this.deliveredAt = const {},
    this.isEncrypted = false, // Nuevo campo
  });

  final String id;
  final String chatId;
  final String senderId;
  final String text;
  final DateTime? createdAt;
  final String type;
  final List<String> seenBy;
  final List<String> deliveredTo;
  final List<String> deletedFor;
  final bool deletedForAll;
  final String attachmentUrl;
  final String fileName;
  final List<MessageAttachment> attachments;
  final Map<String, List<String>> reactions;
  final String replyToMessageId;
  final String replyToText;
  final String replyToSenderName;
  final String replyToType;
  final int voiceDurationMs;
  final String pollQuestion;
  final List<MessagePollOption> pollOptions;
  final DateTime? editedAt;
  final String forwardedFromMessageId;
  final String forwardedFromChatId;
  final String forwardedFromSenderName;
  final List<String> starredBy;
  final bool viewOnce;
  final List<String> mediaOpenedBy;
  final String subject;
  final String priority;
  final Map<String, DateTime> seenAt;
  final Map<String, DateTime> deliveredAt;
  final bool isEncrypted;

  factory Message.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? <String, dynamic>{};
    return Message(
      id: doc.id,
      chatId: map['chatId'] as String? ?? '',
      senderId: map['senderId'] as String? ?? '',
      text: map['text'] as String? ?? '',
      createdAt: _fromTimestamp(map['createdAt']),
      type: map['type'] as String? ?? 'text',
      seenBy: List<String>.from(map['seenBy'] as List? ?? const []),
      deliveredTo: List<String>.from(map['deliveredTo'] as List? ?? const []),
      deletedFor: List<String>.from(map['deletedFor'] as List? ?? const []),
      deletedForAll: map['deletedForAll'] as bool? ?? false,
      attachmentUrl: map['attachmentUrl'] as String? ?? '',
      fileName: map['fileName'] as String? ?? '',
      attachments: ((map['attachments'] as List?) ?? const [])
          .map((item) => MessageAttachment.fromMap(Map<String, dynamic>.from(item)))
          .toList(),
      reactions: _mapReactions(map['reactions']),
      replyToMessageId: map['replyToMessageId'] as String? ?? '',
      replyToText: map['replyToText'] as String? ?? '',
      replyToSenderName: map['replyToSenderName'] as String? ?? '',
      replyToType: map['replyToType'] as String? ?? '',
      voiceDurationMs: map['voiceDurationMs'] as int? ?? 0,
      pollQuestion: map['pollQuestion'] as String? ?? '',
      pollOptions: ((map['pollOptions'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => MessagePollOption.fromMap(Map<String, dynamic>.from(item)))
          .toList(),
      editedAt: _fromTimestamp(map['editedAt']),
      forwardedFromMessageId: map['forwardedFromMessageId'] as String? ?? '',
      forwardedFromChatId: map['forwardedFromChatId'] as String? ?? '',
      forwardedFromSenderName: map['forwardedFromSenderName'] as String? ?? '',
      starredBy: List<String>.from(map['starredBy'] as List? ?? const []),
      viewOnce: map['viewOnce'] as bool? ?? false,
      mediaOpenedBy: List<String>.from(map['mediaOpenedBy'] as List? ?? const []),
      subject: map['subject'] as String? ?? '',
      priority: map['priority'] as String? ?? 'normal',
      seenAt: _mapTimestamps(map['seenAt']),
      deliveredAt: _mapTimestamps(map['deliveredAt']),
      isEncrypted: map['isEncrypted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'chatId': chatId,
      'senderId': senderId,
      'text': text,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'type': type,
      'seenBy': seenBy,
      'deliveredTo': deliveredTo,
      'deletedFor': deletedFor,
      'deletedForAll': deletedForAll,
      'attachmentUrl': attachmentUrl,
      'fileName': fileName,
      'attachments': attachments.map((a) => a.toMap()).toList(),
      'reactions': reactions,
      'replyToMessageId': replyToMessageId,
      'replyToText': replyToText,
      'replyToSenderName': replyToSenderName,
      'replyToType': replyToType,
      'voiceDurationMs': voiceDurationMs,
      'pollQuestion': pollQuestion,
      'pollOptions': pollOptions.map((item) => item.toMap()).toList(),
      'editedAt': editedAt == null ? null : Timestamp.fromDate(editedAt!),
      'forwardedFromMessageId': forwardedFromMessageId,
      'forwardedFromChatId': forwardedFromChatId,
      'forwardedFromSenderName': forwardedFromSenderName,
      'starredBy': starredBy,
      'viewOnce': viewOnce,
      'mediaOpenedBy': mediaOpenedBy,
      'subject': subject,
      'priority': priority,
      'seenAt': seenAt.map((k, v) => MapEntry(k, Timestamp.fromDate(v))),
      'deliveredAt': deliveredAt.map((k, v) => MapEntry(k, Timestamp.fromDate(v))),
      'isEncrypted': isEncrypted,
    };
  }

  static DateTime? _fromTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }

  static Map<String, DateTime> _mapTimestamps(dynamic value) {
    if (value is! Map) return const {};
    return value.map((key, val) => MapEntry('$key', val is Timestamp ? val.toDate() : DateTime.now()));
  }

  static Map<String, List<String>> _mapReactions(dynamic value) {
    if (value is! Map) return const {};
    return value.map((key, reactionValue) => MapEntry('$key', List<String>.from(reactionValue as List? ?? const [])));
  }
}

class MessageAttachment {
  final String url;
  final String name;
  final String type;

  MessageAttachment({required this.url, required this.name, required this.type});

  factory MessageAttachment.fromMap(Map<String, dynamic> map) {
    return MessageAttachment(
      url: map['url'] ?? '',
      name: map['name'] ?? '',
      type: map['type'] ?? 'file',
    );
  }

  Map<String, dynamic> toMap() => {'url': url, 'name': name, 'type': type};
}

class MessagePollOption {
  const MessagePollOption({required this.id, required this.label, required this.voterIds});
  final String id;
  final String label;
  final List<String> voterIds;
  factory MessagePollOption.fromMap(Map<String, dynamic> map) => MessagePollOption(id: map['id'] ?? '', label: map['label'] ?? '', voterIds: List<String>.from(map['voterIds'] ?? []));
  Map<String, dynamic> toMap() => {'id': id, 'label': label, 'voterIds': voterIds};
}
