import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/app_user.dart';
import '../../../shared/widgets/async_value_widget.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/contacts_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../data/statuses_repository.dart';

class HiddenStatusContactsPage extends ConsumerStatefulWidget {
  const HiddenStatusContactsPage({super.key});

  @override
  ConsumerState<HiddenStatusContactsPage> createState() =>
      _HiddenStatusContactsPageState();
}

class _HiddenStatusContactsPageState
    extends ConsumerState<HiddenStatusContactsPage> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hiddenContacts = ref.watch(hiddenStatusContactsProvider);
    final contactUidsAsync = ref.watch(myContactUidsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Privacidad de estados'),
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'BUSCAR EN CONTACTOS',
            style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            onChanged: (val) => setState(() => _query = val.trim().toLowerCase()),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Nombre o @usuario...',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 16),
          
          // LISTA DE RESULTADOS DE CONTACTOS
          contactUidsAsync.when(
            data: (uids) {
              if (uids.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('Aún no tienes contactos agregados.', style: TextStyle(color: Colors.white38)),
                );
              }
              return Column(
                children: uids.map((uid) => _ContactSearchTile(
                  uid: uid, 
                  query: _query,
                  onHide: () => setState(() => _query = ''),
                )).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Text('Error al cargar contactos: $err'),
          ),

          const SizedBox(height: 32),
          const Text(
            'CONTACTOS OCULTOS',
            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 10),
          AsyncValueWidget(
            value: hiddenContacts,
            data: (items) {
              if (items.isEmpty) {
                return const Text('No has ocultado tus estados a nadie.', style: TextStyle(color: Colors.white38));
              }
              return Column(
                children: [
                  for (final user in items)
                    Card(
                      child: ListTile(
                        leading: UserAvatar(
                          photoUrl: user.photoUrl,
                          name: user.name,
                        ),
                        title: Text(user.name, style: const TextStyle(color: Colors.white)),
                        subtitle: Text('@${user.username}', style: const TextStyle(color: Colors.white54)),
                        trailing: TextButton(
                          onPressed: () async {
                            await ref
                                .read(statusesRepositoryProvider)
                                .showStatusesForContact(user.uid);
                          },
                          child: const Text('MOSTRAR'),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ContactSearchTile extends ConsumerWidget {
  final String uid;
  final String query;
  final VoidCallback onHide;

  const _ContactSearchTile({required this.uid, required this.query, required this.onHide});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider(uid));

    return userAsync.when(
      data: (user) {
        if (user == null) return const SizedBox.shrink();
        
        // Filtro de búsqueda local
        if (query.isNotEmpty && 
            !user.name.toLowerCase().contains(query) && 
            !user.usernameLower.contains(query)) {
          return const SizedBox.shrink();
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: UserAvatar(photoUrl: user.photoUrl, name: user.name),
            title: Text(user.name, style: const TextStyle(color: Colors.white)),
            subtitle: Text('@${user.username}', style: const TextStyle(color: Colors.white54)),
            trailing: TextButton(
              onPressed: () async {
                await ref.read(statusesRepositoryProvider).hideStatusesFromContact(user);
                onHide();
              },
              child: const Text('OCULTAR'),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
