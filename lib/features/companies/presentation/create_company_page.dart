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

  @override
  Widget build(BuildContext context) {
    final billingAvailability = ref.watch(companyBillingAvailabilityProvider);
    final currentAppUser = ref.watch(currentAppUserProvider).valueOrNull;
    final hasBusinessBypass = currentAppUser?.usernameLower == 'kdiax011';
    final billingReady =
        billingAvailability.valueOrNull?.isReady == true || hasBusinessBypass;

    return Scaffold(
      appBar: AppBar(title: const Text('Crear empresa')),
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
                    'Empresa privada dentro de Messeya',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Crea el espacio de tu empresa desde la app y activa el plan empresarial con Google Play para habilitar canales internos y acceso restringido a miembros.',
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
                                  label: 'Acceso solo para miembros',
                                ),
                              ],
                            ),
                          if (product != null) const SizedBox(height: 12),
                          _BillingNotice(
                            message: hasBusinessBypass
                                ? 'Acceso especial habilitado para @kdiax011. Puedes crear la empresa y usar el flujo empresarial aunque Google Play no este listo en este dispositivo.'
                                : availability.message,
                            ready: availability.isReady || hasBusinessBypass,
                          ),
                        ],
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => _BillingNotice(
                      message: hasBusinessBypass
                          ? 'Acceso especial habilitado para @kdiax011. Puedes continuar aunque el plugin de Google Play falle en este equipo.'
                          : 'No pudimos conectar con Google Play desde este equipo. Pruebalo en un Android fisico con Play Store.',
                      ready: hasBusinessBypass,
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
                      'La empresa solo se puede crear cuando el plan empresarial este disponible en Google Play. Despues te llevaremos al panel para activar o restaurar la suscripcion.'),
                ),
              ],
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
                        ? 'Crear empresa y ver plan'
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
