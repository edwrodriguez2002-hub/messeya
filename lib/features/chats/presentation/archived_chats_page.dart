import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/async_value_widget.dart';
import '../../auth/data/auth_repository.dart';
import '../data/chats_repository.dart';
import 'widgets/chat_list_tile.dart';

class ArchivedChatsPage extends ConsumerWidget {
  const ArchivedChatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archivedChats = ref.watch(archivedChatsProvider);
    final currentUserId = ref.watch(currentUserProvider)?.uid ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Chats archivados')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: AsyncValueWidget(
          value: archivedChats,
          data: (items) {
            if (items.isEmpty) {
              return const Center(
                child: Text('No tienes chats archivados.'),
              );
            }

            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final chat = items[index];
                final otherId = chat.otherMemberId(currentUserId);
                final isSpace = chat.type != 'direct';
                final name =
                    isSpace ? chat.title : chat.memberNames[otherId] ?? 'Chat';
                final username =
                    isSpace ? '' : chat.memberUsernames[otherId] ?? '';
                final photo = isSpace ? '' : chat.memberPhotos[otherId] ?? '';

                return ChatListTile(
                  chat: chat,
                  currentUserId: currentUserId,
                  onTap: () => context.push(
                    '/chat/${chat.id}?uid=${Uri.encodeComponent(otherId)}&name=${Uri.encodeComponent(name)}&username=${Uri.encodeComponent(username)}&photo=${Uri.encodeComponent(photo)}',
                  ),
                  onLongPress: () async {
                    await ref.read(chatsRepositoryProvider).toggleArchived(
                          chat.id,
                          archived: false,
                        );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Chat restaurado.')),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
