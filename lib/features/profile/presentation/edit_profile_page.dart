import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/async_value_widget.dart';
import '../../../shared/widgets/primary_button.dart';
import '../data/profile_repository.dart';

class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  File? _imageFile;
  bool _initialized = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1200,
    );
    if (file == null) return;
    setState(() => _imageFile = File(file.path));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            name: _nameController.text,
            bio: _bioController.text,
            imageFile: _imageFile,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentAppUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Editar perfil')),
      body: AsyncValueWidget(
        value: currentUser,
        data: (user) {
          if (user == null) {
            return const Center(child: Text('No se encontro el perfil.'));
          }

          if (!_initialized) {
            _nameController.text = user.name;
            _bioController.text = user.bio;
            _initialized = true;
          }

          ImageProvider<Object>? imageProvider;
          if (_imageFile != null) {
            imageProvider = FileImage(_imageFile!);
          } else if (user.photoUrl.isNotEmpty) {
            final isRemote = user.photoUrl.startsWith('http://') ||
                user.photoUrl.startsWith('https://');
            imageProvider = isRemote
                ? NetworkImage(user.photoUrl)
                : FileImage(File(user.photoUrl));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: CircleAvatar(
                      radius: 46,
                      backgroundImage: imageProvider,
                      child: imageProvider == null
                          ? const Icon(Icons.camera_alt_outlined)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Identificador',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            if (user.isVerified) ...[
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.verified_rounded,
                                color: Colors.blueAccent,
                                size: 18,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '@${user.username}',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tu username es unico y no se puede editar porque funciona como identificador de tu cuenta.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _nameController,
                    label: 'Nombre',
                    validator: (value) {
                      if (value == null || value.trim().length < 2) {
                        return 'Ingresa un nombre valido.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _bioController,
                    label: 'Estado',
                    maxLines: 2,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Escribe una descripcion corta.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: 'Guardar cambios',
                    onPressed: _save,
                    isLoading: _isSaving,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
