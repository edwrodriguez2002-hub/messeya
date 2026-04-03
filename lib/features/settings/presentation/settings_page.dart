import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/app_preferences_service.dart';
import '../../../shared/widgets/async_value_widget.dart';
import '../../../shared/widgets/messeya_ui.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/data/auth_repository.dart';
import '../../companies/data/companies_repository.dart';
import '../../profile/data/profile_repository.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late bool notifications;
  late bool mediaAutoDownload;
  late bool readReceipts;
  late bool darkPreview;
  late int directMessageLimit;
  late bool archiveRejectedRequests;
  late bool onlyUntrustedRequests;
  late TextEditingController _signatureController;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _signatureController = TextEditingController();
  }

  @override
  void dispose() {
    _signatureController.dispose();
    super.dispose();
  }

  void _shareApp() {
    Share.share(
      '¡Únete a Messeya! Revolucionando el correo moderno. https://play.google.com/store/apps/details?id=com.messeya.chat',
      subject: 'Invitar a Messeya',
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentAppUserProvider);
    final preferences = ref.watch(appPreferencesServiceProvider);
    final themeMode = ref.watch(themeModeProvider);
    final companies = ref.watch(allCurrentUserCompaniesProvider).valueOrNull ?? const [];
    final primaryCompany = companies.isNotEmpty ? companies.first : null;

    if (!_initialized) {
      notifications = preferences.getNotificationsEnabled();
      mediaAutoDownload = preferences.getMediaAutoDownloadEnabled();
      readReceipts = preferences.getReadReceiptsEnabled();
      darkPreview = preferences.getDiscreetPreviewEnabled();
      directMessageLimit = preferences.getDirectMessageRequestLimit();
      archiveRejectedRequests = preferences.getArchiveRejectedRequests();
      onlyUntrustedRequests = preferences.getOnlyRequestForUntrustedContacts();
      _signatureController.text = preferences.getUserSignature();
      _initialized = true;
    }

    return Scaffold(
      body: MesseyaBackground(
        child: SafeArea(
          child: AsyncValueWidget(
            value: me,
            data: (user) {
              if (user == null) return const Center(child: Text('No se encontró el perfil.'));
              final hasVerificationAccess =
                  ProfileRepository.hasVerificationAccess(user);

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 160),
                children: [
                  MesseyaTopBar(
                    title: 'Ajustes',
                    subtitle: Text(
                      'Gestiona tu identidad y experiencia de correo moderno.',
                      style: TextStyle(
                        color: MesseyaUi.textMutedFor(context),
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _ProfileHero(
                    name: user.name,
                    username: user.username,
                    photoUrl: user.photoUrl,
                    isVerified: user.isVerified,
                    verificationLabel:
                        user.isVerified ? 'Cuenta verificada' : 'Cuenta estándar',
                    onEdit: () => context.push('/profile/edit'),
                  ),
                  const SizedBox(height: 18),
                  _QuickStats(
                    notificationsEnabled: notifications,
                    mediaAutoDownloadEnabled: mediaAutoDownload,
                    themeMode: themeMode,
                  ),
                  const SizedBox(height: 28),
                  
                  const _SectionTitle(title: 'Mensajería', subtitle: 'Personaliza tu firma profesional'),
                  MesseyaPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Firma Automática',
                          style: TextStyle(
                            color: MesseyaUi.textPrimaryFor(context),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _signatureController,
                          style: TextStyle(
                            color: MesseyaUi.textPrimaryFor(context),
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: 'Ej: Saludos cordiales, ${user.name}',
                            hintStyle: TextStyle(
                              color: MesseyaUi.textMutedFor(context),
                            ),
                            filled: true,
                            fillColor: MesseyaUi.isDark(context)
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.04),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                          onChanged: (val) => preferences.setUserSignature(val),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Se añadirá automáticamente al final de tus correos.',
                          style: TextStyle(
                            color: MesseyaUi.textMutedFor(context),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const _SectionTitle(title: 'Cuenta y Empresa', subtitle: 'Tu identidad y espacios de trabajo'),
                  MesseyaPanel(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        _Tile(icon: Icons.person_outline_rounded, iconColor: const Color(0xFF72D0FF), title: 'Perfil', subtitle: 'Nombre, foto y biografía', onTap: () => context.push('/profile/edit')),
                        _Tile(icon: Icons.apartment_rounded, iconColor: const Color(0xFF7DB7FF), title: primaryCompany == null ? 'Crear empresa' : 'Panel empresa', subtitle: primaryCompany == null ? 'Espacio empresarial pago' : 'Administrar ${primaryCompany.name}', onTap: () => context.push(primaryCompany == null ? '/companies/create' : '/companies/${primaryCompany.id}/admin')),
                        if (hasVerificationAccess)
                          _Tile(
                            icon: Icons.verified_user_rounded,
                            iconColor: const Color(0xFF5EA8FF),
                            title: 'Usuarios verificados',
                            subtitle: 'Marcar o quitar verificación',
                            onTap: () => context.push('/settings/user-verification'),
                          ),
                        _Tile(icon: Icons.devices_outlined, iconColor: const Color(0xFFFFC56D), title: 'Dispositivos', subtitle: 'Sesiones vinculadas', onTap: () => context.push('/settings/linked-devices')),
                        _Tile(icon: Icons.person_add_alt_rounded, iconColor: const Color(0xFF7DE2A7), title: 'Invitar amigos', subtitle: 'Compartir enlace de la app', onTap: _shareApp),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const _SectionTitle(title: 'Privacidad y Seguridad', subtitle: 'Protección de datos y acceso'),
                  MesseyaPanel(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        _SwitchTile(
                          value: readReceipts,
                          title: 'Confirmaciones de lectura',
                          subtitle: 'Mostrar cuando viste un mensaje',
                          icon: Icons.done_all_rounded,
                          iconColor: const Color(0xFF6FD7FF),
                          onChanged: (val) async {
                            setState(() => readReceipts = val);
                            await preferences.setReadReceiptsEnabled(val);
                          },
                        ),
                        _Tile(icon: Icons.lock_person_rounded, iconColor: const Color(0xFF79C0FF), title: 'Bloqueo de app', subtitle: 'Configurar PIN o huella', onTap: () => context.push('/settings/app-lock')),
                        _Tile(icon: Icons.block_outlined, iconColor: const Color(0xFFFF8FA9), title: 'Bloqueados', subtitle: 'Gestionar restricciones', onTap: () => context.push('/blocked-contacts')),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Divider(color: Colors.white10),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Límite de mensajes desconocidos', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                              const Text('Mensajes que puedes recibir de alguien que no es tu contacto.', style: TextStyle(color: MesseyaUi.textMuted, fontSize: 12)),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Icon(Icons.mail_lock_rounded, color: Colors.blue, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Slider(
                                      value: directMessageLimit.toDouble(),
                                      min: 0,
                                      max: 10,
                                      divisions: 10,
                                      label: directMessageLimit == 0 ? 'Bloqueado' : directMessageLimit.toString(),
                                      onChanged: (val) async {
                                        setState(() => directMessageLimit = val.toInt());
                                        await preferences.setDirectMessageRequestLimit(val.toInt());
                                      },
                                    ),
                                  ),
                                  Text(directMessageLimit == 0 ? 'OFF' : directMessageLimit.toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const _SectionTitle(title: 'Experiencia', subtitle: 'Apariencia y funcionamiento'),
                  MesseyaPanel(
                    child: Column(
                      children: [
                        _SwitchTile(
                          value: notifications,
                          title: 'Notificaciones',
                          subtitle: 'Avisos de nuevos correos',
                          icon: Icons.notifications_none_rounded,
                          iconColor: const Color(0xFF7BC2FF),
                          onChanged: (val) async {
                            setState(() => notifications = val);
                            await preferences.setNotificationsEnabled(val);
                          },
                        ),
                        _SwitchTile(
                          value: mediaAutoDownload,
                          title: 'Descarga automática',
                          subtitle: 'Guardar archivos al recibirlos',
                          icon: Icons.download_for_offline_outlined,
                          iconColor: const Color(0xFF81E0B0),
                          onChanged: (val) async {
                            setState(() => mediaAutoDownload = val);
                            await preferences.setMediaAutoDownloadEnabled(val);
                          },
                        ),
                        const SizedBox(height: 12),
                        _ThemeSection(
                          themeMode: themeMode,
                          onThemeChanged: (selection) => ref.read(themeModeProvider.notifier).setThemeMode(selection),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                  MesseyaPillButton(
                    label: 'Cerrar sesión',
                    icon: Icons.logout_rounded,
                    onTap: () async {
                      await ref.read(authRepositoryProvider).signOut();
                      if (context.mounted) context.go('/login');
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.name, required this.username, required this.photoUrl, required this.onEdit, required this.isVerified, required this.verificationLabel});
  final String name; final String username; final String photoUrl; final VoidCallback onEdit; final bool isVerified; final String verificationLabel;
  @override
  Widget build(BuildContext context) {
    return MesseyaPanel(
      padding: const EdgeInsets.all(0),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.06),
              MesseyaUi.accent.withValues(alpha: 0.08),
            ],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            UserAvatar(photoUrl: photoUrl, name: name, radius: 34),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: TextStyle(
                          color: MesseyaUi.textPrimaryFor(context),
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (isVerified) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.verified_rounded, color: Colors.blueAccent, size: 20),
                    ],
                  ],
                ),
                Text('@$username', style: TextStyle(color: MesseyaUi.textMutedFor(context), fontSize: 15)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isVerified
                        ? Colors.blueAccent.withValues(alpha: 0.14)
                        : MesseyaUi.isDark(context)
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: isVerified
                          ? Colors.blueAccent.withValues(alpha: 0.35)
                          : MesseyaUi.isDark(context)
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isVerified
                            ? Icons.verified_rounded
                            : Icons.shield_outlined,
                        size: 14,
                        color: isVerified
                            ? Colors.blueAccent
                            : MesseyaUi.textMutedFor(context),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        verificationLabel,
                        style: TextStyle(
                          color: isVerified
                              ? Colors.blueAccent
                              : MesseyaUi.textMutedFor(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
            IconButton(icon: Icon(Icons.edit_outlined, color: MesseyaUi.textPrimaryFor(context)), onPressed: onEdit),
          ],
        ),
      ),
    );
  }
}

class _QuickStats extends StatelessWidget {
  const _QuickStats({required this.notificationsEnabled, required this.mediaAutoDownloadEnabled, required this.themeMode});
  final bool notificationsEnabled; final bool mediaAutoDownloadEnabled; final ThemeMode themeMode;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatCard(icon: notificationsEnabled ? Icons.notifications_active : Icons.notifications_off, label: 'Alertas', active: notificationsEnabled),
        const SizedBox(width: 10),
        _StatCard(icon: Icons.download_done, label: 'Auto-Media', active: mediaAutoDownloadEnabled),
        const SizedBox(width: 10),
        _StatCard(icon: Icons.palette, label: 'Modo', active: true, value: themeMode.name.toUpperCase()),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.active, this.value});
  final IconData icon; final String label; final bool active; final String? value;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MesseyaUi.isDark(context)
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: MesseyaUi.isDark(context)
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        child: Column(children: [
          Icon(icon, color: active ? MesseyaUi.accent : MesseyaUi.textMuted, size: 20),
          const SizedBox(height: 6),
          Text(
            value ?? label,
            style: TextStyle(
              color: MesseyaUi.textPrimaryFor(context),
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ]),
      ),
    );
  }
}

class _ThemeSection extends StatelessWidget {
  const _ThemeSection({required this.themeMode, required this.onThemeChanged});
  final ThemeMode themeMode; final ValueChanged<ThemeMode> onThemeChanged;
  @override
  Widget build(BuildContext context) {
    final options = <({ThemeMode mode, String title, String subtitle, IconData icon})>[
      (
        mode: ThemeMode.light,
        title: 'Blanco',
        subtitle: 'Interfaz clara',
        icon: Icons.light_mode_rounded,
      ),
      (
        mode: ThemeMode.dark,
        title: 'Negro',
        subtitle: 'Interfaz oscura',
        icon: Icons.dark_mode_rounded,
      ),
      (
        mode: ThemeMode.system,
        title: 'Sistema',
        subtitle: 'Sigue tu equipo',
        icon: Icons.brightness_auto_rounded,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tema de la app',
          style: TextStyle(
            color: MesseyaUi.textPrimaryFor(context),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Tu elección se guarda y se mantiene hasta que vuelvas a cambiarla.',
          style: TextStyle(
            color: MesseyaUi.textMutedFor(context),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: options
              .map(
                (option) => _ThemeOptionCard(
                  title: option.title,
                  subtitle: option.subtitle,
                  icon: option.icon,
                  selected: themeMode == option.mode,
                  onTap: () => onThemeChanged(option.mode),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _ThemeOptionCard extends StatelessWidget {
  const _ThemeOptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        width: 150,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected
              ? MesseyaUi.accent.withValues(alpha: 0.16)
              : (MesseyaUi.isDark(context)
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.04)),
          border: Border.all(
            color: selected
                ? MesseyaUi.accent
                : (MesseyaUi.isDark(context)
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.06)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: selected ? MesseyaUi.accent : MesseyaUi.textPrimaryFor(context)),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                color: MesseyaUi.textPrimaryFor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: MesseyaUi.textMutedFor(context),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});
  final String title; final String subtitle;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          title,
          style: TextStyle(
            color: MesseyaUi.textPrimaryFor(context),
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        Text(
          subtitle,
          style: TextStyle(
            color: MesseyaUi.textMutedFor(context),
            fontSize: 12,
          ),
        ),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.iconColor, required this.title, required this.subtitle, this.onTap});
  final IconData icon; final Color iconColor; final String title; final String subtitle; final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(backgroundColor: iconColor.withValues(alpha: 0.1), child: Icon(icon, color: iconColor, size: 20)),
      title: Text(
        title,
        style: TextStyle(
          color: MesseyaUi.textPrimaryFor(context),
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: MesseyaUi.textMutedFor(context),
          fontSize: 12,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: MesseyaUi.textMutedFor(context),
      ),
      onTap: onTap,
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({required this.value, required this.title, required this.subtitle, required this.icon, required this.iconColor, required this.onChanged});
  final bool value; final String title; final String subtitle; final IconData icon; final Color iconColor; final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(
        title,
        style: TextStyle(
          color: MesseyaUi.textPrimaryFor(context),
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: MesseyaUi.textMutedFor(context),
          fontSize: 12,
        ),
      ),
      secondary: CircleAvatar(backgroundColor: iconColor.withValues(alpha: 0.1), child: Icon(icon, color: iconColor, size: 20)),
    );
  }
}
