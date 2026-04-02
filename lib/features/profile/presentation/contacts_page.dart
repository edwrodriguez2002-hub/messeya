import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/app_user.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../data/contacts_repository.dart';
import '../data/profile_repository.dart';

class ContactsPage extends ConsumerWidget {
  const ContactsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactUidsAsync = ref.watch(myContactUidsProvider);
    final requestUidsAsync = ref.watch(incomingRequestUidsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Contactos'),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: CustomScrollView(
        slivers: [
          // 1. SOLICITUDES PENDIENTES (Solo UIDs)
          requestUidsAsync.when(
            data: (uids) {
              if (uids.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
              return SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        'SOLICITUDES PENDIENTES',
                        style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    ...uids.map((uid) => _UserRequestTile(uid: uid)),
                    const Divider(color: Colors.white10, height: 32),
                  ],
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(child: LinearProgressIndicator()),
            error: (err, _) => SliverToBoxAdapter(child: Text('Error: $err', style: const TextStyle(color: Colors.white24))),
          ),

          // 2. TÍTULO DE MIS CONTACTOS
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'MIS CONTACTOS',
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),

          // 3. LISTA DE CONTACTOS (Solo UIDs con SliverList)
          contactUidsAsync.when(
            data: (uids) {
              if (uids.isEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text('Aún no tienes contactos.', style: TextStyle(color: Colors.white38)),
                  ),
                );
              }
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _UserContactTile(uid: uids[index]),
                  childCount: uids.length,
                ),
              );
            },
            loading: () => const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
            error: (err, _) => SliverToBoxAdapter(child: Center(child: Text('Error: $err'))),
          ),
        ],
      ),
    );
  }
}

class _UserContactTile extends ConsumerWidget {
  final String uid;
  const _UserContactTile({required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider(uid));
    
    return userAsync.when(
      data: (user) {
        if (user == null) return const SizedBox.shrink();
        return ListTile(
          leading: UserAvatar(photoUrl: user.photoUrl, name: user.name),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  user.name,
                  style: const TextStyle(color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (user.isVerified) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.verified_rounded,
                  color: Colors.blueAccent,
                  size: 16,
                ),
              ],
            ],
          ),
          subtitle: Text('@${user.username}', style: const TextStyle(color: Colors.white38)),
          onTap: () => context.push('/contact/${user.uid}'),
        );
      },
      loading: () => const ListTile(title: Text('Cargando...', style: TextStyle(color: Colors.white24))),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _UserRequestTile extends ConsumerWidget {
  final String uid;
  const _UserRequestTile({required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProfileProvider(uid));

    return userAsync.when(
      data: (user) {
        if (user == null) return const SizedBox.shrink();
        return ListTile(
          leading: UserAvatar(photoUrl: user.photoUrl, name: user.name),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  user.name,
                  style: const TextStyle(color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (user.isVerified) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.verified_rounded,
                  color: Colors.blueAccent,
                  size: 16,
                ),
              ],
            ],
          ),
          subtitle: const Text('Solicitud pendiente', style: TextStyle(color: Colors.blue, fontSize: 11)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.check_circle, color: Colors.green),
                onPressed: () => ref.read(contactsRepositoryProvider).acceptRequest(uid),
              ),
              IconButton(
                icon: const Icon(Icons.cancel, color: Colors.redAccent),
                onPressed: () => ref.read(contactsRepositoryProvider).rejectRequest(uid),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
