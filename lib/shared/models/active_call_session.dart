import 'package:cloud_firestore/cloud_firestore.dart';

class ActiveCallSession {
  const ActiveCallSession({
    required this.id,
    required this.callId,
    required this.contactId,
    required this.contactName,
    required this.contactUsername,
    required this.contactPhoto,
    required this.type,
    required this.status,
    required this.direction,
    required this.screenSharing,
    required this.startedAt,
  });

  final String id;
  final String callId;
  final String contactId;
  final String contactName;
  final String contactUsername;
  final String contactPhoto;
  final String type;
  final String status;
  final String direction;
  final bool screenSharing;
  final DateTime? startedAt;

  factory ActiveCallSession.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? const <String, dynamic>{};
    return ActiveCallSession(
      id: doc.id,
      callId: map['callId'] as String? ?? '',
      contactId: map['contactId'] as String? ?? '',
      contactName: map['contactName'] as String? ?? '',
      contactUsername: map['contactUsername'] as String? ?? '',
      contactPhoto: map['contactPhoto'] as String? ?? '',
      type: map['type'] as String? ?? 'audio',
      status: map['status'] as String? ?? 'ringing',
      direction: map['direction'] as String? ?? 'outgoing',
      screenSharing: map['screenSharing'] as bool? ?? false,
      startedAt: map['startedAt'] is Timestamp
          ? (map['startedAt'] as Timestamp).toDate()
          : null,
    );
  }
}
