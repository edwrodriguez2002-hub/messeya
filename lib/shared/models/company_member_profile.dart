import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_user.dart';

class CompanyMemberProfile {
  const CompanyMemberProfile({
    required this.companyId,
    required this.userId,
    required this.displayName,
    required this.roleTitle,
    required this.department,
    required this.workEmail,
    required this.workPhone,
    required this.notes,
    required this.isVisible,
    required this.updatedAt,
  });

  final String companyId;
  final String userId;
  final String displayName;
  final String roleTitle;
  final String department;
  final String workEmail;
  final String workPhone;
  final String notes;
  final bool isVisible;
  final DateTime? updatedAt;

  factory CompanyMemberProfile.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String companyId,
  }) {
    final map = doc.data() ?? <String, dynamic>{};
    return CompanyMemberProfile(
      companyId: companyId,
      userId: doc.id,
      displayName: map['displayName'] as String? ?? '',
      roleTitle: map['roleTitle'] as String? ?? '',
      department: map['department'] as String? ?? '',
      workEmail: map['workEmail'] as String? ?? '',
      workPhone: map['workPhone'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      isVisible: map['isVisible'] as bool? ?? true,
      updatedAt: _fromTimestamp(map['updatedAt']),
    );
  }

  factory CompanyMemberProfile.empty({
    required String companyId,
    required String userId,
  }) {
    return CompanyMemberProfile(
      companyId: companyId,
      userId: userId,
      displayName: '',
      roleTitle: '',
      department: '',
      workEmail: '',
      workPhone: '',
      notes: '',
      isVisible: true,
      updatedAt: null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'roleTitle': roleTitle,
      'department': department,
      'workEmail': workEmail,
      'workPhone': workPhone,
      'notes': notes,
      'isVisible': isVisible,
      'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
    };
  }

  static DateTime? _fromTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }
}

class CompanyMemberContact {
  const CompanyMemberContact({
    required this.user,
    required this.profile,
  });

  final AppUser user;
  final CompanyMemberProfile profile;

  String get displayName => profile.displayName.trim().isNotEmpty
      ? profile.displayName.trim()
      : user.name;

  String get subtitle {
    final pieces = <String>[
      if (profile.roleTitle.trim().isNotEmpty) profile.roleTitle.trim(),
      if (profile.department.trim().isNotEmpty) profile.department.trim(),
      '@${user.username}',
    ];
    return pieces.join(' · ');
  }
}
