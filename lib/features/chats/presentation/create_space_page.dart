import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/app_user.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../../search/data/search_repository.dart';
import '../data/chats_repository.dart';

class CreateSpacePage extends ConsumerStatefulWidget {
  const CreateSpacePage({super.key});

  @override
  ConsumerState<CreateSpacePage> createState() => _CreateSpacePageState();
}

class _CreateSpacePageState extends ConsumerState<CreateSpacePage> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();
  final List<AppUser> _users = [];
  final Set<String> _selectedIds = {};
  String _type = 'group';
  bool _loadingUsers = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers([String query = '']) async {
    final currentUid = ref.read(currentUserProvider)?.uid;
    if (currentUid == null) return;
    setState(() => _loadingUsers = true);
    final users = await ref.read(searchRepositoryProvider).searchUsers(
          query,
          excludeUid: currentUid,
        );
    if (!mounted) return;
    setState(() {
      _users
        ..clear()
        ..addAll(users);
      _loadingUsers = false;
    });
  }

  Future<void> _createSpace() async {
    final title = _titleController.text.trim();
    if (title.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe un nombre valido.')),
      );
      return;
    }
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos un contacto.')),
      );
      return;
    }

    final currentUser =
        await ref.read(profileRepositoryProvider).getCurrentUser();
    if (currentUser == null) return;

    setState(() => _saving = true);
    try {
      final selectedUsers =
          _users.where((user) => _selectedIds.contains(user.uid)).toList();
      final chatId = await ref.read(chatsRepositoryProvider).createSpace(
            type: _type,
            title: title,
            description: _descriptionController.text,
            currentUser: currentUser,
            selectedUsers: selectedUsers,
          );
      if (!mounted) return;
      context.pushReplacement(
        '/chat/$chatId?uid=&name=${Uri.encodeComponent(title)}&username=&photo=',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo grupo o canal')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'group',
                  label: Text('Grupo'),
                  icon: Icon(Icons.group_rounded),
                ),
                ButtonSegment<String>(
                  value: 'channel',
                  label: Text('Canal'),
                  icon: Icon(Icons.campaign_rounded),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (value) {
                setState(() => _type = value.first);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText:
                    _type == 'group' ? 'Nombre del grupo' : 'Nombre del canal',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Descripcion',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: _loadUsers,
              decoration: const InputDecoration(
                labelText: 'Buscar contactos',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loadingUsers
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _users.length,
                      itemBuilder: (context, index) {
                        final user = _users[index];
                        final selected = _selectedIds.contains(user.uid);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: CheckboxListTile(
                            value: selected,
                            onChanged: (_) {
                              setState(() {
                                if (selected) {
                                  _selectedIds.remove(user.uid);
                                } else {
                                  _selectedIds.add(user.uid);
                                }
                              });
                            },
                            secondary: UserAvatar(
                              photoUrl: user.photoUrl,
                              name: user.name,
                            ),
                            title: Text(user.name),
                            subtitle: Text('@${user.username}'),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _createSpace,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_type == 'group' ? 'Crear grupo' : 'Crear canal'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
