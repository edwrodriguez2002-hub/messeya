import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';
import '../data/auth_repository.dart';

class PhoneLoginPage extends ConsumerStatefulWidget {
  const PhoneLoginPage({super.key});

  @override
  ConsumerState<PhoneLoginPage> createState() => _PhoneLoginPageState();
}

class _PhoneLoginPageState extends ConsumerState<PhoneLoginPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _codeSent = false;
  String? _verificationId;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      await ref.read(authRepositoryProvider).sendPhoneCode(
            phoneNumber: _phoneController.text,
            onCodeSent: (verificationId, _) {
              setState(() {
                _verificationId = verificationId;
                _codeSent = true;
              });
            },
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Te enviamos un codigo por SMS.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyCode() async {
    if ((_verificationId ?? '').isEmpty) return;
    if (_codeController.text.trim().length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa el codigo de 6 digitos.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(authRepositoryProvider).verifySmsCode(
            verificationId: _verificationId!,
            smsCode: _codeController.text,
          );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar con telefono')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _codeSent
                              ? 'Verifica tu numero'
                              : 'Ingresa tu numero',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _codeSent
                              ? 'Escribe el codigo SMS que recibiste.'
                              : 'Usa formato internacional, por ejemplo +573001234567.',
                        ),
                        const SizedBox(height: 24),
                        AppTextField(
                          controller: _phoneController,
                          label: 'Telefono',
                          keyboardType: TextInputType.phone,
                          prefixIcon: const Icon(Icons.phone_outlined),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Ingresa tu numero.';
                            }
                            if (!value.trim().startsWith('+') ||
                                value.trim().length < 8) {
                              return 'Usa formato internacional, por ejemplo +57...';
                            }
                            return null;
                          },
                        ),
                        if (_codeSent) ...[
                          const SizedBox(height: 16),
                          AppTextField(
                            controller: _codeController,
                            label: 'Codigo SMS',
                            keyboardType: TextInputType.number,
                            prefixIcon: const Icon(Icons.password_rounded),
                          ),
                        ],
                        const SizedBox(height: 24),
                        PrimaryButton(
                          label:
                              _codeSent ? 'Verificar codigo' : 'Enviar codigo',
                          onPressed: _codeSent ? _verifyCode : _sendCode,
                          isLoading: _isLoading,
                        ),
                        if (_codeSent) ...[
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _isLoading ? null : _sendCode,
                            child: const Text('Reenviar codigo'),
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
      ),
    );
  }
}
