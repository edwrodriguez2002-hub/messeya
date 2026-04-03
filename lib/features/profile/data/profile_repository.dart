import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/services/app_preferences_service.dart';
import '../../../core/services/cloudinary_media_service.dart';
import '../../../core/services/encryption_service.dart';
import '../../../shared/models/app_user.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(
    ref.watch(firestoreProvider),
    ref.watch(cloudinaryMediaServiceProvider),
    ref.watch(firebaseAuthProvider),
    ref.watch(encryptionServiceProvider),
    ref.watch(appPreferencesServiceProvider),
  );
});

final currentAppUserProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(profileRepositoryProvider).watchCurrentUser();
});

final userProfileProvider =
    StreamProvider.family<AppUser?, String>((ref, userId) {
  return ref.watch(profileRepositoryProvider).watchUser(userId);
});

final allUsersProvider = FutureProvider.family<List<AppUser>, String>((ref, query) {
  return ref.watch(profileRepositoryProvider).searchUsers(query: query);
});

class ProfileRepository {
  ProfileRepository(
    this._firestore,
    this._cloudinary,
    this._auth,
    this._encryption,
    this._preferences,
  );

  final FirebaseFirestore _firestore;
  final CloudinaryMediaService _cloudinary;
  final FirebaseAuth _auth;
  final EncryptionService _encryption;
  final AppPreferencesService _preferences;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');
  CollectionReference<Map<String, dynamic>> get _usernames =>
      _firestore.collection('usernames');
  CollectionReference<Map<String, dynamic>> _presenceDevices(
    FirebaseFirestore firestore,
    String uid,
  ) =>
      firestore.collection('users').doc(uid).collection('presence_devices');

  String get _uid => _auth.currentUser!.uid;
  String get currentUid => _auth.currentUser?.uid ?? '';

  static bool hasVerificationAccess(AppUser? user) {
    if (user == null) return false;
    return user.canVerifyUsers;
  }

  static bool hasCompanyTesterAccess(AppUser? user) {
    if (user == null) return false;
    return user.isCompanyTester;
  }

  Stream<AppUser?> watchCurrentUser() {
    if (_auth.currentUser == null) return const Stream.empty();
    return _watchUserWithPresence(_firestore, _uid);
  }

  Stream<AppUser?> watchUser(String userId) {
    if (userId.isEmpty) return Stream.value(null);
    return _watchUserWithPresence(_firestore, userId);
  }

  Future<void> createUserProfile(AppUser user) async {
    // Generar claves E2EE al crear el perfil
    final publicKey = await _encryption.generateAndStoreKeyPair(user.uid);
    // IMPORTANTE: isVerified siempre es false por defecto al crear
    final userWithKey = user.copyWith(
      publicKey: publicKey,
      isVerified: false,
    );

    await _reserveUsernameAndSaveProfile(
      uid: userWithKey.uid,
      username: userWithKey.username,
      data: userWithKey.toMap(),
    );
  }

  Future<void> ensureUserProfile({
    required String uid,
    required String email,
    required String name,
    String? desiredUsername,
    String photoUrl = '',
    String bio = 'Disponible',
  }) async {
    await ensureUserProfileForSession(
      firestore: _firestore,
      auth: _auth,
      uid: uid,
      email: email,
      name: name,
      desiredUsername: desiredUsername,
      photoUrl: photoUrl,
      bio: bio,
    );
  }

  Future<void> ensureUserProfileForSession({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    required String uid,
    required String email,
    required String name,
    String? desiredUsername,
    String photoUrl = '',
    String bio = 'Disponible',
  }) async {
    final users = firestore.collection('users');
    final usernames = firestore.collection('usernames');
    final doc = await users.doc(uid).get();
    
    if (doc.exists) {
      final data = doc.data()!;
      final currentUsername = data['username'] as String? ?? '';
      final currentPublicKey = data['publicKey'] as String? ?? '';
      
      // VERIFICACIÓN DE LLAVES E2EE (Solución a reinstalaciones)
      final hasLocalKey = await _encryption.hasPrivateKey(uid);
      
      Map<String, dynamic> updates = {
        'email': email,
        'name': name,
        'photoUrl': photoUrl.isNotEmpty ? photoUrl : (data['photoUrl'] ?? ''),
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
      };

      // Si el usuario no tiene llave pública en Firestore O si reinstaló la app (no tiene llave privada local),
      // generamos un par nuevo y actualizamos Firestore.
      if (currentPublicKey.isEmpty || !hasLocalKey) {
        updates['publicKey'] = await _encryption.generateAndStoreKeyPair(uid);
      }
      
      if (currentUsername.isEmpty) {
        final newUsername = await _generateUniqueUsername(
          desiredUsername ?? email.split('@').first,
        );
        updates['username'] = newUsername;
        updates['usernameLower'] = newUsername.toLowerCase();
        
        await _reserveUsernameAndSaveProfileForSession(
          firestore: firestore,
          usernames: usernames,
          users: users,
          uid: uid,
          username: newUsername,
          data: updates,
          merge: true,
        );
      } else {
        await users.doc(uid).set(updates, SetOptions(merge: true));
      }
      return;
    }

    // Lógica para usuario nuevo
    final username = await _generateUniqueUsername(
      desiredUsername ?? email.split('@').first,
    );
    
    final publicKey = await _encryption.generateAndStoreKeyPair(uid);

    final user = AppUser(
      uid: uid,
      username: username,
      usernameLower: username.toLowerCase(),
      name: name,
      email: email,
      photoUrl: photoUrl,
      bio: bio,
      createdAt: DateTime.now(),
      isOnline: true,
      lastSeen: DateTime.now(),
      publicKey: publicKey,
      isVerified: false, // Por defecto siempre false
      canCreateCompanies: false,
      canVerifyUsers: false,
      isCompanyTester: false,
    );
    await createUserProfileForSession(
      firestore: firestore,
      usernames: usernames,
      user: user,
    );
  }

