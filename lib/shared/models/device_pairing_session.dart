import 'package:cloud_firestore/cloud_firestore.dart';

class DevicePairingSession {
  const DevicePairingSession({
    required this.id,
    required this.creatorUid,
    required this.platform,
    required this.deviceLabel,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.ownerUid,
    required this.ownerName,
    required this.ownerUsername,
    required this.linkedDeviceId,
    required this.linkedAt,
  });

  final String id;
  final String creatorUid;
  final String platform;
  final String deviceLabel;
  final String status;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final String ownerUid;
  final String ownerName;
  final String ownerUsername;
  final String linkedDeviceId;
  final DateTime? linkedAt;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get isPending => status == 'pending' && !isExpired;
  bool get isLinked => status == 'linked' && linkedDeviceId.isNotEmpty;

  factory DevicePairingSession.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final map = doc.data() ?? const <String, dynamic>{};
    return DevicePairingSession(
      id: doc.id,
      creatorUid: map['creatorUid'] as String? ?? '',
      platform: map['platform'] as String? ?? 'windows',
      deviceLabel: map['deviceLabel'] as String? ?? 'Windows',
      status: map['status'] as String? ?? 'pending',
      createdAt: _fromTimestamp(map['createdAt']),
      expiresAt: _fromTimestamp(map['expiresAt']),
      ownerUid: map['ownerUid'] as String? ?? '',
      ownerName: map['ownerName'] as String? ?? '',
      ownerUsername: map['ownerUsername'] as String? ?? '',
      linkedDeviceId: map['linkedDeviceId'] as String? ?? '',
      linkedAt: _fromTimestamp(map['linkedAt']),
    );
  }

  static DateTime? _fromTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }
}
