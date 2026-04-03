import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/profile/data/profile_repository.dart';
import '../../../shared/models/app_user.dart';
import '../../../shared/widgets/async_value_widget.dart';
import '../../../shared/widgets/messeya_ui.dart';
import '../../../shared/widgets/user_avatar.dart';

class UserVerificationPage extends ConsumerStatefulWidget {
  const UserVerificationPage({super.key});

  @override
  ConsumerState<UserVerificationPage> createState() =>
      _UserVerificationPageState();
}

class _UserVerificationPageState extends ConsumerState<UserVerificationPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentAppUserProvider);
    final users = ref.watch(allUsersProvider(_searchController.text));

    return Scaffold(
      body: MesseyaBackground(
        child: SafeArea(
          child: AsyncValueWidget(
            value: me,
            data: (currentUser) {
              if (currentUser == null) {
                return const Center(child: Text('No se encontró tu perfil.'));
              }

              if (!ProfileRepository.hasVerificationAccess(currentUser)) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: MesseyaPanel(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            size: 40,
                            color: MesseyaUi.textMutedFor(context),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Tu cuenta no tiene permiso para verificar usuarios.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: MesseyaUi.textPrimaryFor(context),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                children: [
                  MesseyaTopBar(
                    title: 'Usuarios verificados',
                    subtitle: Text(
                      'Marca las cuentas que deben mostrar el icono azul en la app.',
                      style: TextStyle(
                        color: MesseyaUi.textMutedFor(context),
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  MesseyaSearchField(
                    controller: _searchController,
                    hintText: 'Buscar por nombre, correo o usuario',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 18),
                  AsyncValueWidget(
                    value: users,
                    data: (items) {
                      if (items.isEmpty) {
                        return MesseyaPanel(
                          child: Text(
                            'No encontramos usuarios con ese filtro.',
                            style: TextStyle(
                              color: MesseyaUi.textMutedFor(context),
                            ),
                          ),
                        );
                      }

                      return Column(
                        children: items
                            .map((user) => Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 12),
                                  child: _VerificationTile(user: user),
                                ))
                            .toList(),
                      );
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

class _VerificationTile extends ConsumerStatefulWidget {
  const _VerificationTile({
    required this.user,
  });

  final AppUser user;

  @override
  ConsumerState<_VerificationTile> createState() => _VerificationTileState();
}

class _VerificationTileState extends ConsumerState<_VerificationTile> {
  bool _busy = false;

  Future<void> _runUpdate(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setVerified(bool value) async {
    await _runUpdate(
      () => ref.read(profileRepositoryProvider).setUserVerified(
            userId: widget.user.uid,
            verified: value,
          ),
      value
          ? 'Usuario verificado correctamente.'
          : 'Verificación removida correctamente.',
    );
  }

  Future<void> _setRole({
    bool? canVerifyUsers,
    bool? isCompanyTester,
    required String success,
  }) async {
    await _runUpdate(
      () => ref.read(profileRepositoryProvider).updateUserRoles(
            userId: widget.user.uid,
            canVerifyUsers: canVerifyUsers,
            isCompanyTester: isCompanyTester,
          ),
      success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userProfileProvider(widget.user.uid));

    return MesseyaPanel(
      child: AsyncValueWidget(
        value: userAsync,
        data: (user) {
          final current = user ?? widget.user;
          return Column(
            children: [
              Row(
                children: [
                  UserAvatar(
                    photoUrl: current.photoUrl,
                    name: current.name,
                    radius: 24,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                current.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: MesseyaUi.textPrimaryFor(context),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (current.isVerified) ...[
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
                          '@${current.username}',
                          style: TextStyle(
                            color: MesseyaUi.textMutedFor(context),
                          ),
                        ),
                        if (current.email.isNotEmpty)
                          Text(
                            current.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: MesseyaUi.textMutedFor(context),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Switch(
                          value: current.isVerified,
                          onChanged: _setVerified,
                        ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _RoleSwitchChip(
                    label: 'Puede verificar',
                    value: current.canVerifyUsers,
                    onChanged: _busy
                        ? null
                        : (value) => _setRole(
                              canVerifyUsers: value,
                              success: value
                                  ? 'Permiso de verificación activado.'
                                  : 'Permiso de verificación removido.',
                            ),
                  ),
                  _RoleSwitchChip(
                    label: 'Tester de empresa',
                    value: current.isCompanyTester,
                    onChanged: _busy
                        ? null
                        : (value) => _setRole(
                              isCompanyTester: value,
                              success: value
                                  ? 'Acceso demo empresarial activado.'
                                  : 'Acceso demo empresarial removido.',
                            ),
                  ),
                  _InfoChip(
                    label: current.canCreateCompanies
                        ? 'Empresa habilitada por suscripción'
                        : 'Empresa bloqueada hasta suscripción',
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: MesseyaUi.isDark(context)
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: MesseyaUi.textMutedFor(context),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RoleSwitchChip extends StatelessWidget {
  const _RoleSwitchChip({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: value
            ? MesseyaUi.accent.withValues(alpha: 0.14)
            : (MesseyaUi.isDark(context)
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.04)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: MesseyaUi.textPrimaryFor(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}
