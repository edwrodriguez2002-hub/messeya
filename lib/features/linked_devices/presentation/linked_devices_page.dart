import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/async_value_widget.dart';
import '../data/linked_devices_repository.dart';

class LinkedDevicesPage extends ConsumerWidget {
  const LinkedDevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(linkedDevicesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dispositivos vinculados')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/settings/linked-devices/scan'),
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('Vincular Windows'),
      ),
      body: AsyncValueWidget(
        value: devices,
        data: (items) {
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aun no tienes equipos vinculados.\nEscanea el QR desde tu Windows para conectarlo con tu Android.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final device = items[index];
              final isActive = device.isActive;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      device.platform == 'windows'
                          ? Icons.desktop_windows_rounded
                          : Icons.devices_other_rounded,
                    ),
                  ),
                  title: Text(
                    device.deviceLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    isActive
                        ? 'Activo${device.ownerUsername.isNotEmpty ? ' · @${device.ownerUsername}' : ''}'
                        : 'Revocado',
                  ),
                  trailing: isActive
                      ? TextButton(
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) {
                                return AlertDialog(
                                  title: const Text(
                                      'Desvincular este dispositivo'),
                                  content: Text(
                                    'Se cerrara el acceso de ${device.deviceLabel}.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('Cancelar'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: const Text('Desvincular'),
                                    ),
                                  ],
                                );
                              },
                            );
                            if (confirmed != true) return;
                            await ref
                                .read(linkedDevicesRepositoryProvider)
                                .revokeLinkedDevice(device);
                          },
                          child: const Text('Desvincular'),
                        )
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
