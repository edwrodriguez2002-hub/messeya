import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/app_user.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/data/auth_repository.dart';
import '../../chats/data/chats_repository.dart';
import '../../linked_devices/data/linked_devices_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../data/search_repository.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  List<AppUser> _results = [];
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final currentUid = ref.read(currentUserProvider)?.uid;
    if (currentUid == null) return;

    setState(() => _loading = true);
    try {
      final result = await ref
          .read(searchRepositoryProvider)
          .searchUsers(_controller.text, excludeUid: currentUid);
      if (!mounted) return;
      setState(() {
        _results = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error en la búsqueda: $e')),
      );
    }
  }

  Future<void> _startChat(AppUser otherUser) async {
    setState(() => _loading = true);
    try {
      final currentUser =
          await ref.read(profileRepositoryProvider).getCurrentUser();
      if (currentUser == null) {
        throw Exception('No pudimos cargar tu perfil.');
      }

      final chatId = await ref
          .read(chatsRepositoryProvider)
          .createOrGetDirectChat(otherUser, currentUser);

      if (!mounted) return;
      setState(() => _loading = false);
      
      // Cambiamos pushReplacement por push para mejorar la estabilidad de la navegación
      context.push(
        '/chat/$chatId?uid=${Uri.encodeComponent(otherUser.uid)}&name=${Uri.encodeComponent(otherUser.name)}&username=${Uri.encodeComponent(otherUser.username)}&photo=${Uri.encodeComponent(otherUser.photoUrl)}',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktopLinked = ref.watch(currentUserProvider)?.isAnonymous == true;
    final ownerUid = ref.watch(effectiveMessagingUserIdProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buscar usuarios'),
        actions: [
          IconButton(
            onPressed: _joinByInvite,
            icon: const Icon(Icons.link_rounded),
          ),
          IconButton(
            onPressed: () => context.push('/spaces/create'),
            icon: const Icon(Icons.group_add_rounded),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: isDesktopLinked
            ? Center(
                child: Text(
                  ownerUid.isEmpty
                      ? 'El cliente Windows todavia no termino de vincularse.'
                      : 'La busqueda global y el inicio de chats nuevos siguen disponibles solo en Android por ahora.',
                  textAlign: TextAlign.center,
                ),
              )
            : Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          onSubmitted: (_) => _search(),
                          decoration: InputDecoration(
                            hintText: 'Nombre, username o correo',
                            prefixIcon: const Icon(Icons.search_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 56,
                        child: FilledButton(
                          onPressed: _loading ? null : _search,
                          child: _loading 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Buscar'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: _loading && _results.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : _results.isEmpty
                            ? const Center(
                                child: Text(
                                  'Busca por nombre, username o correo para iniciar un chat.',
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : ListView.builder(
                                itemCount: _results.length,
                                itemBuilder: (context, index) {
                                  final user = _results[index];
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: ListTile(
                                      leading: UserAvatar(
                                        photoUrl: user.photoUrl,
                                        name: user.name,
                                      ),
                                      title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      subtitle: Text('@${user.username}'),
                                      trailing: FilledButton.tonal(
                                        onPressed: () => _startChat(user),
                                        child: const Text('Chatear'),
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _joinByInvite() async {
    final controller = TextEditingController();
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Unirme por enlace',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'Pega el enlace o codigo del grupo/canal',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Entrar'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (accepted != true) return;
    try {
      final chatId = await ref
          .read(chatsRepositoryProvider)
          .joinSpaceByInviteCode(controller.text);
      if (!mounted) return;
      context.push('/chat/$chatId?name=${Uri.encodeComponent('Espacio')}');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }
}
