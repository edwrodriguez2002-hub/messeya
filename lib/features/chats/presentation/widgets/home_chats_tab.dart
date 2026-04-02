import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/firebase/firebase_providers.dart';
import '../../../../shared/models/chat.dart';
import '../../../../shared/widgets/async_value_widget.dart';
import '../../../../shared/widgets/messeya_ui.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../linked_devices/data/linked_devices_repository.dart';
import '../../../messages/data/messages_repository.dart';
import '../../../profile/data/profile_repository.dart';
import '../../data/chats_repository.dart';
import 'chat_list_tile.dart';

class HomeChatsTab extends ConsumerStatefulWidget {
  const HomeChatsTab({super.key});

  @override
  ConsumerState<HomeChatsTab> createState() => _HomeChatsTabState();
}

class _HomeChatsTabState extends ConsumerState<HomeChatsTab> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveUserId = ref.watch(effectiveMessagingUserIdProvider);
    final chats = ref.watch(userChatsForProvider(effectiveUserId));
    final firebaseUser = ref.watch(currentUserProvider);
    final appUser = ref.watch(currentAppUserProvider);
    final desktopLinkedSession = ref.watch(desktopClientSessionProvider);
    final isDesktopLinked = firebaseUser?.isAnonymous == true &&
        (desktopLinkedSession.valueOrNull?.isActive == true ||
            effectiveUserId.isNotEmpty);

    return Scaffold(
      body: MesseyaBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: MesseyaTopBar(
                  title: 'Mensajes',
                  actions: [
                    MesseyaRoundIconButton(
                      icon: Icons.search_rounded,
                      tooltip: 'Buscar',
                      onTap: isDesktopLinked
                          ? null
                          : () => context.push('/search'),
                    ),
                    PopupMenuButton<String>(
                      color: const Color(0xFF172340),
                      icon: const Icon(Icons.more_vert_rounded,
                          color: Colors.white),
                      onSelected: (value) async {
                        // Capturamos el router antes del delay
                        final router = GoRouter.of(context);
                        final authRepo = ref.read(authRepositoryProvider);
                        
                        await Future.delayed(const Duration(milliseconds: 150));
                        if (!mounted) return;

                        if (value == 'contacts') {
                          context.push('/contacts');
                          return;
                        }
                        if (value == 'archived') {
                          context.push('/archived-chats');
                          return;
                        }
                        if (value == 'drafts') {
                          context.push('/drafts');
                          return;
                        }
                        if (value == 'linked_devices') {
                          context.push('/settings/linked-devices');
                          return;
                        }
                        if (value == 'edit_profile') {
                          context.push('/profile/edit');
                          return;
                        }
                        if (value == 'settings') {
                          context.push('/settings');
                          return;
                        }
                        if (value != 'logout') return;
                        try {
                          await authRepo.signOut();
                          if (mounted) {
                            context.go(
                                isDesktopLinked ? '/desktop-link' : '/login');
                          }
                        } catch (error) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  error
                                      .toString()
                                      .replaceFirst('Exception: ', ''),
                                ),
                              ),
                            );
                          }
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem<String>(
                          value: 'contacts',
                          child: Text('Contactos'),
                        ),
                        const PopupMenuItem<String>(
                          value: 'archived',
                          child: Text('Chats archivados'),
                        ),
                        const PopupMenuItem<String>(
                          value: 'drafts',
                          child: Text('Borradores'),
                        ),
                        if (!isDesktopLinked)
                          const PopupMenuItem<String>(
                            value: 'linked_devices',
                            child: Text('Dispositivos vinculados'),
                          ),
                        const PopupMenuItem<String>(
                          value: 'edit_profile',
                          child: Text('Editar perfil'),
                        ),
                        const PopupMenuItem<String>(
                          value: 'settings',
                          child: Text('Ajustes'),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem<String>(
                          value: 'logout',
                          child: Text('Cerrar sesion'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: MesseyaSearchField(
                  controller: _searchController,
                  hintText: 'Buscar conversaciones',
                  onChanged: (value) {
                    setState(() => _query = value.trim().toLowerCase());
                  },
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: isDesktopLinked
                    ? desktopLinkedSession.when(
                  data: (session) => session == null
                      ? const SizedBox.shrink()
                      : _HeroProfileCard(
                    title: session.ownerName,
                    subtitle: session.ownerUsername.isEmpty
                        ? 'Cliente enlazado'
                        : '@${session.ownerUsername}',
                    status: 'Sesion vinculada a Windows',
                    photoUrl: '',
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                )
                    : appUser.when(
                  data: (user) => user == null
                      ? const SizedBox.shrink()
                      : _HeroProfileCard(
                    title: user.name,
                    subtitle: '@${user.username}',
                    status:
                    user.bio.isEmpty ? 'Disponible' : user.bio,
                    photoUrl: user.photoUrl,
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: MesseyaSectionLabel('Conversaciones'),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: AsyncValueWidget(
                    value: chats,
                    data: (items) {
                      for (final chat in items) {
                        if ((chat.unreadCounts[effectiveUserId] ?? 0) > 0) {
                          ref
                              .read(messagesRepositoryProvider)
                              .markRecentMessagesAsDelivered(
                            chatId: chat.id,
                            viewerUserId: effectiveUserId,
                          );
                        }
                      }

                      final filteredItems = items.where((chat) {
                        if (_query.isEmpty) return true;
                        final otherId = chat.otherMemberId(effectiveUserId);
                        final isSpace = chat.type != 'direct';
                        final name = (isSpace
                            ? chat.title
                            : chat.memberNames[otherId] ?? 'Chat')
                            .toLowerCase();
                        final username =
                        (isSpace ? '' : chat.memberUsernames[otherId] ?? '')
                            .toLowerCase();
                        final lastMessage = chat.lastMessage.toLowerCase();
                        return name.contains(_query) ||
                            username.contains(_query) ||
                            lastMessage.contains(_query);
                      }).toList();

                      if (filteredItems.isEmpty) {
                        return const Center(
                          child: Text(
                            'Todavia no tienes conversaciones.\nBusca un usuario para empezar.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: MesseyaUi.textMuted),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.only(bottom: 100),
                        itemCount: filteredItems.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          final chat = filteredItems[index];
                          final otherId = chat.otherMemberId(effectiveUserId);
                          final isSpace = chat.type != 'direct';
                          final name = isSpace
                              ? chat.title
                              : chat.memberNames[otherId] ?? 'Chat';
                          final username = isSpace
                              ? ''
                              : chat.memberUsernames[otherId] ?? '';
                          final photo =
                          isSpace ? '' : chat.memberPhotos[otherId] ?? '';

                          return ChatListTile(
                            chat: chat,
                            currentUserId: effectiveUserId,
                            onLongPress: () =>
                                _showChatActions(context, ref, chat),
                            onTap: () => context.push(
                              '/chat/${chat.id}?uid=${Uri.encodeComponent(otherId)}&name=${Uri.encodeComponent(name)}&username=${Uri.encodeComponent(username)}&photo=${Uri.encodeComponent(photo)}',
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showChatActions(
      BuildContext context,
      WidgetRef ref,
      Chat chat,
      ) async {
    final currentUserId = ref.read(currentUserProvider)?.uid ?? '';
    final isPinned = chat.pinnedBy.contains(currentUserId);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: Icon(
                  isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                ),
                title: Text(isPinned ? 'Desfijar chat' : 'Fijar chat'),
                onTap: () => Navigator.of(context).pop('pin'),
              ),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('Archivar chat'),
                onTap: () => Navigator.of(context).pop('archive'),
              ),
            ],
          ),
        );
      },
    );

    if (action == null) return;

    if (action == 'pin') {
      await ref.read(chatsRepositoryProvider).togglePinned(
        chat.id,
        pinned: !isPinned,
      );
      return;
    }

    if (action == 'archive') {
      await ref.read(chatsRepositoryProvider).toggleArchived(
        chat.id,
        archived: true,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat archivado.')),
      );
    }
  }
}

class _HeroProfileCard extends StatelessWidget {
  const _HeroProfileCard({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.photoUrl,
  });

  final String title;
  final String subtitle;
  final String status;
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    return MesseyaPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              UserAvatar(
                photoUrl: photoUrl,
                name: title,
                radius: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style:
                      Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: MesseyaUi.textMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 12,
                  backgroundColor: Color(0xFF43A8FF),
                  child: Icon(
                    Icons.info_outline_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
