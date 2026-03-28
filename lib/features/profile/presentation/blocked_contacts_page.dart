import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/async_value_widget.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../data/blocked_contacts_repository.dart';

class BlockedContactsPage extends ConsumerWidget {
  const BlockedContactsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockedContacts = ref.watch(blockedContactsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios bloqueados')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: AsyncValueWidget(
          value: blockedContacts,
          data: (items) {
            if (items.isEmpty) {
              return const Center(
                child: Text('No tienes contactos bloqueados.'),
              );
            }

            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final user = items[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: UserAvatar(
                      photoUrl: user.photoUrl,
                      name: user.name,
                    ),
                    title: Text(user.name),
                    subtitle: Text('@${user.username}'),
                    trailing: FilledButton.tonal(
                      onPressed: () async {
                        await ref
                            .read(blockedContactsRepositoryProvider)
                            .unblockUser(user.uid);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${user.name} fue desbloqueado.'),
                          ),
                        );
                      },
                      child: const Text('Desbloquear'),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
