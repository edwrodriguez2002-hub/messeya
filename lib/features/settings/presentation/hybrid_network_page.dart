import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_preferences_service.dart';
import '../../../core/services/hybrid_local_queue_service.dart';
import '../../../core/services/hybrid_sync_service.dart';
import '../../../core/services/nearby_mesh_service.dart';
import '../../../core/services/network_connectivity_service.dart';
import '../../../shared/widgets/async_value_widget.dart';

class HybridNetworkPage extends ConsumerStatefulWidget {
  const HybridNetworkPage({super.key});

  @override
  ConsumerState<HybridNetworkPage> createState() => _HybridNetworkPageState();
}

class _HybridNetworkPageState extends ConsumerState<HybridNetworkPage> {
  late bool _hybridEnabled;
  late bool _relayEnabled;
  late bool _gatewayEnabled;
  late bool _relayTermsAccepted;

  @override
  void initState() {
    super.initState();
    final preferences = ref.read(appPreferencesServiceProvider);
    _hybridEnabled = preferences.getHybridEnabled();
    _relayEnabled = true;
    _gatewayEnabled = true;
    _relayTermsAccepted = preferences.getHybridRelayTermsAccepted();
    Future.microtask(() async {
      await preferences.setHybridRelayEnabled(true);
      await preferences.setHybridGatewayEnabled(true);
    });
  }

  Future<bool> _confirmHybridConsent(BuildContext context) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Activar red hibrida'),
        content: const Text(
          'Al activar esta funcion, tu dispositivo podra enviar paquetes cercanos, participar como nodo puente y, si tu lo permites, usar internet para ayudar a sincronizar mensajes de otros usuarios. Los paquetes relay se procesan de forma silenciosa y puedes apagar esta opcion cuando quieras desde Ajustes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Acepto'),
          ),
        ],
      ),
    );
    return accepted ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final onlineState = ref.watch(networkOnlineProvider);
    final nearbyState = ref.watch(nearbyMeshStateProvider);
    final pendingMessages = ref.watch(hybridPendingMessagesProvider);
    final preferences = ref.watch(appPreferencesServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Red hibrida')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Modo comunitario',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Si lo activas, tu dispositivo podra participar en la red hibrida: envio cercano, relay silencioso y puente a internet cuando este disponible. Debe usarse solo con tu consentimiento.',
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _hybridEnabled,
                    onChanged: (value) async {
                      if (value && !_relayTermsAccepted) {
                        final accepted = await _confirmHybridConsent(context);
                        if (!accepted) {
                          return;
                        }
                        await preferences.setHybridRelayTermsAccepted(true);
                      }
                      await preferences.setHybridEnabled(value);
                      await preferences.setHybridRelayEnabled(true);
                      await preferences.setHybridGatewayEnabled(true);
                      if (!mounted) return;
                      setState(() {
                        _hybridEnabled = value;
                        _relayEnabled = true;
                        _gatewayEnabled = true;
                        if (value) {
                          _relayTermsAccepted = true;
                        }
                      });
                      if (value) {
                        await ref
                            .read(hybridSyncServiceProvider)
                            .restartNearby();
                      } else {
                        await ref.read(nearbyMeshServiceProvider).stop();
                      }
                    },
                    title: const Text('Activar red hibrida'),
                    subtitle:
                        const Text('Permite mensajeria cercana sin internet.'),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _relayEnabled,
                    onChanged: null,
                    title: const Text('Nodo puente siempre activo'),
                    subtitle: const Text(
                      'Mientras la red hibrida este encendida, este dispositivo puede reenviar paquetes cercanos sin mostrar avisos dentro de la app.',
                    ),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _gatewayEnabled,
                    onChanged: null,
                    title: const Text('Puente a internet siempre activo'),
                    subtitle: const Text(
                      'Si este dispositivo tiene internet, puede ayudar a subir paquetes offline a Firebase automaticamente.',
                    ),
                  ),
                  if (_relayTermsAccepted) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Consentimiento registrado. Puedes cambiar estas opciones cuando quieras.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Nota: en esta fase, el nodo gateway ya puede subir paquetes cercanos a la nube. La bajada completa para receptores sin internet sigue dependiendo de la siguiente capa de cifrado y relay avanzado.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () async {
                  await ref
                      .read(hybridSyncServiceProvider)
                      .flushPendingToCloud();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sincronizacion lanzada.')),
                  );
                },
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Sincronizar ahora'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(hybridSyncServiceProvider).restartNearby();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Nearby reiniciado.')),
                  );
                },
                icon: const Icon(Icons.hub_outlined),
                label: const Text('Reiniciar Nearby'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_done_outlined),
              title: const Text('Canal online'),
              subtitle: onlineState.when(
                data: (online) => Text(
                  online ? 'Firebase disponible' : 'Sin internet',
                ),
                loading: () => const Text('Verificando...'),
                error: (_, __) => const Text('No se pudo verificar la red'),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.hub_outlined),
              title: const Text('Canal offline cercano'),
              subtitle: Text(
                !_hybridEnabled
                    ? 'Desactivado por el usuario'
                    : nearbyState.running
                        ? 'Activo. Nodos conectados: ${nearbyState.connectedEndpoints.length}'
                        : 'Inactivo o pendiente de permisos',
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.route_outlined),
              title: const Text('Relay opcional'),
              subtitle: Text(
                !_relayEnabled
                    ? 'Relay silencioso desactivado'
                    : nearbyState.connectedEndpoints.isEmpty
                        ? 'No hay nodos para reenviar mensajes'
                        : 'Los nodos cercanos pueden reenviar mensajes de forma temporal',
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: const Text('Nodo gateway'),
              subtitle: Text(
                !_gatewayEnabled
                    ? 'Puente a internet desactivado'
                    : 'Si este dispositivo tiene internet, puede subir paquetes offline a la nube.',
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Cola local',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          AsyncValueWidget(
            value: pendingMessages,
            data: (items) {
              if (items.isEmpty) {
                return const Card(
                  child: ListTile(
                    title: Text('No hay mensajes pendientes'),
                    subtitle: Text('La cola local esta limpia.'),
                  ),
                );
              }
              return Column(
                children: [
                  for (final item in items)
                    Card(
                      child: ListTile(
                        title: Text(
                          item.text.isNotEmpty
                              ? item.text
                              : item.attachmentName.isNotEmpty
                                  ? item.attachmentName
                                  : 'Paquete ${item.packetType}',
                        ),
                        subtitle: Text(
                          '${item.status} - ${item.direction} - ${item.packetType} - chat ${item.chatId}',
                        ),
                        trailing: item.retryCount > 0
                            ? Text('r${item.retryCount}')
                            : null,
                      ),
                    ),
                ],
              );
            },
          ),
          if (nearbyState.lastEvent.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Ultimo evento mesh',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(nearbyState.lastEvent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
