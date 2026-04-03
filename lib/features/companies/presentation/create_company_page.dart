import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/app_user.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../../search/data/search_repository.dart';
import '../data/company_billing_service.dart';
import '../data/companies_repository.dart';

class CreateCompanyPage extends ConsumerStatefulWidget {
  const CreateCompanyPage({super.key});

  @override
  ConsumerState<CreateCompanyPage> createState() => _CreateCompanyPageState();
}

class _CreateCompanyPageState extends ConsumerState<CreateCompanyPage> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();
  final List<AppUser> _users = [];
  final Set<String> _selectedIds = {};
  bool _loadingUsers = false;
  bool _saving = false;
  bool _billingBusy = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers([String query = '']) async {
    final currentUid = ref.read(currentUserProvider)?.uid;
    if (currentUid == null) return;
    setState(() => _loadingUsers = true);
    final users = await ref
        .read(searchRepositoryProvider)
        .searchUsers(query, excludeUid: currentUid);
    if (!mounted) return;
    setState(() {
      _users
        ..clear()
        ..addAll(users);
      _loadingUsers = false;
    });
  }

  Future<void> _createCompany() async {
    final name = _nameController.text.trim();
    if (name.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Escribe un nombre valido para la empresa.')),
      );
      return;
    }

    final currentUser =
        await ref.read(profileRepositoryProvider).getCurrentUser();
    if (currentUser == null) return;

    final allowedByDemoAccess =
        ProfileRepository.hasCompanyTesterAccess(currentUser);
    final allowedByBilling =
        currentUser.canCreateCompanies || allowedByDemoAccess;
    if (!mounted) return;
    if (!allowedByBilling) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Primero debes activar o restaurar la suscripción empresarial para habilitar la creación de centros privados.',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final selectedUsers =
          _users.where((user) => _selectedIds.contains(user.uid)).toList();
      final companyId =
          await ref.read(companiesRepositoryProvider).createCompany(
                owner: currentUser,
                name: name,
                description: _descriptionController.text.trim(),
                initialMembers: selectedUsers,
                allowedByBilling: allowedByBilling,
                createdAsDemo: allowedByDemoAccess,
              );
      if (!mounted) return;
      context.go('/companies/$companyId/admin?focusBilling=1');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo crear la empresa: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _runBillingAction(
    Future<void> Function() action,
  ) async {
    setState(() => _billingBusy = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _billingBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final billingAvailability = ref.watch(companyBillingAvailabilityProvider);
    final currentAppUser = ref.watch(currentAppUserProvider).valueOrNull;
    final hasDemoAccess =
        ProfileRepository.hasCompanyTesterAccess(currentAppUser);
    final hasPurchaseAccess = currentAppUser?.canCreateCompanies == true;
    final billingReady =
        hasPurchaseAccess || hasDemoAccess;

    return Scaffold(
      appBar: AppBar(title: const Text('Crear centro privado')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Centro privado de comunicación',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Crea el espacio interno de tu empresa y agrega solo a las personas autorizadas. El creador quedara como dueño y podra asignar administradores para gestionar miembros y canales.',
                  ),
                  const SizedBox(height: 14),
                  billingAvailability.when(
                    data: (availability) {
                      final product = availability.product;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (product != null)
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _InfoChip(
                                  icon: Icons.workspace_premium_rounded,
                                  label: product.title,
                                ),
                                _InfoChip(
                                  icon: Icons.payments_rounded,
                                  label: product.priceLabel,
                                ),
                                const _InfoChip(
                                  icon: Icons.lock_outline_rounded,
                                  label: 'Acceso privado por miembros',
                                ),
                                const _InfoChip(
                                  icon: Icons.campaign_rounded,
                                  label: 'Canal General incluido',
                                ),
                              ],
                            ),
                          if (product != null) const SizedBox(height: 12),
                          _BillingNotice(
                            message: hasDemoAccess
                                ? 'Acceso demo habilitado para pruebas internas. Puedes crear empresas de prueba aunque Google Play no esté listo en este dispositivo.'
                                : hasPurchaseAccess
                                    ? 'Tu cuenta ya tiene la suscripción empresarial verificada. Ya puedes crear centros privados.'
                                    : availability.message,
                            ready:
                                hasPurchaseAccess || availability.isReady || hasDemoAccess,
                          ),
                        ],
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => _BillingNotice(
                      message: hasDemoAccess
                          ? 'Acceso demo habilitado para pruebas internas. Puedes seguir creando empresas de prueba aunque Google Play falle en este equipo.'
                          : 'No pudimos conectar con Google Play desde este equipo. Pruebalo en un Android fisico con Play Store.',
                      ready: hasDemoAccess,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Nombre de la empresa',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Descripcion',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: _loadUsers,
            decoration: const InputDecoration(
              labelText: 'Agregar usuarios iniciales',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 360,
            child: _loadingUsers
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _users.length,
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      final selected = _selectedIds.contains(user.uid);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: CheckboxListTile(
                          value: selected,
                          onChanged: (_) {
                            setState(() {
                              if (selected) {
                                _selectedIds.remove(user.uid);
                              } else {
                                _selectedIds.add(user.uid);
                              }
                            });
                          },
                          secondary: UserAvatar(
                            photoUrl: user.photoUrl,
                            name: user.name,
                          ),
                          title: Text(user.name),
                          subtitle: Text('@${user.username}'),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                const Expanded(
                      child: Text(
                      'El centro privado solo se puede crear cuando tu cuenta ya tiene la suscripción empresarial verificada o acceso demo de pruebas. Al terminar, entrarás al panel para gestionar miembros, administradores y canales.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Activar permiso para crear empresas',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Compra, restaura o verifica tu suscripción en Google Play. Cuando quede validada, tu cuenta recibirá automáticamente el permiso para crear centros privados.',
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: _billingBusy
                            ? null
                            : () {
                                final messenger =
                                    ScaffoldMessenger.of(context);
                                _runBillingAction(() async {
                                  final result = await ref
                                      .read(companyBillingServiceProvider)
                                      .purchaseCompanyPlan();
                                  if (!mounted) return;
                                  messenger.showSnackBar(
                                    SnackBar(content: Text(result.message)),
                                  );
                                });
                              },
                        icon: _billingBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.workspace_premium_rounded),
                        label: const Text('Comprar'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _billingBusy
                            ? null
                            : () {
                                final messenger =
                                    ScaffoldMessenger.of(context);
                                _runBillingAction(() async {
                                  final result = await ref
                                      .read(companyBillingServiceProvider)
                                      .restoreCompanyPlan();
                                  if (!mounted) return;
                                  messenger.showSnackBar(
                                    SnackBar(content: Text(result.message)),
                                  );
                                });
                              },
                        icon: const Icon(Icons.restore_rounded),
                        label: const Text('Restaurar'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _billingBusy
                            ? null
                            : () {
                                final messenger =
                                    ScaffoldMessenger.of(context);
                                _runBillingAction(() async {
                                  final result = await ref
                                      .read(companyBillingServiceProvider)
                                      .refreshCompanyPlan();
                                  if (!mounted) return;
                                  messenger.showSnackBar(
                                    SnackBar(content: Text(result.message)),
                                  );
                                });
                              },
                        icon: const Icon(Icons.sync_rounded),
                        label: const Text('Verificar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving || !billingReady ? null : _createCompany,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.apartment_rounded),
              label: Text(
                _saving
                    ? 'Creando empresa...'
                    : billingReady
                        ? 'Crear centro privado'
                        : 'Bloqueado hasta tener plan',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }
}

class _BillingNotice extends StatelessWidget {
  const _BillingNotice({
    required this.message,
    required this.ready,
  });

  final String message;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final color = ready ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ready ? Icons.verified_rounded : Icons.lock_outline_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
