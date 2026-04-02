import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/app_user.dart';
import '../../../shared/models/chat.dart';
import '../../../shared/models/company.dart';
import '../../../shared/models/company_member_profile.dart';
import '../../../shared/widgets/async_value_widget.dart';
import '../../../shared/widgets/messeya_ui.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/data/auth_repository.dart';
import '../../chats/data/chats_repository.dart';
import '../../chats/presentation/widgets/chat_list_tile.dart';
import '../../profile/data/profile_repository.dart';
import '../data/companies_repository.dart';

class CompanyChatsTab extends ConsumerStatefulWidget {
  const CompanyChatsTab({super.key});

  @override
  ConsumerState<CompanyChatsTab> createState() => _CompanyChatsTabState();
}

class _CompanyChatsTabState extends ConsumerState<CompanyChatsTab> {
  String _selectedCompanyId = '';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final companiesAsync = ref.watch(currentUserCompaniesProvider);
    final currentUserId = ref.watch(currentUserProvider)?.uid ?? '';

    return Scaffold(
      floatingActionButton: companiesAsync.valueOrNull?.isNotEmpty == true
          ? Padding(
              padding: const EdgeInsets.only(bottom: 95), // SUBIDO UN POCO (Antes 80)
              child: FloatingActionButton.extended(
                onPressed: () => _showComposeSheet(context),
                backgroundColor: MesseyaUi.accent,
                foregroundColor: Colors.white,
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                icon: const Icon(Icons.edit_rounded),
                label: const Text(
                  'Redactar',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: MesseyaBackground(
        child: SafeArea(
          child: AsyncValueWidget(
            value: companiesAsync,
            data: (companies) {
              if (companies.isEmpty) {
                return const _LockedCompanyView();
              }

              final selectedCompany = companies.firstWhere(
                (company) => company.id == _selectedCompanyId,
                orElse: () => companies.first,
              );
              if (_selectedCompanyId != selectedCompany.id) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() => _selectedCompanyId = selectedCompany.id);
                  }
                });
              }

              final companyChatsAsync =
                  ref.watch(companyChatsProvider(selectedCompany.id));
              final unreadCount = companyChatsAsync.valueOrNull?.fold<int>(
                    0,
                    (sum, chat) =>
                        sum + (chat.unreadCounts[currentUserId] ?? 0),
                  ) ??
                  0;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                    child: MesseyaTopBar(
                      title: 'Empresa',
                      subtitle: Text(
                        '${selectedCompany.name} · ${selectedCompany.planName.toUpperCase()}',
                        style: const TextStyle(
                          color: MesseyaUi.textMuted,
                          fontSize: 14,
                        ),
                      ),
                      actions: [
                        MesseyaRoundIconButton(
                          icon: Icons.badge_outlined,
                          tooltip: 'Perfil de empresa',
                          onTap: () => context
                              .push('/companies/${selectedCompany.id}/profile'),
                        ),
                        MesseyaRoundIconButton(
                          icon: Icons.people_outline_rounded,
                          tooltip: 'Contactos',
                          onTap: () =>
                              _showContactsSheet(context, selectedCompany),
                        ),
                        MesseyaRoundIconButton(
                          icon: Icons.admin_panel_settings_outlined,
                          tooltip: 'Panel de administrador',
                          onTap: () => context
                              .push('/companies/${selectedCompany.id}/admin'),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 92,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      itemCount: companies.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final company = companies[index];
                        final selected = company.id == selectedCompany.id;
                        return _CompanyPill(
                          companyName: company.name,
                          logoUrl: company.logoUrl,
                          planStatus: company.planStatus,
                          selected: selected,
                          onTap: () {
                            setState(() {
                              _selectedCompanyId = company.id;
                              _query = '';
                            });
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: TextField(
                      onChanged: (value) => setState(() => _query = value),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Buscar contacto o canal',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () => setState(() => _query = ''),
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 100),
                      child: AsyncValueWidget(
                        value: companyChatsAsync,
                        data: (allChats) {
                          final companyConversations = allChats
                              .where((chat) => _matchesChat(chat, _query))
                              .toList();
                          final channelChats = companyConversations
                              .where((chat) => chat.type != 'direct')
                              .toList();
                          final directChats = companyConversations
                              .where((chat) => chat.type == 'direct')
                              .toList();

                          return ListView(
                            children: [
                              _SectionHeader(
                                title: 'Contactos de empresa',
                                trailing: OutlinedButton.icon(
                                  onPressed: () => _showContactsSheet(
                                      context, selectedCompany),
                                  icon:
                                      const Icon(Icons.people_outline_rounded),
                                  label: const Text('Ver contactos'),
                                ),
                              ),
                              const SizedBox(height: 24),
                              _SectionHeader(
                                title: 'Conversaciones empresariales',
                                trailing: unreadCount > 0
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: MesseyaUi.accent,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          unreadCount > 99
                                              ? '99+'
                                              : '$unreadCount',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(height: 10),
                              if (companyConversations.isEmpty)
                                _EmptySectionCard(
                                  icon: Icons.forum_outlined,
                                  title: _query.isEmpty
                                      ? 'Aun no hay conversaciones empresariales'
                                      : 'No encontramos conversaciones',
                                  message: _query.isEmpty
                                      ? 'Usa redactar para escribir a un miembro agregado o crea un canal desde el panel de empresa.'
                                      : 'Prueba con otra palabra clave.',
                                )
                              else ...[
                                if (directChats.isNotEmpty) ...[
                                  const _SubsectionLabel('Mensajes directos'),
                                  const SizedBox(height: 10),
                                  ...directChats.map(
                                    (chat) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 14),
                                      child: ChatListTile(
                                        chat: chat,
                                        currentUserId: currentUserId,
                                        onTap: () => _openChat(
                                          context,
                                          currentUserId,
                                          chat,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                if (channelChats.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  const _SubsectionLabel('Canales internos'),
                                  const SizedBox(height: 10),
                                  ...channelChats.map(
                                    (chat) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 14),
                                      child: ChatListTile(
                                        chat: chat,
                                        currentUserId: currentUserId,
                                        onTap: () => _openChat(
                                          context,
                                          currentUserId,
                                          chat,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  bool _matchesContact(CompanyMemberContact contact, String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return true;
    return contact.displayName.toLowerCase().contains(trimmed) ||
        contact.profile.roleTitle.toLowerCase().contains(trimmed) ||
        contact.profile.department.toLowerCase().contains(trimmed) ||
        contact.user.usernameLower.contains(trimmed) ||
        contact.user.email.toLowerCase().contains(trimmed);
  }

  bool _matchesChat(Chat chat, String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return true;
    return chat.title.toLowerCase().contains(trimmed) ||
        chat.description.toLowerCase().contains(trimmed) ||
        chat.lastMessage.toLowerCase().contains(trimmed);
  }

  Future<void> _openCompanyDirectChat({
    required Company company,
    required AppUser otherUser,
  }) async {
    final currentUser =
        await ref.read(profileRepositoryProvider).getCurrentUser();
    if (currentUser == null || !mounted) return;

    final chatId = await ref
        .read(companiesRepositoryProvider)
        .createOrGetCompanyDirectChat(
          company: company,
          currentUser: currentUser,
          otherUser: otherUser,
        );

    if (!mounted) return;
    context.push(
      '/chat/$chatId?uid=${Uri.encodeComponent(otherUser.uid)}&name=${Uri.encodeComponent(otherUser.name)}&username=${Uri.encodeComponent(otherUser.username)}&photo=${Uri.encodeComponent(otherUser.photoUrl)}&companyId=${Uri.encodeComponent(company.id)}',
    );
  }

  Future<void> _showComposeSheet(BuildContext context) async {
    final companies = ref.read(currentUserCompaniesProvider).valueOrNull ?? [];
    if (companies.isEmpty) return;
    final selectedCompany = companies.firstWhere(
      (company) => company.id == _selectedCompanyId,
      orElse: () => companies.first,
    );
    final members = ref
            .read(companyMemberContactsProvider(selectedCompany.id))
            .valueOrNull
            ?.where((member) =>
                member.user.uid != (ref.read(currentUserProvider)?.uid ?? ''))
            .toList() ??
        const <CompanyMemberContact>[];

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: MesseyaUi.accent,
                    child:
                        Icon(Icons.person_outline_rounded, color: Colors.white),
                  ),
                  title: const Text('Redactar a un contacto'),
                  subtitle: const Text(
                    'Abre una conversacion directa con un miembro agregado.',
                  ),
                  onTap: () => Navigator.of(context).pop('direct'),
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: MesseyaUi.accentSoft,
                    child: Icon(Icons.campaign_outlined, color: Colors.white),
                  ),
                  title: const Text('Crear canal empresarial'),
                  subtitle: const Text(
                    'Configura un canal interno para todo el equipo.',
                  ),
                  onTap: () => Navigator.of(context).pop('channel'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!context.mounted || action == null) return;

    if (action == 'channel') {
      context.push('/companies/${selectedCompany.id}/admin');
      return;
    }

    final selectedMember = await showModalBottomSheet<CompanyMemberContact>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        var query = '';
        var filteredMembers = members;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 18,
                  right: 18,
                  top: 18,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 18,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      onChanged: (value) {
                        setModalState(() {
                          query = value;
                          filteredMembers = members
                              .where((member) => _matchesContact(member, query))
                              .toList();
                        });
                      },
                      decoration: const InputDecoration(
                        hintText: 'Buscar contacto',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Flexible(
                      child: filteredMembers.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(18),
                              child: Text('No encontramos contactos.'),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: filteredMembers.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final member = filteredMembers[index];
                                return ListTile(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  leading: UserAvatar(
                                    photoUrl: member.user.photoUrl,
                                    name: member.displayName,
                                  ),
                                  title: Text(member.displayName),
                                  subtitle: Text(member.subtitle),
                                  onTap: () =>
                                      Navigator.of(context).pop(member),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!context.mounted || selectedMember == null) return;
    await _openCompanyDirectChat(
      company: selectedCompany,
      otherUser: selectedMember.user,
    );
  }

  Future<void> _showContactsSheet(
    BuildContext context,
    Company company,
  ) async {
    final currentUserId = ref.read(currentUserProvider)?.uid ?? '';
    final members = ref
            .read(companyMemberContactsProvider(company.id))
            .valueOrNull
            ?.where((member) => member.user.uid != currentUserId)
            .toList() ??
        const <CompanyMemberContact>[];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final searchController = TextEditingController();
        var filteredMembers = members;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 18,
              right: 18,
              top: 18,
              bottom: MediaQuery.of(context).viewInsets.bottom + 18,
            ),
            child: StatefulBuilder(
              builder: (context, setModalState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Contactos agregados',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          '${filteredMembers.length}',
                          style: const TextStyle(
                            color: MesseyaUi.textMuted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    MesseyaSearchField(
                      controller: searchController,
                      hintText: 'Buscar contacto agregado',
                      onChanged: (value) {
                        setModalState(() {
                          filteredMembers = members
                              .where((member) => _matchesContact(member, value))
                              .toList();
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    Flexible(
                      child: filteredMembers.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(18),
                              child: Text(
                                'No encontramos contactos agregados.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: filteredMembers.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final member = filteredMembers[index];
                                return _CompanyContactTile(
                                  contact: member,
                                  onTap: () async {
                                    Navigator.of(context).pop();
                                    await _openCompanyDirectChat(
                                      company: company,
                                      otherUser: member.user,
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _openChat(BuildContext context, String currentUserId, Chat chat) {
    final otherId = chat.otherMemberId(currentUserId);
    final isSpace = chat.type != 'direct';
    final name = isSpace
        ? (chat.title.isEmpty ? 'Canal empresarial' : chat.title)
        : chat.memberNames[otherId] ?? 'Chat';
    final username = isSpace ? '' : chat.memberUsernames[otherId] ?? '';
    final photo = isSpace ? chat.photoUrl : chat.memberPhotos[otherId] ?? '';

    context.push(
      '/chat/${chat.id}?uid=${Uri.encodeComponent(otherId)}&name=${Uri.encodeComponent(name)}&username=${Uri.encodeComponent(username)}&photo=${Uri.encodeComponent(photo)}${chat.companyId.isEmpty ? '' : '&companyId=${Uri.encodeComponent(chat.companyId)}'}',
    );
  }
}

class _CompanyPill extends StatelessWidget {
  const _CompanyPill({
    required this.companyName,
    required this.logoUrl,
    required this.planStatus,
    required this.selected,
    required this.onTap,
  });

  final String companyName;
  final String logoUrl;
  final String planStatus;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        width: 172,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: selected
              ? MesseyaUi.accent.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: selected
                ? MesseyaUi.accentSoft
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            UserAvatar(
              photoUrl: logoUrl,
              name: companyName,
              radius: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    companyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    planStatus == 'active' || planStatus == 'grace'
                        ? 'Acceso activo'
                        : 'Plan inactivo',
                    style: const TextStyle(
                      color: MesseyaUi.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _SubsectionLabel extends StatelessWidget {
  const _SubsectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: MesseyaUi.textMuted,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _CompanyContactTile extends StatelessWidget {
  const _CompanyContactTile({
    required this.contact,
    required this.onTap,
  });

  final CompanyMemberContact contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              UserAvatar(
                photoUrl: contact.user.photoUrl,
                name: contact.displayName,
                radius: 24,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      contact.subtitle,
                      style: const TextStyle(
                        color: MesseyaUi.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: MesseyaUi.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedCompanyView extends StatelessWidget {
  const _LockedCompanyView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.apartment_rounded,
              size: 64, color: MesseyaUi.accent),
          const SizedBox(height: 20),
          Text(
            'Comunicacion empresarial',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          const Text(
            'Este apartado solo se habilita para usuarios agregados a una empresa con plan activo.',
            style: TextStyle(
              color: MesseyaUi.textMuted,
              fontSize: 15,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => context.push('/companies/create'),
            icon: const Icon(Icons.add_business_rounded),
            label: const Text('Crear empresa'),
          ),
        ],
      ),
    );
  }
}

class _EmptySectionCard extends StatelessWidget {
  const _EmptySectionCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: MesseyaUi.textMuted),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MesseyaUi.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
