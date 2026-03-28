import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/messeya_ui.dart';
import '../../auth/data/auth_repository.dart';
import '../../linked_devices/data/linked_devices_repository.dart';
import '../../settings/presentation/settings_page.dart';
import '../../statuses/data/statuses_repository.dart';
import '../../statuses/presentation/statuses_page.dart';
import '../data/chats_repository.dart';
import 'widgets/home_chats_tab.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _index = 0;

  late final List<Widget> _pages = const [
    HomeChatsTab(),
    StatusesPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final effectiveUserId = ref.watch(effectiveMessagingUserIdProvider);
    final chats =
        ref.watch(userChatsForProvider(effectiveUserId)).valueOrNull ??
            const [];
    final unreadChats = chats.fold<int>(
      0,
      (sum, chat) => sum + (chat.unreadCounts[effectiveUserId] ?? 0),
    );
    final unreadStatuses = ref.watch(unreadStatusesCountProvider);
    
    final firebaseUser = ref.watch(currentUserProvider);
    final isDesktopLinked = firebaseUser?.isAnonymous == true &&
        effectiveUserId.isNotEmpty;

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: _pages,
      ),
      floatingActionButton: _index == 0 
        ? Padding(
            padding: const EdgeInsets.only(bottom: 85), // Bajado para estar más cerca de la barra de Ajustes
            child: FloatingActionButton.extended(
              onPressed: isDesktopLinked ? null : () => context.push('/compose'),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              icon: const Icon(Icons.edit_rounded),
              label: const Text(
                'Redactar',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          )
        : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: MesseyaPanel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          borderRadius: 34,
          child: Row(
            children: [
              Expanded(
                child: _NavItem(
                  label: 'Chats',
                  icon: Icons.chat_bubble_outline_rounded,
                  selectedIcon: Icons.chat_bubble_rounded,
                  selected: _index == 0,
                  count: unreadChats,
                  onTap: () => setState(() => _index = 0),
                ),
              ),
              Expanded(
                child: _NavItem(
                  label: 'Estados',
                  icon: Icons.copy_all_outlined,
                  selectedIcon: Icons.copy_all_rounded,
                  selected: _index == 1,
                  count: unreadStatuses,
                  onTap: () => setState(() => _index = 1),
                ),
              ),
              Expanded(
                child: _NavItem(
                  label: 'Ajustes',
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings_rounded,
                  selected: _index == 2,
                  count: 0,
                  onTap: () => setState(() => _index = 2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = selected ? Colors.white : MesseyaUi.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: selected ? Colors.white.withValues(alpha: 0.10) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(selected ? selectedIcon : icon, color: accent),
                if (count > 0)
                  Positioned(
                    right: -10,
                    top: -8,
                    child: Container(
                      constraints:
                          const BoxConstraints(minWidth: 18, minHeight: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: const BoxDecoration(
                        color: MesseyaUi.accent,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: accent,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
