import 'package:cloud_firestore/cloud_firestore.dart';

class CallInvite {
  const CallInvite({
    required this.id,
    required this.callId,
    required this.callerUid,
    required this.callerName,
    required this.callerUsername,
    required this.callerPhoto,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.callerLogId,
    required this.receiverLogId,
  });

  final String id;
  final String callId;
  final String callerUid;
  final String callerName;
  final String callerUsername;
  final String callerPhoto;
  final String type;
  final String status;
  final DateTime? createdAt;
  final String callerLogId;
  final String receiverLogId;

  factory CallInvite.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? const <String, dynamic>{};
    return CallInvite(
      id: doc.id,
      callId: map['callId'] as String? ?? '',
      callerUid: map['callerUid'] as String? ?? '',
      callerName: map['callerName'] as String? ?? '',
      callerUsername: map['callerUsername'] as String? ?? '',
      callerPhoto: map['callerPhoto'] as String? ?? '',
      type: map['type'] as String? ?? 'audio',
      status: map['status'] as String? ?? 'ringing',
      createdAt: map['createdAt'] is Timestamp
          ? (map['createdAt'] as Timestamp).toDate()
          : null,
      callerLogId: map['callerLogId'] as String? ?? '',
      receiverLogId: map['receiverLogId'] as String? ?? '',
    );
  }
}
