import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

final localAuthenticationProvider = Provider<LocalAuthentication>((ref) {
  return LocalAuthentication();
});

final biometricAuthServiceProvider = Provider<BiometricAuthService>((ref) {
  return BiometricAuthService(ref.watch(localAuthenticationProvider));
});

class BiometricAuthService {
  BiometricAuthService(this._localAuth);

  final LocalAuthentication _localAuth;

  Future<bool> isAvailable() async {
    final canCheck = await _localAuth.canCheckBiometrics;
    final isSupported = await _localAuth.isDeviceSupported();
    return canCheck && isSupported;
  }

  Future<bool> authenticate() async {
    return _localAuth.authenticate(
      localizedReason: 'Autenticate para desbloquear Messeya',
      biometricOnly: true,
    );
  }
}
