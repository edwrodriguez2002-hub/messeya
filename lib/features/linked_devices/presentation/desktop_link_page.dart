import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/services/app_preferences_service.dart';
import '../../../shared/models/device_pairing_session.dart';
import '../../auth/data/auth_repository.dart';
import '../data/linked_devices_repository.dart';

class DesktopLinkPage extends ConsumerStatefulWidget {
  const DesktopLinkPage({super.key});

  @override
  ConsumerState<DesktopLinkPage> createState() => _DesktopLinkPageState();
}

class _DesktopLinkPageState extends ConsumerState<DesktopLinkPage> {
  String _sessionId = '';
  bool _loading = true;
  String? _error;
  Timer? _rotationTimer;
  Timer? _countdownTimer;
  DateTime? _expiresAt;
  int _secondsRemaining = 20;

  bool get _isWebLinkMode => kIsWeb;

  @override
  void initState() {
    super.initState();
    _initialize();
    if (_isWebLinkMode) {
      _rotationTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        if (!mounted || _loading) return;
        final prefs = ref.read(appPreferencesServiceProvider);
        if (prefs.getDesktopLinkedDeviceId().isEmpty) {
          _initialize(regenerate: true);
        }
      });
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_isWebLinkMode) return;
        if (_expiresAt == null) return;
        final remaining = _expiresAt!.difference(DateTime.now()).inSeconds;
        if (remaining < 0) return;
        if (_secondsRemaining != remaining) {
          setState(() => _secondsRemaining = remaining);
        }
      });
    }
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _initialize({bool regenerate = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).ensureAnonymousSession();
      final prefs = ref.read(appPreferencesServiceProvider);
      if (_isWebLinkMode) {
        if (regenerate) {
          await prefs.clearDesktopPairingSessionId();
        }
        final sessionId = await ref
            .read(linkedDevicesRepositoryProvider)
            .createPairingSession(
              platform: 'web',
              deviceLabel: _deviceLabel(),
              expiresIn: const Duration(seconds: 25),
            );
        if (!mounted) return;
        setState(() {
          _sessionId = sessionId;
          _loading = false;
          _expiresAt = DateTime.now().add(const Duration(seconds: 20));
          _secondsRemaining = 20;
        });
        return;
      }
      if (regenerate) {
        await prefs.clearDesktopPairingSessionId();
      }
      var sessionId = prefs.getDesktopPairingSessionId();
      if (sessionId.isEmpty) {
        sessionId = await ref
            .read(linkedDevicesRepositoryProvider)
            .createPairingSession(
              platform: 'windows',
              deviceLabel: _deviceLabel(),
            );
        await prefs.setDesktopPairingSessionId(sessionId);
      }
      if (!mounted) return;
      setState(() {
        _sessionId = sessionId;
        _loading = false;
        _expiresAt = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
        _expiresAt = null;
      });
    }
  }

  String _deviceLabel() {
    if (_isWebLinkMode) {
      return 'Messeya Web';
    }
    final host = Platform.localHostname.trim();
    if (host.isNotEmpty) {
      return 'Windows · $host';
    }
    return 'Windows vinculado';
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(appPreferencesServiceProvider);
    final linkedDeviceId = prefs.getDesktopLinkedDeviceId();
    final linkedOwnerName = prefs.getDesktopLinkedOwnerName();
    final linkedOwnerUsername = prefs.getDesktopLinkedOwnerUsername();
    final session = _sessionId.isEmpty
        ? const AsyncValue<DevicePairingSession?>.data(null)
        : ref.watch(devicePairingSessionProvider(_sessionId));

    return Scaffold(
      backgroundColor: const Color(0xFF08111F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0E1C39),
              Color(0xFF091322),
              Color(0xFF050B14),
            ],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: _isWebLinkMode ? 1080 : 460),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Card(
                color: Colors.white.withValues(alpha: 0.06),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: _loading
                      ? const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Preparando el emparejamiento con Android...'),
                          ],
                        )
                      : _error != null
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline_rounded, size: 48),
                                const SizedBox(height: 16),
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed: _initialize,
                                  child: const Text('Reintentar'),
                                ),
                              ],
                            )
                          : session.when(
                              loading: () => const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 16),
                                  Text('Esperando estado del QR...'),
                                ],
                              ),
                              error: (error, _) => Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.error_outline_rounded,
                                      size: 48),
                                  const SizedBox(height: 16),
                                  Text(
                                    error.toString(),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                              data: (pairing) {
                              if (pairing?.isLinked == true &&
                                  linkedDeviceId.isEmpty) {
                                final linkedPairing = pairing;
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) async {
                                  if (linkedPairing == null) return;
                                  await prefs.setDesktopLinkedOwnerUid(
                                    linkedPairing.ownerUid,
                                  );
                                  await prefs.setDesktopLinkedDeviceId(
                                    linkedPairing.linkedDeviceId,
                                  );
                                  await prefs.setDesktopLinkedOwnerName(
                                    linkedPairing.ownerName,
                                  );
                                  await prefs.setDesktopLinkedOwnerUsername(
                                    linkedPairing.ownerUsername,
                                  );
                                  if (context.mounted) {
                                    context.go('/home');
                                  }
                                });
                              }

                              if (linkedDeviceId.isNotEmpty ||
                                  pairing?.isLinked == true) {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.verified_rounded,
                                      size: 54,
                                      color: Colors.green,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _isWebLinkMode
                                          ? 'Messeya Web vinculado'
                                          : 'Windows vinculado',
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      linkedOwnerName.isNotEmpty
                                          ? 'Conectado a $linkedOwnerName${linkedOwnerUsername.isNotEmpty ? ' · @$linkedOwnerUsername' : ''}'
                                          : 'Este equipo ya fue aprobado desde Android.',
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 20),
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        _isWebLinkMode
                                            ? 'Esta sesion web ya quedo conectada con tu cuenta desde Android.'
                                            : 'La siguiente fase mostrara aqui tus chats sincronizados de Android a Windows.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextButton(
                                      onPressed: () async {
                                        await prefs
                                            .clearDesktopPairingSessionId();
                                        await prefs
                                            .clearDesktopLinkedDeviceId();
                                        await prefs
                                            .clearDesktopLinkedIdentity();
                                        if (!mounted) return;
                                        await _initialize(regenerate: true);
                                      },
                                      child: Text(_isWebLinkMode
                                          ? 'Generar nuevo codigo'
                                          : 'Vincular otro equipo'),
                                    ),
                                  ],
                                );
                              }

                              final qr = Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(28),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x22000000),
                                      blurRadius: 24,
                                      offset: Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: QrImageView(
                                  data: 'messeya-link:${pairing?.id ?? _sessionId}',
                                  size: _isWebLinkMode ? 280 : 220,
                                  backgroundColor: Colors.white,
                                  eyeStyle: const QrEyeStyle(
                                    eyeShape: QrEyeShape.square,
                                    color: Colors.black,
                                  ),
                                  dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: Colors.black,
                                  ),
                                ),
                              );

                              if (!_isWebLinkMode) {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Conecta tu Android con Windows',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    const Text(
                                      'Abre Messeya en tu Android, entra a Ajustes > Dispositivos vinculados y escanea este QR.',
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 22),
                                    qr,
                                    const SizedBox(height: 18),
                                    SelectableText(
                                      'Codigo: ${pairing?.id ?? _sessionId}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      pairing?.expiresAt != null
                                          ? 'Expira a las ${TimeOfDay.fromDateTime(pairing!.expiresAt!).format(context)}'
                                          : 'Codigo temporal listo',
                                    ),
                                    const SizedBox(height: 16),
                                    OutlinedButton.icon(
                                      onPressed: () => _initialize(regenerate: true),
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: const Text('Generar nuevo QR'),
                                    ),
                                  ],
                                );
                              }

                              final progress = (_secondsRemaining.clamp(0, 20)) / 20;
                              return LayoutBuilder(
                                builder: (context, constraints) {
                                  final wide = constraints.maxWidth > 760;
                                  final instructions = [
                                    'Abre Messeya en tu Android.',
                                    'Entra a Ajustes > Dispositivos vinculados.',
                                    'Escanea este codigo y aprueba la vinculación.',
                                  ];

                                  final leftPanel = Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2E78E6)
                                              .withValues(alpha: 0.18),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: const Text(
                                          'Messeya Web',
                                          style: TextStyle(
                                            color: Color(0xFF8DC3FF),
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      const Text(
                                        'Inicia sesión rápido con un QR rotativo',
                                        style: TextStyle(
                                          fontSize: 34,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          height: 1.1,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      const Text(
                                        'Escanea desde tu móvil para vincular esta pestaña como otro dispositivo de Messeya.',
                                        style: TextStyle(
                                          color: Color(0xFFB7C4DE),
                                          fontSize: 16,
                                          height: 1.45,
                                        ),
                                      ),
                                      const SizedBox(height: 22),
                                      ...instructions.indexed.map(
                                        (entry) => Padding(
                                          padding: const EdgeInsets.only(bottom: 12),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                width: 28,
                                                height: 28,
                                                alignment: Alignment.center,
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFF163A70),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Text(
                                                  '${entry.$1 + 1}',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  entry.$2,
                                                  style: const TextStyle(
                                                    color: Color(0xFFE4ECFA),
                                                    fontSize: 15,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  );

                                  final qrPanel = Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      qr,
                                      const SizedBox(height: 18),
                                      SizedBox(
                                        width: 280,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(999),
                                          child: LinearProgressIndicator(
                                            value: progress,
                                            minHeight: 8,
                                            backgroundColor:
                                                Colors.white.withValues(alpha: 0.08),
                                            valueColor:
                                                const AlwaysStoppedAnimation(
                                              Color(0xFF52A8FF),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'Este código cambia en $_secondsRemaining s',
                                        style: const TextStyle(
                                          color: Color(0xFFB7C4DE),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      SelectableText(
                                        'Codigo: ${pairing?.id ?? _sessionId}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Si no lo escaneas a tiempo, se genera uno nuevo automáticamente.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Color(0xFF97A7C8),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      OutlinedButton.icon(
                                        onPressed: () => _initialize(regenerate: true),
                                        icon: const Icon(Icons.refresh_rounded),
                                        label: const Text('Generar nuevo QR'),
                                      ),
                                    ],
                                  );

                                  return wide
                                      ? Row(
                                          children: [
                                            Expanded(child: leftPanel),
                                            const SizedBox(width: 36),
                                            qrPanel,
                                          ],
                                        )
                                      : Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            leftPanel,
                                            const SizedBox(height: 28),
                                            qrPanel,
                                          ],
                                        );
                                },
                              );
                            },
                          ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
