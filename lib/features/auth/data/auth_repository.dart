import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/services/app_preferences_service.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../profile/data/profile_repository.dart';

final googleSignInProvider = Provider<GoogleSignIn>(
  (ref) => GoogleSignIn(
    clientId: kIsWeb
        ? '353282297748-us0kv56cnbu9s4tbgtipk5qsq126br50.apps.googleusercontent.com'
        : null,
    serverClientId: kIsWeb
        ? null
        : '353282297748-us0kv56cnbu9s4tbgtipk5qsq126br50.apps.googleusercontent.com',
  ),
);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(firebaseAuthProvider),
    ref.watch(profileRepositoryProvider),
    ref.watch(googleSignInProvider),
    ref.watch(emailOtpSessionProvider.notifier),
  );
});

final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateChangesProvider).valueOrNull;
});

class AuthRepository {
  AuthRepository(
    this._auth,
    this._profileRepository,
    this._googleSignIn,
    this._emailOtpSessionController,
  );

  final FirebaseAuth _auth;
  final ProfileRepository _profileRepository;
  final GoogleSignIn _googleSignIn;
  final EmailOtpSessionController _emailOtpSessionController;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<User> ensureAnonymousSession() async {
    if (_auth.currentUser != null) {
      return _auth.currentUser!;
    }
    try {
      final credential = await _auth.signInAnonymously();
      final user = credential.user;
      if (user == null) {
        throw Exception('No pudimos crear la sesion temporal del dispositivo.');
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapError(e));
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      // OPTIMIZACIÓN: En inicio de sesión tradicional (email/pass), el perfil DEBE existir.
      // No llamamos a ensureUserProfile para evitar escrituras innecesarias en Firestore.
      await _emailOtpSessionController.clear();
      await _profileRepository.setOnlineStatus(isOnline: true);
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapError(e));
    }
  }

  Future<void> register({
    String? username,
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final normalizedEmail = email.trim();
      final credential = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password.trim(),
      );

      // SOLO al registrarse por primera vez aseguramos la creación del perfil y username.
      await _profileRepository.ensureUserProfile(
        uid: credential.user!.uid,
        desiredUsername: _preferredUsername(
          email: normalizedEmail,
          displayName: name,
          fallback: 'usuario',
        ),
        name: name.trim(),
        email: normalizedEmail,
      );
      await _profileRepository.setOnlineStatus(isOnline: true);
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapError(e));
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      await _googleSignIn.signOut();
      
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) {
        throw Exception('No se pudo autenticar con Google.');
      }

      // Para Google, sí usamos ensureUserProfile por si es la primera vez que entra con este método.
      // La lógica interna de ensureUserProfile evitará recrear el username si ya existe.
      await _profileRepository.ensureUserProfile(
        uid: user.uid,
        email: user.email ?? '',
        desiredUsername: _preferredUsername(
          email: user.email,
          displayName: user.displayName,
          fallback: 'googleuser',
        ),
        name: user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : 'Usuario Google',
        photoUrl: user.photoURL ?? '',
      );
      await _emailOtpSessionController.clear();
      await _profileRepository.setOnlineStatus(isOnline: true);
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapError(e));
    } catch (e) {
      throw Exception('Error al conectar con Google: $e');
    }
  }

  Future<void> sendPhoneCode({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
  }) async {
    final completer = Completer<void>();

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber.trim(),
      verificationCompleted: (credential) async {
        await _signInWithPhoneCredential(credential);
        if (!completer.isCompleted) completer.complete();
      },
      verificationFailed: (e) {
        if (!completer.isCompleted) {
          completer.completeError(Exception(_mapError(e)));
        }
      },
      codeSent: (verificationId, resendToken) {
        onCodeSent(verificationId, resendToken);
        if (!completer.isCompleted) completer.complete();
      },
      codeAutoRetrievalTimeout: (_) {
        if (!completer.isCompleted) completer.complete();
      },
      timeout: const Duration(seconds: 60),
    );

    await completer.future;
  }

  Future<void> verifySmsCode({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode.trim(),
      );
      await _signInWithPhoneCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw Exception(_mapError(e));
    }
  }

  Future<void> _signInWithPhoneCredential(AuthCredential credential) async {
    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user;
    if (user == null) {
      throw Exception('No se pudo autenticar por telefono.');
    }

    final displayName = user.displayName?.trim();
    final phone = user.phoneNumber ?? '';
    final fallbackName = phone.isEmpty ? 'Usuario' : phone;
    await _profileRepository.ensureUserProfile(
      uid: user.uid,
      email: user.email ?? '',
      desiredUsername: _preferredUsername(
        email: user.email,
        displayName: user.displayName,
        fallback: 'usuario',
      ),
      name: displayName?.isNotEmpty == true ? displayName! : fallbackName,
      photoUrl: user.photoURL ?? '',
      bio: 'Disponible',
    );
    await _emailOtpSessionController.clear();
    await _profileRepository.setOnlineStatus(isOnline: true);
  }

  Future<void> signOut() async {
    try {
      await _profileRepository.setOnlineStatus(isOnline: false);
    } catch (_) {}
    await _emailOtpSessionController.clear();
    try {
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
    } catch (_) {
    }
    await _auth.signOut();
  }

  Future<void> sendPasswordRecovery(String email) async {
    final normalized = email.trim();
    if (normalized.isEmpty) {
      throw Exception('Escribe un correo para recuperar el PIN.');
    }
    await _auth.sendPasswordResetEmail(email: normalized);
  }

  bool hasRecentSecureSession() {
    final lastSignIn = _auth.currentUser?.metadata.lastSignInTime;
    if (lastSignIn == null) return false;
    return DateTime.now().difference(lastSignIn) <= const Duration(minutes: 15);
  }

  String _mapError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Ese correo ya esta registrado.';
      case 'invalid-email':
        return 'El correo no tiene un formato valido.';
      case 'weak-password':
        return 'La contrasena es demasiado debil.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Credenciales incorrectas.';
      case 'account-exists-with-different-credential':
        return 'Ese correo ya existe con otro metodo de acceso.';
      case 'operation-not-allowed':
        return 'Ese metodo de acceso no esta habilitado en Firebase.';
      case 'admin-restricted-operation':
        return 'Activa el acceso anonimo en Firebase Authentication para usar la vinculacion por QR en la web.';
      case 'invalid-verification-code':
        return 'El codigo ingresado no es valido.';
      case 'invalid-verification-id':
        return 'La sesion del codigo expiro. Solicita uno nuevo.';
      case 'too-many-requests':
        return 'Demasiados intentos. Prueba mas tarde.';
      default:
        return e.message ?? 'Ocurrio un error inesperado.';
    }
  }

  /// Genera un nombre de usuario preferido.
  /// Ahora prioriza la parte local del correo electrónico (antes del @).
  String _preferredUsername({
    String? email,
    String? displayName,
    required String fallback,
  }) {
    // 1. Intentar con la parte local del email (ej: kdiax01)
    final emailPart = _emailLocalPart(email);
    if (emailPart != null && emailPart.isNotEmpty) {
      return _sanitizeUsername(emailPart);
    }

    // 2. Si no hay email, intentar con el display name
    if (displayName != null && displayName.trim().isNotEmpty) {
      return _sanitizeUsername(displayName.trim());
    }

    return fallback;
  }

  String _sanitizeUsername(String input) {
    final raw = input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    return raw.isEmpty ? 'user' : raw;
  }

  String? _emailLocalPart(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    final atIndex = trimmed.indexOf('@');
    if (atIndex <= 0) return trimmed;
    return trimmed.substring(0, atIndex);
  }
}
