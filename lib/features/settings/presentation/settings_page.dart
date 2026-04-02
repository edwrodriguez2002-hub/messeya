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

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 160),
                children: [
                  MesseyaTopBar(
                    title: 'Ajustes',
                    subtitle: const Text('Gestiona tu identidad y experiencia de correo moderno.', style: TextStyle(color: MesseyaUi.textMuted, fontSize: 15)),
                  ),
                  const SizedBox(height: 18),
                  _ProfileHero(
                    name: user.name,
                    username: user.username,
                    photoUrl: user.photoUrl,
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
                        const Text('Firma Automática', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _signatureController,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: 'Ej: Saludos cordiales, ${user.name}',
                            hintStyle: const TextStyle(color: Colors.white24),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.05),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                          onChanged: (val) => preferences.setUserSignature(val),
                        ),
                        const SizedBox(height: 12),
                        const Text('Se añadirá automáticamente al final de tus correos.', style: TextStyle(color: MesseyaUi.textMuted, fontSize: 11)),
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
                        _InlineThemeSelector(
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
  const _ProfileHero({required this.name, required this.username, required this.photoUrl, required this.onEdit});
  final String name; final String username; final String photoUrl; final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    return MesseyaPanel(
      padding: const EdgeInsets.all(0),
      child: Container(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white.withOpacity(0.06), MesseyaUi.accent.withOpacity(0.08)])),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            UserAvatar(photoUrl: photoUrl, name: name, radius: 34),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
                Text('@$username', style: const TextStyle(color: MesseyaUi.textMuted, fontSize: 15)),
              ]),
            ),
            IconButton(icon: const Icon(Icons.edit_outlined, color: Colors.white), onPressed: onEdit),
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
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white.withOpacity(0.05))),
        child: Column(children: [
          Icon(icon, color: active ? MesseyaUi.accent : MesseyaUi.textMuted, size: 20),
          const SizedBox(height: 6),
          Text(value ?? label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}

class _InlineThemeSelector extends StatelessWidget {
  const _InlineThemeSelector({required this.themeMode, required this.onThemeChanged});
  final ThemeMode themeMode; final ValueChanged<ThemeMode> onThemeChanged;
  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ThemeMode>(
      style: SegmentedButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05), foregroundColor: Colors.white, selectedBackgroundColor: MesseyaUi.accent.withOpacity(0.2)),
      segments: const [
        ButtonSegment(value: ThemeMode.system, label: Text('Sistema'), icon: Icon(Icons.brightness_auto)),
        ButtonSegment(value: ThemeMode.light, label: Text('Claro'), icon: Icon(Icons.light_mode)),
        ButtonSegment(value: ThemeMode.dark, label: Text('Oscuro'), icon: Icon(Icons.dark_mode)),
      ],
      selected: {themeMode},
      onSelectionChanged: (selection) => onThemeChanged(selection.first),
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
        Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
        Text(subtitle, style: const TextStyle(color: MesseyaUi.textMuted, fontSize: 12)),
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
      leading: CircleAvatar(backgroundColor: iconColor.withOpacity(0.1), child: Icon(icon, color: iconColor, size: 20)),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: MesseyaUi.textMuted, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
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
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: MesseyaUi.textMuted, fontSize: 12)),
      secondary: CircleAvatar(backgroundColor: iconColor.withOpacity(0.1), child: Icon(icon, color: iconColor, size: 20)),
    );
  }
}
