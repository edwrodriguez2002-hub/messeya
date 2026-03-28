import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/app_preferences_service.dart';
import '../../../shared/widgets/async_value_widget.dart';
import '../../../shared/widgets/messeya_ui.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/data/auth_repository.dart';
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
  bool _initialized = false;

  void _shareApp() {
    Share.share(
      '¡Únete a Messeya! La aplicación de chat segura y resiliente con soporte para redes mesh locales. Descárgala aquí: https://play.google.com/store/apps/details?id=com.messeya.chat',
      subject: 'Invitar a Messeya',
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentAppUserProvider);
    final preferences = ref.watch(appPreferencesServiceProvider);
    final themeMode = ref.watch(themeModeProvider);

    if (!_initialized) {
      notifications = preferences.getNotificationsEnabled();
      mediaAutoDownload = preferences.getMediaAutoDownloadEnabled();
      readReceipts = preferences.getReadReceiptsEnabled();
      darkPreview = preferences.getDiscreetPreviewEnabled();
      directMessageLimit = preferences.getDirectMessageRequestLimit();
      archiveRejectedRequests = preferences.getArchiveRejectedRequests();
      onlyUntrustedRequests = preferences.getOnlyRequestForUntrustedContacts();
      _initialized = true;
    }

    return Scaffold(
      body: MesseyaBackground(
        child: SafeArea(
          child: AsyncValueWidget(
            value: me,
            data: (user) {
              if (user == null) {
                return const Center(child: Text('No se encontro el perfil.'));
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 140),
                children: [
                  const MesseyaTopBar(
                    title: 'Ajustes',
                    actions: [
                      MesseyaRoundIconButton(icon: Icons.search_rounded),
                    ],
                  ),
                  const SizedBox(height: 18),
                  
                  // Perfil Principal
                  MesseyaPanel(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            UserAvatar(photoUrl: user.photoUrl, name: user.name, radius: 34),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(user.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 4),
                                  Text('@${user.username}', style: const TextStyle(color: MesseyaUi.textMuted, fontSize: 17)),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => context.push('/profile/edit'),
                              icon: const Icon(Icons.edit_outlined, color: Colors.white70, size: 20),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  const _SectionTitle(title: 'Cuenta y Privacidad'),
                  MesseyaPanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _Tile(
                          icon: Icons.person_outline_rounded,
                          title: 'Perfil',
                          subtitle: 'Editar nombre, foto y biografía',
                          onTap: () => context.push('/profile/edit'),
                        ),
                        _Tile(
                          icon: Icons.lock_outline_rounded,
                          title: 'Privacidad',
                          subtitle: 'Documentos legales y términos',
                          onTap: () => context.push('/legal/privacy'),
                        ),
                        _Tile(
                          icon: Icons.person_add_alt_rounded,
                          title: 'Invitar amigos',
                          subtitle: 'Comparte el enlace de la Play Store',
                          onTap: _shareApp,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const _SectionTitle(title: 'Notificaciones'),
                  MesseyaPanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _SwitchTile(
                          value: notifications,
                          title: 'Notificaciones globales',
                          subtitle: 'Activar avisos de nuevos mensajes',
                          onChanged: (val) async {
                            setState(() => notifications = val);
                            await preferences.setNotificationsEnabled(val);
                          },
                        ),
                        _SwitchTile(
                          value: readReceipts,
                          title: 'Confirmaciones de lectura',
                          subtitle: 'Mostrar cuando viste un mensaje',
                          onChanged: (val) async {
                            setState(() => readReceipts = val);
                            await preferences.setReadReceiptsEnabled(val);
                          },
                        ),
                        _SwitchTile(
                          value: darkPreview,
                          title: 'Previsualización discreta',
                          subtitle: 'Ocultar contenido en notificaciones',
                          onChanged: (val) async {
                            setState(() => darkPreview = val);
                            await preferences.setDiscreetPreviewEnabled(val);
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const _SectionTitle(title: 'Chats y Multimedia'),
                  MesseyaPanel(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        _Tile(
                          icon: Icons.archive_outlined,
                          title: 'Chats archivados',
                          subtitle: 'Ver conversaciones ocultas',
                          onTap: () => context.push('/archived-chats'),
                        ),
                        _SwitchTile(
                          value: mediaAutoDownload,
                          title: 'Descarga automática',
                          subtitle: 'Guardar multimedia automáticamente',
                          onChanged: (val) async {
                            setState(() => mediaAutoDownload = val);
                            await preferences.setMediaAutoDownloadEnabled(val);
                          },
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(18, 12, 18, 8),
                          child: Text('Solicitudes de mensajes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        Slider(
                          value: directMessageLimit.toDouble(),
                          min: 1, max: 10, divisions: 9,
                          label: '$directMessageLimit',
                          onChanged: (val) async {
                            setState(() => directMessageLimit = val.round());
                            await preferences.setDirectMessageRequestLimit(directMessageLimit);
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const _SectionTitle(title: 'Seguridad y Sistema'),
                  MesseyaPanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _Tile(
                          icon: Icons.devices_outlined,
                          title: 'Dispositivos',
                          subtitle: 'Administrar sesiones vinculadas',
                          onTap: () => context.push('/settings/linked-devices'),
                        ),
                        _Tile(
                          icon: Icons.lock_person_rounded,
                          title: 'Bloqueo de aplicación',
                          subtitle: 'Configurar PIN o Biometría',
                          onTap: () => context.push('/settings/app-lock'),
                        ),
                        _Tile(
                          icon: Icons.block_outlined,
                          title: 'Usuarios bloqueados',
                          subtitle: 'Contactos restringidos',
                          onTap: () => context.push('/blocked-contacts'),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(18.0),
                          child: SegmentedButton<ThemeMode>(
                            segments: const [
                              ButtonSegment(value: ThemeMode.system, label: Text('Sistema'), icon: Icon(Icons.brightness_auto)),
                              ButtonSegment(value: ThemeMode.light, label: Text('Claro'), icon: Icon(Icons.light_mode)),
                              ButtonSegment(value: ThemeMode.dark, label: Text('Oscuro'), icon: Icon(Icons.dark_mode)),
                            ],
                            selected: {themeMode},
                            onSelectionChanged: (selection) => ref.read(themeModeProvider.notifier).setThemeMode(selection.first),
                          ),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: Text(title, style: const TextStyle(color: MesseyaUi.accentSoft, fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1.2)),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.subtitle, this.onTap});
  final IconData icon; final String title; final String subtitle; final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
      subtitle: Text(subtitle, style: const TextStyle(color: MesseyaUi.textMuted, fontSize: 13)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white24),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({required this.value, required this.title, required this.subtitle, required this.onChanged});
  final bool value; final String title; final String subtitle; final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeColor: MesseyaUi.accent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
      subtitle: Text(subtitle, style: const TextStyle(color: MesseyaUi.textMuted, fontSize: 13)),
    );
  }
}
