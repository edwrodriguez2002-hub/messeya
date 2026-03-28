import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_preferences_service.dart';
import 'biometric_auth_service.dart';

class AppPinLockGate extends ConsumerStatefulWidget {
  const AppPinLockGate({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  ConsumerState<AppPinLockGate> createState() => _AppPinLockGateState();
}

class _AppPinLockGateState extends ConsumerState<AppPinLockGate>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  String? _error;
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      ref.read(appLockControllerProvider.notifier).lock();
    } else if (state == AppLifecycleState.resumed) {
      _tryBiometricUnlock();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometricUnlock());
  }

  Future<void> _tryBiometricUnlock() async {
    if (_authenticating || !mounted) return;
    final lockController = ref.read(appLockControllerProvider.notifier);
    if (!lockController.hasPin || !lockController.biometricEnabled) return;
    if (ref.read(appLockControllerProvider)) return;

    final biometric = ref.read(biometricAuthServiceProvider);
    final available = await biometric.isAvailable();
    if (!available) return;

    _authenticating = true;
    try {
      final success = await biometric.authenticate();
      if (success && mounted) {
        lockController.unlock();
      }
    } finally {
      _authenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lockController = ref.watch(appLockControllerProvider.notifier);
    final unlocked = ref.watch(appLockControllerProvider);

    if (!lockController.hasPin || unlocked) {
      return widget.child;
    }

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_rounded, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'App bloqueada',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ingresa tu PIN para continuar.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: 'PIN',
                      errorText: _error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (lockController.biometricEnabled)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _tryBiometricUnlock,
                          icon: const Icon(Icons.fingerprint_rounded),
                          label: const Text('Usar biometria'),
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        final pin = _controller.text.trim();
                        if (pin == lockController.currentPin) {
                          setState(() => _error = null);
                          _controller.clear();
                          lockController.unlock();
                        } else {
                          setState(() => _error = 'PIN incorrecto');
                        }
                      },
                      child: const Text('Desbloquear'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
