import 'dart:io';

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

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize({bool regenerate = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).ensureAnonymousSession();
      final prefs = ref.read(appPreferencesServiceProvider);
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
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  String _deviceLabel() {
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Card(
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
                                    const Text(
                                      'Windows vinculado',
                                      style: TextStyle(
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
                                        'La siguiente fase mostrara aqui tus chats sincronizados de Android a Windows.',
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
                                      child: const Text('Vincular otro equipo'),
                                    ),
                                  ],
                                );
                              }

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
                                  Container(
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: QrImageView(
                                      data:
                                          'messeya-link:${pairing?.id ?? _sessionId}',
                                      size: 220,
                                      eyeStyle: const QrEyeStyle(
                                        eyeShape: QrEyeShape.square,
                                      ),
                                      dataModuleStyle: const QrDataModuleStyle(
                                        dataModuleShape:
                                            QrDataModuleShape.square,
                                      ),
                                    ),
                                  ),
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
                                    onPressed: () =>
                                        _initialize(regenerate: true),
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Generar nuevo QR'),
                                  ),
                                ],
                              );
                            },
                          ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
