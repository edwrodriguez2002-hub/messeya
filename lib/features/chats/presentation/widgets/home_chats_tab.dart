import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/firebase/firebase_multi_session.dart';
import '../../../../core/services/app_preferences_service.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/models/chat.dart';
import '../../../../shared/models/remembered_account.dart';
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
    final activeSessionView = ref.watch(activeSessionViewProvider);
    final rememberedAccounts = ref.watch(rememberedAccountsProvider);
    final cachedChats = ref.watch(cachedChatsProvider);
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
                        final authRepo = ref.read(authRepositoryProvider);
                        
                        await Future.delayed(const Duration(milliseconds: 150));
                        if (!mounted) return;

                        if (value == 'contacts') {
                          this.context.push('/contacts');
                          return;
                        }
                        if (value == 'archived') {
                          this.context.push('/archived-chats');
                          return;
                        }
                        if (value == 'drafts') {
                          this.context.push('/drafts');
                          return;
                        }
                        if (value == 'linked_devices') {
                          this.context.push('/settings/linked-devices');
                          return;
                        }
                        if (value == 'edit_profile') {
                          this.context.push('/profile/edit');
                          return;
                        }
                        if (value == 'settings') {
                          this.context.push('/settings');
                          return;
                        }
                        if (value != 'logout') return;
                        try {
                          await authRepo.signOut();
                          if (mounted) {
                            this.context.go(
                                isDesktopLinked ? '/desktop-link' : '/login');
                          }
                        } catch (error) {
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
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
                child: _AccountSwitcherRow(
                  rememberedAccounts: rememberedAccounts,
                  activeSessionView: activeSessionView,
                  currentUserId: effectiveUserId,
                  onAddSession: () => _showAddSessionSheet(context),
                  onSwitchAccount: _switchToAccount,
                ),
              ),
              const SizedBox(height: 12),
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
                    isVerified: user.isVerified,
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
                      if (activeSessionView != 'all') {
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
                      }

                      final showingAll = activeSessionView == 'all';
                      final selectedRemembered = rememberedAccounts
                          .where((account) => account.uid == activeSessionView)
                          .firstOrNull;
                      final sessionItems = showingAll
                          ? _buildAggregateItems(
                              currentUserId: effectiveUserId,
                              liveChats: items,
                              rememberedAccounts: rememberedAccounts,
                              cachedChats: cachedChats,
                            )
                          : items
                              .map(
                                (chat) => _SessionChatItem(
                                  chat: chat,
                                  userId: effectiveUserId,
                                  account: rememberedAccounts
                                          .where(
                                            (account) =>
                                                account.uid == effectiveUserId,
                                          )
                                          .firstOrNull ??
                                      _fallbackCurrentAccount(
                                        effectiveUserId,
                                        appUser.valueOrNull,
                                      ),
                                  isInteractive: true,
                                ),
                              )
                              .toList();

                      final filteredItems = sessionItems.where((entry) {
                        final chat = entry.chat;
                        final chatUserId = entry.userId;
                        if (_query.isEmpty) return true;
                        final otherId = chat.otherMemberId(chatUserId);
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

                      if (!showingAll &&
                          activeSessionView.isNotEmpty &&
                          activeSessionView != effectiveUserId) {
                        return _InactiveAccountPlaceholder(
                          account: selectedRemembered,
                        );
                      }

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
                          final item = filteredItems[index];
                          final chat = item.chat;
                          final chatUserId = item.userId;
                          final otherId = chat.otherMemberId(chatUserId);
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
                            currentUserId: chatUserId,
                            accountBadgeText:
                                showingAll ? '@${item.account.username}' : null,
                            onLongPress: item.isInteractive
                                ? () => _showChatActions(context, ref, chat)
                                : null,
                            onTap: () => _openChatFromItem(
                              context,
                              item,
                              otherId: otherId,
                              name: name,
                              username: username,
                              photo: photo,
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

  List<_SessionChatItem> _buildAggregateItems({
    required String currentUserId,
    required List<Chat> liveChats,
    required List<RememberedAccount> rememberedAccounts,
    required Map<String, List<Chat>> cachedChats,
  }) {
    final items = <_SessionChatItem>[];

    for (final account in rememberedAccounts) {
      final accountChats = account.uid == currentUserId
          ? liveChats
          : (cachedChats[account.uid] ?? const <Chat>[]);
      items.addAll(
        accountChats.map(
          (chat) => _SessionChatItem(
            chat: chat,
            userId: account.uid,
            account: account,
            isInteractive: account.uid == currentUserId,
          ),
        ),
      );
    }

    items.sort((a, b) {
      final aPinned = a.chat.pinnedBy.contains(a.userId);
      final bPinned = b.chat.pinnedBy.contains(b.userId);
      if (aPinned != bPinned) return aPinned ? -1 : 1;
      final aTime = a.chat.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.chat.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    return items;
  }

  RememberedAccount _fallbackCurrentAccount(
    String uid,
    AppUser? appUser,
  ) {
    return RememberedAccount(
      uid: uid,
      username: appUser?.username ?? 'sesion',
      name: appUser?.name ?? 'Sesion actual',
      email: appUser?.email ?? '',
      photoUrl: appUser?.photoUrl ?? '',
      firebaseAppName: defaultFirebaseSessionAppName,
      lastUsedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _openChatFromItem(
    BuildContext context,
    _SessionChatItem item, {
    required String otherId,
    required String name,
    required String username,
    required String photo,
  }) {
    if (!item.isInteractive) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Este chat pertenece a @${item.account.username}. Entra primero a esa sesion para abrirlo.',
          ),
        ),
      );
      return;
    }

    context.push(
      '/chat/${item.chat.id}?uid=${Uri.encodeComponent(otherId)}&name=${Uri.encodeComponent(name)}&username=${Uri.encodeComponent(username)}&photo=${Uri.encodeComponent(photo)}',
    );
  }

  Future<void> _showAddSessionSheet(BuildContext context) async {
    final authRepo = ref.read(authRepositoryProvider);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: MesseyaPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Agregar otra sesion',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'La cuenta actual quedara recordada en este dispositivo. Luego podras volver a ella desde la fila de sesiones o verla dentro de "Todas".',
                    style: TextStyle(
                      color: MesseyaUi.textMuted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Para agregar otra, iremos al login y desde ahi entras con la nueva cuenta.',
                    style: TextStyle(
                      color: MesseyaUi.textMuted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Ir al login'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      final added = await authRepo.addGoogleSession();
      if (!mounted) return;
      if (added == null) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text(
            'Se agrego @${added.username}. Ya puedes rotar entre sesiones sin volver a iniciar.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _switchToAccount(RememberedAccount account) async {
    final effectiveUserId = ref.read(effectiveMessagingUserIdProvider);
    if (account.uid == effectiveUserId) {
      await ref.read(activeAccountUidProvider.notifier).setUid(account.uid);
      await ref.read(activeSessionViewProvider.notifier).setView(account.uid);
      return;
    }

    final targetAuth = authForSessionAppName(account.firebaseAppName);
    final canSwitchImmediately = targetAuth.currentUser?.uid == account.uid;

    if (canSwitchImmediately) {
      await ref.read(activeAccountUidProvider.notifier).setUid(account.uid);
      await ref.read(activeSessionViewProvider.notifier).setView(account.uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sesion activa cambiada a @${account.username}.'),
        ),
      );
      return;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: MesseyaPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cambiar a @${account.username}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Esta cuenta todavía no quedó autenticada con la nueva base multi-sesion. Te llevaremos al login para entrar una vez y dejarla lista para los siguientes cambios directos.',
                    style: const TextStyle(
                      color: MesseyaUi.textMuted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Cambiar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final authRepo = ref.read(authRepositoryProvider);
    try {
      await authRepo.signOut();
      if (!mounted) return;
      context.go(
        '/login?switchUid=${Uri.encodeComponent(account.uid)}&switchUsername=${Uri.encodeComponent(account.username)}&switchName=${Uri.encodeComponent(account.name)}',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    }
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

class _SessionChatItem {
  const _SessionChatItem({
    required this.chat,
    required this.userId,
    required this.account,
    required this.isInteractive,
  });

  final Chat chat;
  final String userId;
  final RememberedAccount account;
  final bool isInteractive;
}

class _AccountSwitcherRow extends ConsumerWidget {
  const _AccountSwitcherRow({
    required this.rememberedAccounts,
    required this.activeSessionView,
    required this.currentUserId,
    required this.onAddSession,
    required this.onSwitchAccount,
  });

  final List<RememberedAccount> rememberedAccounts;
  final String activeSessionView;
  final String currentUserId;
  final VoidCallback onAddSession;
  final Future<void> Function(RememberedAccount account) onSwitchAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rememberedAccounts.isEmpty && currentUserId.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MesseyaSectionLabel('Sesiones'),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _AccountChip(
                label: 'Todas',
                selected: activeSessionView == 'all',
                onTap: () => ref
                    .read(activeSessionViewProvider.notifier)
                    .setView('all'),
              ),
              ...rememberedAccounts.map(
                (account) => Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: _AccountChip(
                    label: '@${account.username}',
                    selected: activeSessionView == account.uid,
                    isCurrent: account.uid == currentUserId,
                    onTap: () async {
                      if (account.uid == currentUserId) {
                        await ref
                            .read(activeSessionViewProvider.notifier)
                            .setView(account.uid);
                        return;
                      }
                      await onSwitchAccount(account);
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: _AccountChip(
                  label: '+',
                  selected: false,
                  onTap: onAddSession,
                ),
              ),
            ],
          ),
        ),
        if (rememberedAccounts.length <= 1) ...[
          const SizedBox(height: 8),
          Text(
            'Agrega otra sesion para poder rotar entre cuentas y usar la vista "Todas".',
            style: TextStyle(
              color: MesseyaUi.textMutedFor(context),
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

class _AccountChip extends StatelessWidget {
  const _AccountChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.isCurrent = false,
  });

  final String label;
  final bool selected;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? Colors.blue.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? Colors.blueAccent
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? Colors.blueAccent
                    : MesseyaUi.textPrimaryFor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            if (isCurrent) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.check_circle_rounded,
                size: 14,
                color: Colors.greenAccent,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InactiveAccountPlaceholder extends StatelessWidget {
  const _InactiveAccountPlaceholder({
    required this.account,
  });

  final RememberedAccount? account;

  @override
  Widget build(BuildContext context) {
    final label = account == null
        ? 'Esta cuenta quedó recordada localmente.'
        : 'La cuenta @${account!.username} está recordada en este dispositivo.';

    return Center(
      child: MesseyaPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.switch_account_rounded,
              size: 36,
              color: Colors.blueAccent,
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MesseyaUi.textPrimaryFor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'La rotación visual ya está preparada. Para entrar de verdad a esa cuenta, usa Google y cámbiala en el login. La vista agregada de mensajes de varias cuentas será el siguiente paso.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MesseyaUi.textMutedFor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroProfileCard extends StatelessWidget {
  const _HeroProfileCard({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.photoUrl,
    this.isVerified = false,
  });

  final String title;
  final String subtitle;
  final String status;
  final String photoUrl;
  final bool isVerified;

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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style:
                                Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (isVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.verified_rounded,
                            color: Colors.blueAccent,
                            size: 18,
                          ),
                        ],
                      ],
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
