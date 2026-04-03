import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/app_preferences_service.dart';
import '../../../shared/widgets/auth_action_button.dart';
import '../data/auth_repository.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({
    super.key,
    this.targetSwitchUid,
    this.targetSwitchUsername,
    this.targetSwitchName,
  });

  final String? targetSwitchUid;
  final String? targetSwitchUsername;
  final String? targetSwitchName;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  bool _isGoogleLoading = false;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rememberedAccounts = ref.watch(rememberedAccountsProvider);
    final targetAccount = rememberedAccounts
        .where((account) => account.uid == widget.targetSwitchUid)
        .firstOrNull;
    final effectiveTargetName = targetAccount?.name ??
        widget.targetSwitchName ??
        '';
    final effectiveTargetUsername = targetAccount?.username ??
        widget.targetSwitchUsername ??
        '';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bienvenido a Messeya',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Para la version publica, el acceso se realiza solo con tu cuenta de Google.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.black54,
                        ),
                      ),
                      if (effectiveTargetUsername.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.blue.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.switch_account_rounded,
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  effectiveTargetName.isEmpty
                                      ? 'Cambiando a @$effectiveTargetUsername'
                                      : 'Cambiando a $effectiveTargetName (@$effectiveTargetUsername)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.verified_user_outlined),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Inicio oficial con Google',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 10),
                            Text(
                              'Usamos Google como metodo principal de acceso para simplificar el ingreso y la revision en Play Store.',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      AuthActionButton(
                        label: effectiveTargetUsername.isEmpty
                            ? 'Continuar con Google'
                            : 'Continuar como @$effectiveTargetUsername',
                        icon: Icons.g_mobiledata_rounded,
                        onPressed: _signInWithGoogle,
                        isLoading: _isGoogleLoading,
                      ),
                      if (rememberedAccounts.length > 1) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Sesiones recordadas',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...rememberedAccounts.map(
                          (account) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              child: Text(
                                (account.name.isNotEmpty
                                        ? account.name.characters.first
                                        : account.username.characters.first)
                                    .toUpperCase(),
                              ),
                            ),
                            title: Text(account.name),
                            subtitle: Text('@${account.username}'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
