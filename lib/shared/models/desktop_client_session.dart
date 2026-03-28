import 'package:cloud_firestore/cloud_firestore.dart';

class DesktopClientSession {
  const DesktopClientSession({
    required this.id,
    required this.ownerUid,
    required this.ownerName,
    required this.ownerUsername,
    required this.linkedDeviceId,
    required this.status,
    required this.lastActiveAt,
  });

  final String id;
  final String ownerUid;
  final String ownerName;
  final String ownerUsername;
  final String linkedDeviceId;
  final String status;
  final DateTime? lastActiveAt;

  bool get isActive => status == 'active' && ownerUid.isNotEmpty;

  factory DesktopClientSession.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final map = doc.data() ?? const <String, dynamic>{};
    return DesktopClientSession(
      id: doc.id,
      ownerUid: map['ownerUid'] as String? ?? '',
      ownerName: map['ownerName'] as String? ?? '',
      ownerUsername: map['ownerUsername'] as String? ?? '',
      linkedDeviceId: map['linkedDeviceId'] as String? ?? '',
      status: map['status'] as String? ?? 'pending',
      lastActiveAt: _fromTimestamp(map['lastActiveAt']),
    );
  }

  static DateTime? _fromTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }
}
