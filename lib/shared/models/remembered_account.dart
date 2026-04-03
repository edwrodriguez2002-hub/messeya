class RememberedAccount {
  const RememberedAccount({
    required this.uid,
    required this.username,
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.firebaseAppName,
    required this.lastUsedAtMs,
  });

  final String uid;
  final String username;
  final String name;
  final String email;
  final String photoUrl;
  final String firebaseAppName;
  final int lastUsedAtMs;

  factory RememberedAccount.fromMap(Map<String, dynamic> map) {
    return RememberedAccount(
      uid: map['uid'] as String? ?? '',
      username: map['username'] as String? ?? '',
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      photoUrl: map['photoUrl'] as String? ?? '',
      firebaseAppName: map['firebaseAppName'] as String? ?? '__default__',
      lastUsedAtMs: map['lastUsedAtMs'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'username': username,
      'name': name,
      'email': email,
      'photoUrl': photoUrl,
      'firebaseAppName': firebaseAppName,
      'lastUsedAtMs': lastUsedAtMs,
    };
  }

  RememberedAccount copyWith({
    String? uid,
    String? username,
    String? name,
    String? email,
    String? photoUrl,
    String? firebaseAppName,
    int? lastUsedAtMs,
  }) {
    return RememberedAccount(
      uid: uid ?? this.uid,
      username: username ?? this.username,
      name: name ?? this.name,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      firebaseAppName: firebaseAppName ?? this.firebaseAppName,
      lastUsedAtMs: lastUsedAtMs ?? this.lastUsedAtMs,
    );
  }
}
