import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/app_user.dart';
import '../../../shared/widgets/async_value_widget.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../data/blocked_contacts_repository.dart';
import '../data/profile_repository.dart';

class ContactInfoPage extends ConsumerWidget {
  const ContactInfoPage({
    super.key,
    required this.userId,
  });

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider(userId));
    final isBlocked = ref.watch(isBlockedProvider(userId));

    return Scaffold(
      appBar: AppBar(title: const Text('Informacion del contacto')),
      body: AsyncValueWidget(
        value: profile,
        data: (user) {
          if (user == null) {
            return const Center(
              child: Text('No se encontro la informacion del contacto.'),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      UserAvatar(
                        photoUrl: user.photoUrl,
                        name: user.name,
                        radius: 42,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        user.name,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '@${user.username}',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        user.bio.isEmpty ? 'Disponible' : user.bio,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      // Llamadas ocultas para la beta
                      /*
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _startCall(
                                context,
                                ref,
                                user,
                                'audio',
                              ),
                              icon: const Icon(Icons.call_rounded),
                              label: const Text('Llamar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () => _startCall(
                                context,
                                ref,
                                user,
                                'video',
                              ),
                              icon: const Icon(Icons.videocam_rounded),
                              label: const Text('Video'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      */
                      isBlocked.when(
                        data: (blocked) => OutlinedButton.icon(
                          onPressed: () => blocked
                              ? _unblockUser(context, ref, user)
                              : _blockUser(context, ref, user),
                          icon: Icon(
                            blocked
                                ? Icons.lock_open_rounded
                                : Icons.block_rounded,
                          ),
                          label: Text(
                            blocked
                                ? 'Desbloquear contacto'
                                : 'Bloquear contacto',
                          ),
                        ),
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.mail_outline_rounded),
                      title: const Text('Correo'),
                      subtitle: Text(
                          user.email.isEmpty ? 'No disponible' : user.email),
                    ),
                    ListTile(
                      leading: const Icon(Icons.circle_rounded),
                      title: const Text('Estado'),
                      subtitle:
                          Text(user.isOnline ? 'En linea' : 'Desconectado'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.history_rounded),
                      title: const Text('Ultima actividad'),
                      subtitle: Text(
                        user.lastSeen == null
                            ? 'Sin registro'
                            : MaterialLocalizations.of(context)
                                .formatFullDate(user.lastSeen!),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _blockUser(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) async {
    await ref.read(blockedContactsRepositoryProvider).blockUser(user);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${user.name} fue bloqueado.'),
      ),
    );
  }

  Future<void> _unblockUser(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) async {
    await ref.read(blockedContactsRepositoryProvider).unblockUser(user.uid);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${user.name} fue desbloqueado.'),
      ),
    );
  }
}
