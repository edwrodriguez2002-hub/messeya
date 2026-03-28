import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../shared/models/device_pairing_session.dart';
import '../data/linked_devices_repository.dart';

class LinkDesktopScanPage extends ConsumerStatefulWidget {
  const LinkDesktopScanPage({super.key});

  @override
  ConsumerState<LinkDesktopScanPage> createState() =>
      _LinkDesktopScanPageState();
}

class _LinkDesktopScanPageState extends ConsumerState<LinkDesktopScanPage> {
  final _manualController = TextEditingController();
  bool _processing = false;

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _handleRawCode(String rawValue) async {
    if (_processing) return;
    final sessionId = _extractSessionId(rawValue);
    if (sessionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ese codigo de QR no es valido.')),
      );
      return;
    }

    setState(() => _processing = true);
    try {
      final session = await ref
          .read(linkedDevicesRepositoryProvider)
          .fetchPairingSession(sessionId);
      if (!mounted) return;
      final confirm = await _confirmPairing(session);
      if (confirm != true) return;
      await ref
          .read(linkedDevicesRepositoryProvider)
          .approvePairingSession(sessionId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Windows vinculado correctamente.')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<bool?> _confirmPairing(DevicePairingSession session) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Vincular Windows'),
          content: Text(
            'Quieres vincular el equipo "${session.deviceLabel}" a tu cuenta?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Vincular'),
            ),
          ],
        );
      },
    );
  }

  String _extractSessionId(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.startsWith('messeya-link:')) {
      return trimmed.substring('messeya-link:'.length).trim();
    }
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear QR de Windows')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                height: 320,
                width: double.infinity,
                child: MobileScanner(
                  onDetect: (capture) {
                    final code = capture.barcodes.isEmpty
                        ? null
                        : capture.barcodes.first.rawValue;
                    if (code != null) {
                      _handleRawCode(code);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _manualController,
              decoration: const InputDecoration(
                labelText: 'O pega el codigo manual',
                prefixIcon: Icon(Icons.qr_code_2_rounded),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _processing
                    ? null
                    : () => _handleRawCode(_manualController.text),
                child: Text(
                  _processing ? 'Vinculando...' : 'Vincular con ese codigo',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
