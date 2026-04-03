import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/app_preferences_service.dart';
import '../../../shared/models/remembered_account.dart';
import '../../../shared/widgets/messeya_ui.dart';
import '../../auth/data/auth_repository.dart';
import '../../companies/data/companies_repository.dart';
import '../../companies/presentation/company_chats_tab.dart';
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

  @override
  Widget build(BuildContext context) {
    final effectiveUserId = ref.watch(effectiveMessagingUserIdProvider);
    final activeSessionView = ref.watch(activeSessionViewProvider);
    final rememberedAccounts = ref.watch(rememberedAccountsProvider);
    final chats =
        ref.watch(userChatsForProvider(effectiveUserId)).valueOrNull ??
            const [];
    final unreadChats = chats.fold<int>(
      0,
      (sum, chat) => sum + (chat.unreadCounts[effectiveUserId] ?? 0),
    );
    final unreadStatuses = ref.watch(unreadStatusesCountProvider);
    final companies =
        ref.watch(currentUserCompaniesProvider).valueOrNull ?? const [];
    final hasCompanyAccess = companies.isNotEmpty;
    final companyUnread = hasCompanyAccess
        ? companies.fold<int>(0, (sum, company) {
            final companyChats =
                ref.watch(companyChatsProvider(company.id)).valueOrNull ??
                    const [];
            return sum +
                companyChats.fold<int>(
                  0,
                  (chatSum, chat) =>
                      chatSum + (chat.unreadCounts[effectiveUserId] ?? 0),
                );
          })
        : 0;

    final firebaseUser = ref.watch(currentUserProvider);
    final isDesktopLinked =
        firebaseUser?.isAnonymous == true && effectiveUserId.isNotEmpty;

    final pages = <Widget>[
      const HomeChatsTab(),
      if (hasCompanyAccess) const CompanyChatsTab(),
      const StatusesPage(),
      const SettingsPage(),
    ];
    final navItems =
        <({String label, IconData icon, IconData selectedIcon, int count})>[
      (
        label: 'Chats',
        icon: Icons.chat_bubble_outline_rounded,
        selectedIcon: Icons.chat_bubble_rounded,
        count: unreadChats,
      ),
      if (hasCompanyAccess)
        (
          label: 'Empresa',
          icon: Icons.apartment_outlined,
          selectedIcon: Icons.apartment_rounded,
          count: companyUnread,
        ),
      (
        label: 'Estados',
        icon: Icons.copy_all_outlined,
        selectedIcon: Icons.copy_all_rounded,
        count: unreadStatuses,
      ),
      (
        label: 'Ajustes',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
        count: 0,
      ),
    ];
    if (_index >= pages.length) {
      _index = 0;
    }

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      // SOLO PARA LA PESTAÑA DE CHATS
      floatingActionButton: _index == 0
          ? Padding(
              padding: const EdgeInsets.only(bottom: 0.1), // BAJADO PARA QUE SE VEA MEJOR EN CHATS
              child: FloatingActionButton.extended(
                onPressed: isDesktopLinked
                    ? null
                    : () => _handleComposePressed(
                          context,
                          activeSessionView: activeSessionView,
                          currentUserId: effectiveUserId,
                          rememberedAccounts: rememberedAccounts,
                        ),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                elevation: 6,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          borderRadius: 34,
          child: Row(
            children: List.generate(navItems.length, (index) {
              final item = navItems[index];
              return Expanded(
                child: _NavItem(
                  label: item.label,
                  icon: item.icon,
                  selectedIcon: item.selectedIcon,
                  selected: _index == index,
                  count: item.count,
                  onTap: () => setState(() => _index = index),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Future<void> _handleComposePressed(
    BuildContext context, {
    required String activeSessionView,
    required String currentUserId,
    required List<RememberedAccount> rememberedAccounts,
  }) async {
    if (activeSessionView != 'all') {
      context.push('/compose');
      return;
    }

    final selectedUid = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ComposeAccountPicker(
          rememberedAccounts: rememberedAccounts,
          currentUserId: currentUserId,
        );
      },
    );

    if (!mounted || selectedUid == null) return;

    if (selectedUid != currentUserId) {
      ScaffoldMessenger.of(this.context).showSnackBar(
        const SnackBar(
          content: Text(
            'Por ahora solo puedes redactar desde la sesion activa. Entra a esa cuenta primero para enviar desde ella.',
          ),
        ),
      );
      return;
    }

    await ref.read(activeSessionViewProvider.notifier).setView(selectedUid);
    if (!mounted) return;
    this.context.push('/compose');
  }
}

class _ComposeAccountPicker extends StatelessWidget {
  const _ComposeAccountPicker({
    required this.rememberedAccounts,
    required this.currentUserId,
  });

  final List<RememberedAccount> rememberedAccounts;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: MesseyaPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Elegir sesion para redactar',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Desde "Todas" puedes elegir la cuenta emisora. Por ahora solo se puede enviar con la sesion que esta realmente activa.',
                style: TextStyle(
                  color: MesseyaUi.textMuted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 14),
              ...rememberedAccounts.map(
                (account) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.withValues(alpha: 0.18),
                    child: Text(
                      (account.name.isNotEmpty
                              ? account.name.characters.first
                              : account.username.isNotEmpty
                                  ? account.username.characters.first
                                  : '@')
                          .toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(
                    account.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    '@${account.username}',
                    style: const TextStyle(color: MesseyaUi.textMuted),
                  ),
                  trailing: account.uid == currentUserId
                      ? const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.greenAccent,
                        )
                      : const Icon(
                          Icons.lock_outline_rounded,
                          color: MesseyaUi.textMuted,
                        ),
                  onTap: () => Navigator.of(context).pop(account.uid),
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
