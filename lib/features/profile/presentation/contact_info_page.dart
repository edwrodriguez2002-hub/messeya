import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../companies/data/companies_repository.dart';
import '../../../shared/models/company_member_profile.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/widgets/async_value_widget.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../data/blocked_contacts_repository.dart';
import '../data/contacts_repository.dart';
import '../data/profile_repository.dart';

class ContactInfoPage extends ConsumerWidget {
  const ContactInfoPage({
    super.key,
    required this.userId,
    this.companyId = '',
  });

  final String userId;
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider(userId));
    final isBlocked = ref.watch(isBlockedProvider(userId));
    final isContactAsync = ref.watch(isContactProvider(userId));
    
    final companyProfile = companyId.isEmpty
        ? null
        : ref.watch(
            companyMemberProfileProvider(
              (companyId: companyId, userId: userId),
            ),
          );

    return Scaffold(
      appBar: AppBar(title: const Text('Informacion del contacto')),
      body: AsyncValueWidget(
        value: profile,
        data: (user) {
          if (user == null) {
            return const Center(
              child: Text('No se encontro la informacion del contacto.'),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      UserAvatar(
                        photoUrl: user.photoUrl,
                        name: user.name,
                        radius: 42,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              user.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          if (user.isVerified) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.verified_rounded,
                              color: Colors.blueAccent,
                              size: 24,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '@${user.username}',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        user.bio.isEmpty ? 'Disponible' : user.bio,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      
                      // BOTÓN DINÁMICO: AGREGAR A CONTACTOS
                      isContactAsync.when(
                        data: (isContact) {
                          if (isContact) {
                            return const Chip(
                              label: Text('En tus contactos'),
                              avatar: Icon(Icons.check, size: 16, color: Colors.green),
                            );
                          }
                          return FilledButton.icon(
                            onPressed: () => ref.read(contactsRepositoryProvider).addToContacts(userId),
                            icon: const Icon(Icons.person_add_rounded),
                            label: const Text('Agregar a contactos'),
                          );
                        },
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                      
                      const SizedBox(height: 12),
                      isBlocked.when(
                        data: (blocked) => OutlinedButton.icon(
                          onPressed: () => blocked
                              ? _unblockUser(context, ref, user)
                              : _blockUser(context, ref, user),
                          icon: Icon(
                            blocked
                                ? Icons.lock_open_rounded
                                : Icons.block_rounded,
                          ),
                          label: Text(
                            blocked
                                ? 'Desbloquear contacto'
                                : 'Bloquear contacto',
                          ),
                        ),
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
              if (companyProfile != null) ...[
                const SizedBox(height: 16),
                AsyncValueWidget(
                  value: companyProfile,
                  data: (memberProfile) {
                    if (memberProfile == null) {
                      return const SizedBox.shrink();
                    }
                    return _CompanyProfileCard(profile: memberProfile);
                  },
                ),
              ],
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.mail_outline_rounded),
                      title: const Text('Correo'),
                      subtitle: Text(
                          user.email.isEmpty ? 'No disponible' : user.email),
                    ),
                    ListTile(
                      leading: const Icon(Icons.circle_rounded),
                      title: const Text('Estado'),
                      subtitle:
                          Text(user.isOnline ? 'En linea' : 'Desconectado'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.history_rounded),
                      title: const Text('Ultima actividad'),
                      subtitle: Text(
                        user.lastSeen == null
                            ? 'Sin registro'
                            : MaterialLocalizations.of(context)
                                .formatFullDate(user.lastSeen!),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _blockUser(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) async {
    await ref.read(blockedContactsRepositoryProvider).blockUser(user);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${user.name} fue bloqueado.'),
      ),
    );
  }

  Future<void> _unblockUser(
    BuildContext context,
    WidgetRef ref,
    AppUser user,
  ) async {
    await ref.read(blockedContactsRepositoryProvider).unblockUser(user.uid);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${user.name} fue desbloqueado.'),
      ),
    );
  }
}

class _CompanyProfileCard extends StatelessWidget {
  const _CompanyProfileCard({
    required this.profile,
  });

  final CompanyMemberProfile profile;

  @override
  Widget build(BuildContext context) {
    final items = <({IconData icon, String title, String value})>[
      if (profile.displayName.trim().isNotEmpty)
        (
          icon: Icons.person_outline_rounded,
          title: 'Nombre en empresa',
          value: profile.displayName.trim(),
        ),
      if (profile.roleTitle.trim().isNotEmpty)
        (
          icon: Icons.badge_outlined,
          title: 'Cargo',
          value: profile.roleTitle.trim(),
        ),
      if (profile.department.trim().isNotEmpty)
        (
          icon: Icons.apartment_rounded,
          title: 'Departamento',
          value: profile.department.trim(),
        ),
      if (profile.workEmail.trim().isNotEmpty)
        (
          icon: Icons.work_outline_rounded,
          title: 'Correo corporativo',
          value: profile.workEmail.trim(),
        ),
      if (profile.workPhone.trim().isNotEmpty)
        (
          icon: Icons.phone_in_talk_outlined,
          title: 'Telefono o extension',
          value: profile.workPhone.trim(),
        ),
      if (profile.notes.trim().isNotEmpty)
        (
          icon: Icons.sticky_note_2_outlined,
          title: 'Notas',
          value: profile.notes.trim(),
        ),
    ];

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.business_center_outlined),
            title: const Text('Informacion en la empresa'),
            subtitle: Text(
              items.length > 1
                  ? 'Ficha empresarial disponible'
                  : 'Todavia no completo mas datos empresariales.',
            ),
          ),
          ...items.map(
            (item) => ListTile(
              leading: Icon(item.icon),
              title: Text(item.title),
              subtitle: Text(item.value),
            ),
          ),
        ],
      ),
    );
  }
}
