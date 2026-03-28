import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/app_user.dart';
import '../../../shared/widgets/async_value_widget.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/data/auth_repository.dart';
import '../../search/data/search_repository.dart';
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
  List<AppUser> _results = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final currentUid = ref.read(currentUserProvider)?.uid;
    if (currentUid == null) return;
    final users = await ref
        .read(searchRepositoryProvider)
        .searchUsers(_controller.text, excludeUid: currentUid);
    if (!mounted) return;
    setState(() => _results = users);
  }

  @override
  Widget build(BuildContext context) {
    final hiddenContacts = ref.watch(hiddenStatusContactsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ocultar estados a contactos')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Busca un contacto para ocultarle tus estados',
                  ),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _search,
                child: const Text('Agregar'),
              ),
            ],
          ),
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (final user in _results)
              Card(
                child: ListTile(
                  leading: UserAvatar(photoUrl: user.photoUrl, name: user.name),
                  title: Text(user.name),
                  subtitle: Text('@${user.username}'),
                  trailing: OutlinedButton(
                    onPressed: () async {
                      await ref
                          .read(statusesRepositoryProvider)
                          .hideStatusesFromContact(user);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Tus estados se ocultaran para ${user.name}.',
                          ),
                        ),
                      );
                      setState(() => _results = const []);
                    },
                    child: const Text('Ocultar'),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 18),
          Text(
            'Contactos ocultos',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          AsyncValueWidget(
            value: hiddenContacts,
            data: (items) {
              if (items.isEmpty) {
                return const Text('No has ocultado estados a ningun contacto.');
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
                        title: Text(user.name),
                        subtitle: Text('@${user.username}'),
                        trailing: TextButton(
                          onPressed: () async {
                            await ref
                                .read(statusesRepositoryProvider)
                                .showStatusesForContact(user.uid);
                          },
                          child: const Text('Mostrar'),
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
