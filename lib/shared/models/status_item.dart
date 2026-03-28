import 'package:cloud_firestore/cloud_firestore.dart';

class StatusItem {
  const StatusItem({
    required this.id,
    required this.userId,
    required this.username,
    required this.userName,
    required this.userPhoto,
    required this.text,
    required this.mediaUrl,
    required this.mediaType,
    required this.createdAt,
    required this.expiresAt,
    required this.viewedBy,
    required this.hiddenFor,
    required this.visibleTo,
  });

  final String id;
  final String userId;
  final String username;
  final String userName;
  final String userPhoto;
  final String text;
  final String mediaUrl;
  final String mediaType;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final List<String> viewedBy;
  final List<String> hiddenFor;
  final List<String> visibleTo;

  factory StatusItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? <String, dynamic>{};
    return StatusItem(
      id: doc.id,
      userId: map['userId'] as String? ?? '',
      username: map['username'] as String? ?? '',
      userName: map['userName'] as String? ?? '',
      userPhoto: map['userPhoto'] as String? ?? '',
      text: map['text'] as String? ?? '',
      mediaUrl: map['mediaUrl'] as String? ?? '',
      mediaType: map['mediaType'] as String? ?? 'text',
      createdAt: _fromTimestamp(map['createdAt']),
      expiresAt: _fromTimestamp(map['expiresAt']),
      viewedBy: List<String>.from(map['viewedBy'] as List? ?? const []),
      hiddenFor: List<String>.from(map['hiddenFor'] as List? ?? const []),
      visibleTo: List<String>.from(map['visibleTo'] as List? ?? const []),
    );
  }

  static DateTime? _fromTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }
}
