import 'package:cloud_firestore/cloud_firestore.dart';

class CallLog {
  const CallLog({
    required this.id,
    required this.contactId,
    required this.contactName,
    required this.contactUsername,
    required this.contactPhoto,
    required this.type,
    required this.direction,
    required this.status,
    required this.startedAt,
  });

  final String id;
  final String contactId;
  final String contactName;
  final String contactUsername;
  final String contactPhoto;
  final String type;
  final String direction;
  final String status;
  final DateTime? startedAt;

  factory CallLog.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? <String, dynamic>{};
    return CallLog(
      id: doc.id,
      contactId: map['contactId'] as String? ?? '',
      contactName: map['contactName'] as String? ?? '',
      contactUsername: map['contactUsername'] as String? ?? '',
      contactPhoto: map['contactPhoto'] as String? ?? '',
      type: map['type'] as String? ?? 'audio',
      direction: map['direction'] as String? ?? 'outgoing',
      status: map['status'] as String? ?? 'completed',
      startedAt: _fromTimestamp(map['startedAt']),
    );
  }

  static DateTime? _fromTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }
}