  Future<void> updateProfile({
    required String name,
    required String bio,
    File? imageFile,
  }) async {
    String photoUrl = '';
    String currentUsername = '';
    bool isVerified = false;
    bool canCreateCompanies = false;
    bool canVerifyUsers = false;
    bool isCompanyTester = false;
    String currentPublicKey = '';
    final snapshot = await _users.doc(_uid).get();
    if (snapshot.exists) {
      final data = snapshot.data()!;
      photoUrl = data['photoUrl'] as String? ?? '';
      currentUsername = (data['username'] as String? ?? '').toLowerCase();
      isVerified = data['isVerified'] as bool? ?? false;
      canCreateCompanies = data['canCreateCompanies'] as bool? ?? false;
      canVerifyUsers = data['canVerifyUsers'] as bool? ?? false;
      isCompanyTester = data['isCompanyTester'] as bool? ?? false;
      currentPublicKey = data['publicKey'] as String? ?? '';
    }

    if (imageFile != null) {
      photoUrl = await _cloudinary.uploadImage(
        file: imageFile,
        folder: 'messeya/profile_photos',
        publicId: _uid,
      );
    }

    final hasLocalKey = await _encryption.hasPrivateKey(_uid);
    if (currentPublicKey.isEmpty || !hasLocalKey) {
      currentPublicKey = await _encryption.generateAndStoreKeyPair(_uid);
    }

    await _users.doc(_uid).set(
      {
        'uid': _uid,
        'email': _auth.currentUser?.email ?? '',
        'name': name.trim(),
        'username': currentUsername,
        'usernameLower': currentUsername,
        'bio': bio.trim(),
        'photoUrl': photoUrl,
        'lastSeen': FieldValue.serverTimestamp(),
        'isOnline': true,
        'publicKey': currentPublicKey,
        'isVerified': isVerified,
        'canCreateCompanies': canCreateCompanies,
        'canVerifyUsers': canVerifyUsers,
        'isCompanyTester': isCompanyTester,
      },
      SetOptions(merge: true),
    );
  }

  Future<AppUser?> getCurrentUser() async {
    if (_auth.currentUser == null) return null;
    final snapshot = await _users.doc(_uid).get();
    if (!snapshot.exists) return null;
    return AppUser.fromDoc(snapshot);
  }

  Future<AppUser?> getUserForSession({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  }) async {
    final uid = auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return null;
    final snapshot = await firestore.collection('users').doc(uid).get();
    if (!snapshot.exists) return null;
    return AppUser.fromDoc(snapshot);
  }

  Future<List<AppUser>> searchUsers({String query = ''}) async {
    final trimmed = query.trim().toLowerCase();
    final snapshot = await _users.get();
    final currentUid = _auth.currentUser?.uid;

    final users = snapshot.docs
        .map(AppUser.fromDoc)
        .where(
          (user) =>
              user.uid.isNotEmpty &&
              user.uid != currentUid &&
              (trimmed.isEmpty ||
                  user.name.toLowerCase().contains(trimmed) ||
                  user.email.toLowerCase().contains(trimmed) ||
                  user.usernameLower.contains(trimmed)),
        )
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return users;
  }

  Future<void> setUserVerified({
    required String userId,
    required bool verified,
  }) async {
    final currentUser = await getCurrentUser();
    if (!hasVerificationAccess(currentUser)) {
      throw Exception('Tu cuenta no tiene permiso para verificar usuarios.');
    }

    await _users.doc(userId).set(
      {
        'isVerified': verified,
      },
      SetOptions(merge: true),
    );
  }

  Future<void> updateUserRoles({
    required String userId,
    bool? canVerifyUsers,
    bool? canCreateCompanies,
    bool? isCompanyTester,
  }) async {
    final currentUser = await getCurrentUser();
    if (!hasVerificationAccess(currentUser)) {
      throw Exception('Tu cuenta no tiene permiso para administrar roles.');
    }

    final updates = <String, dynamic>{};
    if (canVerifyUsers != null) {
      updates['canVerifyUsers'] = canVerifyUsers;
    }
    if (canCreateCompanies != null) {
      updates['canCreateCompanies'] = canCreateCompanies;
    }
    if (isCompanyTester != null) {
      updates['isCompanyTester'] = isCompanyTester;
    }
    if (updates.isEmpty) return;

    await _users.doc(userId).set(updates, SetOptions(merge: true));
  }

