import 'package:cloud_firestore/cloud_firestore.dart';

class LinkedDevice {
  const LinkedDevice({
    required this.id,
    required this.ownerUid,
    required this.pairingSessionId,
    required this.creatorUid,
    required this.platform,
    required this.deviceLabel,
    required this.status,
    required this.createdAt,
    required this.lastActiveAt,
    required this.revokedAt,
    required this.ownerName,
    required this.ownerUsername,
  });

  final String id;
  final String ownerUid;
  final String pairingSessionId;
  final String creatorUid;
  final String platform;
  final String deviceLabel;
  final String status;
  final DateTime? createdAt;
  final DateTime? lastActiveAt;
  final DateTime? revokedAt;
  final String ownerName;
  final String ownerUsername;

  bool get isActive => status == 'active';

  factory LinkedDevice.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? const <String, dynamic>{};
    return LinkedDevice(
      id: doc.id,
      ownerUid: map['ownerUid'] as String? ?? '',
      pairingSessionId: map['pairingSessionId'] as String? ?? '',
      creatorUid: map['creatorUid'] as String? ?? '',
      platform: map['platform'] as String? ?? 'windows',
      deviceLabel: map['deviceLabel'] as String? ?? 'Dispositivo',
      status: map['status'] as String? ?? 'active',
      createdAt: _fromTimestamp(map['createdAt']),
      lastActiveAt: _fromTimestamp(map['lastActiveAt']),
      revokedAt: _fromTimestamp(map['revokedAt']),
      ownerName: map['ownerName'] as String? ?? '',
      ownerUsername: map['ownerUsername'] as String? ?? '',
    );
  }

  static DateTime? _fromTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }
}
