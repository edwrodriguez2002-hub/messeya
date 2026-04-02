import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/services/cloudinary_media_service.dart';
import '../../../core/services/encryption_service.dart';
import '../../../shared/models/app_user.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(
    ref.watch(firestoreProvider),
    ref.watch(cloudinaryMediaServiceProvider),
    ref.watch(firebaseAuthProvider),
    ref.watch(encryptionServiceProvider),
  );
});

final currentAppUserProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(profileRepositoryProvider).watchCurrentUser();
});

final userProfileProvider =
    StreamProvider.family<AppUser?, String>((ref, userId) {
  return ref.watch(profileRepositoryProvider).watchUser(userId);
});

class ProfileRepository {
  ProfileRepository(this._firestore, this._cloudinary, this._auth, this._encryption);

  final FirebaseFirestore _firestore;
  final CloudinaryMediaService _cloudinary;
  final FirebaseAuth _auth;
  final EncryptionService _encryption;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');
  CollectionReference<Map<String, dynamic>> get _usernames =>
      _firestore.collection('usernames');

  String get _uid => _auth.currentUser!.uid;
  String get currentUid => _auth.currentUser?.uid ?? '';

  Stream<AppUser?> watchCurrentUser() {
    if (_auth.currentUser == null) return const Stream.empty();
    return _users.doc(_uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return AppUser.fromDoc(doc);
    });
  }

  Stream<AppUser?> watchUser(String userId) {
    if (userId.isEmpty) return Stream.value(null);
    return _users.doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return AppUser.fromDoc(doc);
    });
  }

  Future<void> createUserProfile(AppUser user) async {
    // Generar claves E2EE al crear el perfil
    final publicKey = await _encryption.generateAndStoreKeyPair(user.uid);
    // IMPORTANTE: isVerified siempre es false por defecto al crear
    final userWithKey = user.copyWith(publicKey: publicKey, isVerified: false);

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
    final doc = await _users.doc(uid).get();
    
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
        
        await _reserveUsernameAndSaveProfile(
          uid: uid,
          username: newUsername,
          data: updates,
          merge: true,
        );
      } else {
        await _users.doc(uid).set(updates, SetOptions(merge: true));
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
    );
    await createUserProfile(user);
  }

  Future<void> updateProfile({
    required String name,
    required String bio,
    File? imageFile,
  }) async {
    String photoUrl = '';
    String currentUsername = '';
    String currentPublicKey = '';
    final snapshot = await _users.doc(_uid).get();
    if (snapshot.exists) {
      final data = snapshot.data()!;
      photoUrl = data['photoUrl'] as String? ?? '';
      currentUsername = (data['username'] as String? ?? '').toLowerCase();
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

  Future<void> setOnlineStatus({required bool isOnline}) async {
    if (_auth.currentUser == null) return;

    await _users.doc(_uid).set(
      {
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
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
    await _firestore.runTransaction((transaction) async {
      final usernameRef = _usernames.doc(username);
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
        transaction.delete(_usernames.doc(previousUsername));
      }

      transaction.set(
        _users.doc(uid),
        data,
        merge ? SetOptions(merge: true) : null,
      );
    });
  }
}