  Future<void> setOnlineStatus({required bool isOnline}) async {
    if (_auth.currentUser == null) return;

    await setOnlineStatusForSession(
      firestore: _firestore,
      auth: _auth,
      isOnline: isOnline,
    );
  }

  Future<void> setOnlineStatusForSession({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    required bool isOnline,
  }) async {
    final uid = auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    final deviceId = _preferences.getOrCreateLocalDeviceId();
    await _presenceDevices(firestore, uid).doc(deviceId).set(
      {
        'deviceId': deviceId,
        'platform': Platform.operatingSystem,
        'status': isOnline ? 'active' : 'inactive',
        'lastSeen': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    final presenceSnapshot = await _presenceDevices(firestore, uid).get();
    final hasAnotherActive = presenceSnapshot.docs.any((doc) {
      final data = doc.data();
      final status = data['status'] as String? ?? 'inactive';
      if (doc.id == deviceId) {
        return isOnline ? status == 'active' : false;
      }
      return status == 'active';
    });

    await firestore.collection('users').doc(uid).set(
      {
        'isOnline': isOnline || hasAnotherActive,
        'lastSeen': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Stream<AppUser?> _watchUserWithPresence(
    FirebaseFirestore firestore,
    String userId,
  ) async* {
    await for (final doc in firestore.collection('users').doc(userId).snapshots()) {
      if (!doc.exists) {
        yield null;
        continue;
      }

      final user = AppUser.fromDoc(doc);
      final presenceSnapshot = await _presenceDevices(firestore, userId).get();
      final hasActiveDevice = presenceSnapshot.docs.any((deviceDoc) {
        final data = deviceDoc.data();
        return (data['status'] as String? ?? 'inactive') == 'active';
      });

      yield user.copyWith(
        isOnline: hasActiveDevice || user.isOnline,
      );
    }
  }

  String _normalizeUsername(String input) {
    final normalized = input.trim().toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9_]'),
          '',
        );
    if (normalized.length < 2) {
      return 'user_${DateTime.now().millisecondsSinceEpoch.toString().substring(10)}';
    }
    return normalized;
  }

  Future<String> _generateUniqueUsername(String base) async {
    final normalizedBase = _normalizeUsername(base);
    var candidate = normalizedBase;
    var counter = 0;

    while (true) {
      final doc = await _usernames.doc(candidate).get();
      if (!doc.exists) return candidate;
      counter++;
      candidate = '$normalizedBase$counter';
    }
  }

  Future<void> _reserveUsernameAndSaveProfile({
    required String uid,
    required String username,
    required Map<String, dynamic> data,
    String? previousUsername,
    bool merge = false,
  }) async {
    await _reserveUsernameAndSaveProfileForSession(
      firestore: _firestore,
      usernames: _usernames,
      users: _users,
      uid: uid,
      username: username,
      data: data,
      previousUsername: previousUsername,
      merge: merge,
    );
  }

  Future<void> createUserProfileForSession({
    required FirebaseFirestore firestore,
    required CollectionReference<Map<String, dynamic>> usernames,
    required AppUser user,
  }) async {
    final publicKey = await _encryption.generateAndStoreKeyPair(user.uid);
    final userWithKey = user.copyWith(
      publicKey: publicKey,
      isVerified: false,
    );
    await _reserveUsernameAndSaveProfileForSession(
      firestore: firestore,
      usernames: usernames,
      users: firestore.collection('users'),
      uid: userWithKey.uid,
      username: userWithKey.username,
      data: userWithKey.toMap(),
    );
  }

  Future<void> _reserveUsernameAndSaveProfileForSession({
    required FirebaseFirestore firestore,
    required CollectionReference<Map<String, dynamic>> usernames,
    required CollectionReference<Map<String, dynamic>> users,
    required String uid,
    required String username,
    required Map<String, dynamic> data,
    String? previousUsername,
    bool merge = false,
  }) async {
    await firestore.runTransaction((transaction) async {
      final usernameRef = usernames.doc(username);
      final usernameDoc = await transaction.get(usernameRef);

      if (usernameDoc.exists) {
        final ownerUid = usernameDoc.data()?['uid'] as String?;
        if (ownerUid != uid) {
          throw Exception('Ese username ya esta en uso.');
        }
      }

      transaction.set(usernameRef, {
        'uid': uid,
        'username': username,
      });

      if (previousUsername != null &&
          previousUsername.isNotEmpty &&
          previousUsername != username) {
        transaction.delete(usernames.doc(previousUsername));
      }

      transaction.set(
        users.doc(uid),
        data,
        merge ? SetOptions(merge: true) : null,
      );
    });
  }
}
