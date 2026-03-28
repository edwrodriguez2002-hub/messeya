import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_preferences_service.dart';
import '../../../core/services/biometric_auth_service.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/profile_repository.dart';

class AppLockPage extends ConsumerStatefulWidget {
  const AppLockPage({super.key});

  @override
  ConsumerState<AppLockPage> createState() => _AppLockPageState();
}

class _AppLockPageState extends ConsumerState<AppLockPage> {
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lockController = ref.watch(appLockControllerProvider.notifier);
    final hasPin = lockController.hasPin;
    final biometricAvailable = ref.watch(_biometricAvailableProvider);
    final currentUser = ref.watch(currentAppUserProvider).valueOrNull;
    final recentSession =
        ref.read(authRepositoryProvider).hasRecentSecureSession();

    return Scaffold(
      appBar: AppBar(title: const Text('Bloqueo por PIN')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasPin
                  ? 'Tu app ya tiene un PIN activo.'
                  : 'Configura un PIN de 4 a 6 digitos para proteger la app.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'PIN'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'Confirmar PIN'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final pin = _pinController.text.trim();
                  final confirm = _confirmController.text.trim();
                  if (pin.length < 4 || pin.length > 6) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('El PIN debe tener entre 4 y 6 digitos.'),
                      ),
                    );
                    return;
                  }
                  if (pin != confirm) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Los PIN no coinciden.'),
                      ),
                    );
                    return;
                  }
                  await lockController.setPin(pin);
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                },
                child: Text(hasPin ? 'Actualizar PIN' : 'Guardar PIN'),
              ),
            ),
            if (hasPin) ...[
              const SizedBox(height: 12),
              biometricAvailable.when(
                data: (available) => SwitchListTile(
                  value: lockController.biometricEnabled,
                  onChanged: !available
                      ? null
                      : (value) async {
                          await lockController.setBiometricEnabled(value);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                value
                                    ? 'Biometria activada.'
                                    : 'Biometria desactivada.',
                              ),
                            ),
                          );
                        },
                  title: const Text('Desbloqueo biometrico'),
                  subtitle: Text(
                    available
                        ? 'Usa huella o biometria junto al PIN'
                        : 'Este dispositivo no tiene biometria disponible',
                  ),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    await lockController.clearPin();
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                  },
                  child: const Text('Desactivar PIN'),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.mark_email_read_outlined),
                      title: const Text('Recuperar por correo'),
                      subtitle: Text(
                        currentUser?.email.isNotEmpty == true
                            ? 'Enviar enlace a ${currentUser!.email}'
                            : 'Disponible solo si tu cuenta tiene correo',
                      ),
                      onTap: currentUser?.email.isNotEmpty != true
                          ? null
                          : () async {
                              await ref
                                  .read(authRepositoryProvider)
                                  .sendPasswordRecovery(currentUser!.email);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Enlace de recuperacion enviado al correo.',
                                  ),
                                ),
                              );
                            },
                    ),
                    ListTile(
                      leading: const Icon(Icons.verified_user_outlined),
                      title: const Text('Recuperar con sesion segura'),
                      subtitle: Text(
                        recentSession
                            ? 'Tu sesion es reciente. Puedes quitar el PIN.'
                            : 'Vuelve a iniciar sesion para habilitar esta opcion.',
                      ),
                      onTap: !recentSession
                          ? null
                          : () async {
                              await lockController.clearPin();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('PIN eliminado por sesion segura.'),
                                ),
                              );
                              Navigator.of(context).pop();
                            },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final _biometricAvailableProvider = FutureProvider<bool>((ref) {
  return ref.read(biometricAuthServiceProvider).isAvailable();
});
