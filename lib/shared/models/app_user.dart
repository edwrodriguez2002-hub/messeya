import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  const AppUser({
    required this.uid,
    required this.username,
    required this.usernameLower,
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.bio,
    required this.createdAt,
    required this.isOnline,
    required this.lastSeen,
  });

  final String uid;
  final String username;
  final String usernameLower;
  final String name;
  final String email;
  final String photoUrl;
  final String bio;
  final DateTime? createdAt;
  final bool isOnline;
  final DateTime? lastSeen;

  factory AppUser.fromMap(Map<String, dynamic> map, {String? id}) {
    return AppUser(
      // CORRECCIÓN: Priorizamos el ID pasado (el del documento) sobre el campo interno
      uid: id ?? map['uid'] as String? ?? '',
      username: map['username'] as String? ?? '',
      usernameLower: map['usernameLower'] as String? ?? '',
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      photoUrl: map['photoUrl'] as String? ?? '',
      bio: map['bio'] as String? ?? '',
      createdAt: _fromTimestamp(map['createdAt']),
      isOnline: map['isOnline'] as bool? ?? false,
      lastSeen: _fromTimestamp(map['lastSeen']),
    );
  }

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    // CORRECCIÓN: Pasamos doc.id para asegurar que el UID nunca sea una cadena vacía
    return AppUser.fromMap(doc.data() ?? <String, dynamic>{}, id: doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'username': username,
      'usernameLower': usernameLower,
      'name': name,
      'email': email,
      'photoUrl': photoUrl,
      'bio': bio,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'isOnline': isOnline,
      'lastSeen': lastSeen == null ? null : Timestamp.fromDate(lastSeen!),
    };
  }

  AppUser copyWith({
    String? uid,
    String? username,
    String? usernameLower,
    String? name,
    String? email,
    String? photoUrl,
    String? bio,
    DateTime? createdAt,
    bool? isOnline,
    DateTime? lastSeen,
  }) {
    return AppUser(
      uid: uid ?? this.uid,
      username: username ?? this.username,
      usernameLower: usernameLower ?? this.usernameLower,
      name: name ?? this.name,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      bio: bio ?? this.bio,
      createdAt: createdAt ?? this.createdAt,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  static DateTime? _fromTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }
}
