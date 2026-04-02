import 'package:cloud_firestore/cloud_firestore.dart';

class Company {
  const Company({
    required this.id,
    required this.name,
    required this.description,
    required this.ownerId,
    required this.adminIds,
    required this.memberIds,
    required this.planStatus,
    required this.planName,
    required this.planSource,
    required this.logoUrl,
    required this.subscriptionProductId,
    required this.subscriptionBasePlanId,
    required this.subscriptionOfferId,
    required this.subscriptionRenewsAt,
    required this.billingLastVerifiedAt,
    required this.billingStatusMessage,
    required this.createdAt,
    this.isVerified = false, // Nuevo campo
  });

  final String id;
  final String name;
  final String description;
  final String ownerId;
  final List<String> adminIds;
  final List<String> memberIds;
  final String planStatus;
  final String planName;
  final String planSource;
  final String logoUrl;
  final String subscriptionProductId;
  final String subscriptionBasePlanId;
  final String subscriptionOfferId;
  final DateTime? subscriptionRenewsAt;
  final DateTime? billingLastVerifiedAt;
  final String billingStatusMessage;
  final DateTime? createdAt;
  final bool isVerified;

  bool get isActive =>
      planStatus == 'active' || planStatus == 'trial' || planStatus == 'grace';

  bool get needsPaidPlanActivation =>
      planStatus == 'inactive' ||
      planStatus == 'expired' ||
      planStatus == 'canceled';

  factory Company.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? <String, dynamic>{};
    
    // Manejo robusto para isVerified (acepta boolean o string)
    final verifiedRaw = map['isVerified'];
    bool verified = false;
    if (verifiedRaw is bool) {
      verified = verifiedRaw;
    } else if (verifiedRaw is String) {
      verified = verifiedRaw.toLowerCase() == 'true';
    }

    return Company(
      id: doc.id,
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      ownerId: map['ownerId'] as String? ?? '',
      adminIds: List<String>.from(map['adminIds'] as List? ?? const []),
      memberIds: List<String>.from(map['memberIds'] as List? ?? const []),
      planStatus: map['planStatus'] as String? ?? 'inactive',
      planName: map['planName'] as String? ?? 'basic',
      planSource: map['planSource'] as String? ?? '',
      logoUrl: map['logoUrl'] as String? ?? '',
      subscriptionProductId: map['subscriptionProductId'] as String? ?? '',
      subscriptionBasePlanId: map['subscriptionBasePlanId'] as String? ?? '',
      subscriptionOfferId: map['subscriptionOfferId'] as String? ?? '',
      subscriptionRenewsAt: _fromTimestamp(map['subscriptionRenewsAt']),
      billingLastVerifiedAt: _fromTimestamp(map['billingLastVerifiedAt']),
      billingStatusMessage: map['billingStatusMessage'] as String? ?? '',
      createdAt: _fromTimestamp(map['createdAt']),
      isVerified: verified,
    );
  }

  static DateTime? _fromTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }
}
