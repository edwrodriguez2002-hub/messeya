import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../shared/models/company.dart';
import '../../../shared/models/company_member_profile.dart';
import '../../../shared/widgets/async_value_widget.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../../search/data/search_repository.dart';
import '../data/company_billing_service.dart';
import '../data/companies_repository.dart';

class CompanyAdminPage extends ConsumerStatefulWidget {
  const CompanyAdminPage({
    super.key,
    required this.companyId,
    this.focusBilling = false,
  });

  final String companyId;
  final bool focusBilling;

  @override
  ConsumerState<CompanyAdminPage> createState() => _CompanyAdminPageState();
}

class _CompanyAdminPageState extends ConsumerState<CompanyAdminPage> {
  bool _working = false;
  bool _billingBusy = false;

  Future<void> _runBillingAction(
    Future<CompanyBillingResult> Function() action,
  ) async {
    setState(() => _billingBusy = true);
    try {
      final result = await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.renewsAt == null
                ? result.message
                : '${result.message} Renueva ${DateFormat('dd/MM/yyyy').format(result.renewsAt!)}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _billingBusy = false);
    }
  }

  Future<void> _addMembers() async {
    final currentUid = ref.read(currentUserProvider)?.uid;
    if (currentUid == null) return;
    final users = await ref
        .read(searchRepositoryProvider)
        .searchUsers('', excludeUid: currentUid);
    if (!mounted) return;

    final selected = <String>{};
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Agregar miembros',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        final isSelected = selected.contains(user.uid);
                        return CheckboxListTile(
                          value: isSelected,
                          onChanged: (_) {
                            setModalState(() {
                              if (isSelected) {
                                selected.remove(user.uid);
                              } else {
                                selected.add(user.uid);
                              }
                            });
                          },
                          title: Text(user.name),
                          subtitle: Text('@${user.username}'),
                          secondary: UserAvatar(
                            photoUrl: user.photoUrl,
                            name: user.name,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Agregar seleccionados'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (accepted != true || selected.isEmpty) return;
    setState(() => _working = true);
    try {
      final selectedUsers =
          users.where((user) => selected.contains(user.uid)).toList();
      await ref.read(companiesRepositoryProvider).addMembers(
            companyId: widget.companyId,
            users: selectedUsers,
          );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _createChannel() async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    bool onlyAdminsCanPost = false;
    String channelKind = 'custom';

    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Nuevo canal empresarial',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    decoration:
                        const InputDecoration(labelText: 'Nombre del canal'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Descripcion'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: channelKind,
                    decoration:
                        const InputDecoration(labelText: 'Tipo de canal'),
                    items: const [
                      DropdownMenuItem(
                        value: 'teams',
                        child: Text('Equipo'),
                      ),
                      DropdownMenuItem(
                        value: 'project',
                        child: Text('Proyecto'),
                      ),
                      DropdownMenuItem(
                        value: 'support',
                        child: Text('Soporte'),
                      ),
                      DropdownMenuItem(
                        value: 'custom',
                        child: Text('Personalizado'),
                      ),
                    ],
                    onChanged: (value) {
                      setModalState(() => channelKind = value ?? 'custom');
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: onlyAdminsCanPost,
                    onChanged: (value) {
                      setModalState(() => onlyAdminsCanPost = value);
                    },
                    title: const Text('Solo admins pueden publicar'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Crear canal'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (accepted != true || titleController.text.trim().length < 3) return;

    final company = ref.read(companyProvider(widget.companyId)).valueOrNull;
    final currentUser =
        await ref.read(profileRepositoryProvider).getCurrentUser();
    if (company == null || currentUser == null) return;

    setState(() => _working = true);
    try {
      final chatId =
          await ref.read(companiesRepositoryProvider).createCompanyChannel(
                company: company,
                currentUser: currentUser,
                title: titleController.text.trim(),
                description: descriptionController.text.trim(),
                onlyAdminsCanPost: onlyAdminsCanPost,
                channelKind: channelKind,
              );
      if (!mounted) return;
      context.push(
          '/chat/$chatId?name=${Uri.encodeComponent(titleController.text.trim())}');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final companyAsync = ref.watch(companyProvider(widget.companyId));
    final currentUserId = ref.watch(currentUserProvider)?.uid ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Centro privado')),
      body: AsyncValueWidget(
        value: companyAsync,
        data: (company) {
          if (company == null) {
            return const Center(child: Text('Empresa no encontrada.'));
          }
          final isAdmin = company.adminIds.contains(currentUserId);
          final isOwner = company.ownerId == currentUserId;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        company.name,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(company.description.isEmpty
                          ? 'Sin descripcion.'
                          : company.description),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _InfoPill(
                            icon: Icons.workspace_premium_rounded,
                            label:
                                'Plan ${company.planName.isEmpty ? 'business' : company.planName}',
                          ),
                          _InfoPill(
                            icon: Icons.verified_rounded,
                            label: 'Estado ${company.planStatus}',
                          ),
                          if (company.planSource.isNotEmpty)
                            _InfoPill(
                              icon: Icons.storefront_rounded,
                              label: company.planSource == 'google_play'
                                  ? 'Google Play'
                                  : company.planSource,
                            ),
                        ],
                      ),
                      if (company.billingStatusMessage.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(company.billingStatusMessage),
                      ],
                      if (company.subscriptionRenewsAt != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Renueva: ${DateFormat('dd/MM/yyyy · HH:mm').format(company.subscriptionRenewsAt!)}',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (widget.focusBilling) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.arrow_downward_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                          'Tu centro privado ya fue creado. El siguiente paso es activar o restaurar el plan desde el bloque de facturacion de abajo.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Suscripción empresarial',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Compra, restaura o verifica tu suscripción para mantener activo tu centro privado de comunicación y sus canales internos.',
                      ),
                      const SizedBox(height: 14),
                      _BillingStatusCard(company: company),
                      const SizedBox(height: 14),
                      ref.watch(companySubscriptionProductProvider).when(
                            data: (product) {
                              if (product == null) {
                                return const Text(
                                  'El producto empresarial todavia no aparece disponible en Play Console.',
                                );
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(product.description),
                                  const SizedBox(height: 10),
                                  _InfoPill(
                                    icon: Icons.payments_rounded,
                                    label: product.priceLabel,
                                  ),
                                ],
                              );
                            },
                            loading: () => const LinearProgressIndicator(),
                            error: (error, _) => Text(
                              error.toString().replaceFirst('Exception: ', ''),
                            ),
                          ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: isAdmin && !_billingBusy
                                ? () => _runBillingAction(
                                      () => ref
                                          .read(companyBillingServiceProvider)
                                          .purchaseCompanyPlan(
                                              company: company),
                                    )
                                : null,
                            icon: _billingBusy
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.play_circle_fill_rounded),
                            label: const Text('Comprar'),
                          ),
                          OutlinedButton.icon(
                            onPressed: isAdmin && !_billingBusy
                                ? () => _runBillingAction(
                                      () => ref
                                          .read(companyBillingServiceProvider)
                                          .restoreCompanyPlan(company: company),
                                    )
                                : null,
                            icon: const Icon(Icons.restore_rounded),
                            label: const Text('Restaurar'),
                          ),
                          OutlinedButton.icon(
                            onPressed: isAdmin && !_billingBusy
                                ? () => _runBillingAction(
                                      () => ref
                                          .read(companyBillingServiceProvider)
                                          .refreshCompanyPlan(company: company),
                                    )
                                : null,
                            icon: const Icon(Icons.sync_rounded),
                            label: const Text('Verificar'),
                          ),
                          OutlinedButton.icon(
                            onPressed: isAdmin && !_billingBusy
                                ? () async {
                                    final messenger =
                                        ScaffoldMessenger.of(context);
                                    try {
                                      await ref
                                          .read(companyBillingServiceProvider)
                                          .openSubscriptionManagement();
                                    } catch (error) {
                                      if (!mounted) return;
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            error.toString().replaceFirst(
                                                'Exception: ', ''),
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                : null,
                            icon: const Icon(Icons.open_in_new_rounded),
                            label: const Text('Administrar en Play'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isAdmin && !_working ? _addMembers : null,
                      icon: const Icon(Icons.person_add_alt_rounded),
                      label: const Text('Agregar integrantes'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isAdmin && !_working ? _createChannel : null,
                      icon: const Icon(Icons.campaign_rounded),
                      label: const Text('Crear canal'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () =>
                    context.push('/companies/${company.id}/profile'),
                icon: const Icon(Icons.badge_outlined),
                label: const Text('Editar mi informacion en empresa'),
              ),
              const SizedBox(height: 20),
              Text(
                        'Integrantes',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 12),
              AsyncValueWidget(
                value: ref.watch(companyMemberContactsProvider(company.id)),
                data: (members) {
                  return Column(
                    children: members.map((member) {
                      final memberIsOwner = member.user.uid == company.ownerId;
                      final memberIsAdmin = company.adminIds.contains(member.user.uid);
                      return _CompanyMemberTile(
                        contact: member,
                        isOwner: memberIsOwner,
                        isAdmin: memberIsAdmin,
                        canToggleAdmin:
                            isOwner && member.user.uid != company.ownerId,
                        canRemove: isAdmin && member.user.uid != company.ownerId,
                        onToggleAdmin: !isOwner || member.user.uid == company.ownerId
                            ? null
                            : () => ref.read(companiesRepositoryProvider).setAdmin(
                                  companyId: company.id,
                                  userId: member.user.uid,
                                  enabled: !memberIsAdmin,
                                ),
                        onRemove: !isAdmin || member.user.uid == company.ownerId
                            ? null
                            : () => ref.read(companiesRepositoryProvider).removeMember(
                                  companyId: company.id,
                                  userId: member.user.uid,
                                ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _BillingStatusCard extends StatelessWidget {
  const _BillingStatusCard({
    required this.company,
  });

  final Company company;

  @override
  Widget build(BuildContext context) {
    final meta = _statusMeta(company.planStatus);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: meta.color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(meta.icon, color: meta.color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Estado actual: ${meta.label}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(meta.description),
          if (company.billingStatusMessage.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(company.billingStatusMessage),
          ],
          if (company.subscriptionRenewsAt != null) ...[
            const SizedBox(height: 10),
            Text(
              'Renueva el ${DateFormat('dd/MM/yyyy · HH:mm').format(company.subscriptionRenewsAt!)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  ({String label, String description, IconData icon, Color color}) _statusMeta(
    String status,
  ) {
    switch (status) {
      case 'demo':
        return (
          label: 'Demo',
          description:
              'Modo de pruebas internas. Úsalo solo para validar el flujo empresarial antes de publicar.',
          icon: Icons.science_rounded,
          color: Colors.deepPurpleAccent,
        );
      case 'trial':
        return (
          label: 'Trial',
          description:
              'La empresa fue creada, pero todavía falta activar o restaurar la suscripción en Google Play.',
          icon: Icons.hourglass_top_rounded,
          color: Colors.orange,
        );
      case 'active':
        return (
          label: 'Activa',
          description:
              'La suscripción empresarial está vigente y las funciones premium están habilitadas.',
          icon: Icons.verified_rounded,
          color: Colors.green,
        );
      case 'expired':
        return (
          label: 'Expirada',
          description:
              'La suscripción venció. Debes comprar o restaurar el plan para recuperar el acceso empresarial.',
          icon: Icons.error_outline_rounded,
          color: Colors.redAccent,
        );
      default:
        return (
          label: status.isEmpty ? 'Sin estado' : status,
          description:
              'Verifica el estado en Google Play para mantener tu empresa habilitada.',
          icon: Icons.info_outline_rounded,
          color: Colors.blueAccent,
        );
    }
  }
}

class _CompanyMemberTile extends StatelessWidget {
  const _CompanyMemberTile({
    required this.contact,
    required this.isOwner,
    required this.isAdmin,
    required this.canToggleAdmin,
    required this.canRemove,
    this.onToggleAdmin,
    this.onRemove,
  });

  final CompanyMemberContact contact;
  final bool isOwner;
  final bool isAdmin;
  final bool canToggleAdmin;
  final bool canRemove;
  final VoidCallback? onToggleAdmin;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final adminLabel = isOwner
        ? 'Creador'
        : isAdmin
            ? 'Administrador'
            : 'Integrante';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: UserAvatar(
          photoUrl: contact.user.photoUrl,
          name: contact.displayName,
        ),
        title: Text(contact.displayName),
        subtitle: Text(
          '${contact.subtitle} · $adminLabel',
        ),
        trailing: (canToggleAdmin || canRemove)
            ? PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'admin') onToggleAdmin?.call();
                  if (value == 'remove') onRemove?.call();
                },
                itemBuilder: (context) => [
                  if (canToggleAdmin)
                    PopupMenuItem(
                      value: 'admin',
                      child: Text(
                        isAdmin
                            ? 'Quitar cargo de administrador'
                            : 'Asignar cargo de administrador',
                      ),
                    ),
                  if (canRemove)
                    const PopupMenuItem(
                      value: 'remove',
                      child: Text('Eliminar del centro privado'),
                    ),
                ],
              )
            : null,
      ),
    );
  }
}
