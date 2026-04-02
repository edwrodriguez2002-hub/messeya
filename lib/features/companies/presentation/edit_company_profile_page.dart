import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/async_value_widget.dart';
import '../data/companies_repository.dart';

class EditCompanyProfilePage extends ConsumerStatefulWidget {
  const EditCompanyProfilePage({super.key, required this.companyId});

  final String companyId;

  @override
  ConsumerState<EditCompanyProfilePage> createState() =>
      _EditCompanyProfilePageState();
}

class _EditCompanyProfilePageState
    extends ConsumerState<EditCompanyProfilePage> {
  final _displayNameController = TextEditingController();
  final _roleTitleController = TextEditingController();
  final _departmentController = TextEditingController();
  final _workEmailController = TextEditingController();
  final _workPhoneController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isVisible = true;
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _roleTitleController.dispose();
    _departmentController.dispose();
    _workEmailController.dispose();
    _workPhoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(companiesRepositoryProvider).saveMyCompanyMemberProfile(
            companyId: widget.companyId,
            displayName: _displayNameController.text,
            roleTitle: _roleTitleController.text,
            department: _departmentController.text,
            workEmail: _workEmailController.text,
            workPhone: _workPhoneController.text,
            notes: _notesController.text,
            isVisible: _isVisible,
          );
      if (!mounted) return;
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/companies/${widget.companyId}/admin');
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync =
        ref.watch(myCompanyMemberProfileProvider(widget.companyId));

    return Scaffold(
      appBar: AppBar(title: const Text('Mi informacion en la empresa')),
      body: AsyncValueWidget(
        value: profileAsync,
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('No encontramos tu ficha.'));
          }

          if (!_initialized) {
            _displayNameController.text = profile.displayName;
            _roleTitleController.text = profile.roleTitle;
            _departmentController.text = profile.department;
            _workEmailController.text = profile.workEmail;
            _workPhoneController.text = profile.workPhone;
            _notesController.text = profile.notes;
            _isVisible = profile.isVisible;
            _initialized = true;
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Esta informacion se muestra solo dentro de la empresa y no cambia tu perfil general de Messeya.',
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                    labelText: 'Nombre visible en empresa'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _roleTitleController,
                decoration: const InputDecoration(labelText: 'Cargo'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _departmentController,
                decoration: const InputDecoration(labelText: 'Departamento'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _workEmailController,
                decoration:
                    const InputDecoration(labelText: 'Correo corporativo'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _workPhoneController,
                decoration:
                    const InputDecoration(labelText: 'Telefono o extension'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                maxLines: 4,
                decoration:
                    const InputDecoration(labelText: 'Notas o descripcion'),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _isVisible,
                onChanged: (value) => setState(() => _isVisible = value),
                title: const Text('Visible para miembros de la empresa'),
                subtitle: const Text(
                  'Si lo apagas, tu ficha empresarial no aparecera en la ventana de contactos.',
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_saving ? 'Guardando...' : 'Guardar informacion'),
              ),
            ],
          );
        },
      ),
    );
  }
}
