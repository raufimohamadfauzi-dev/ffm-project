import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../../shared/widgets/app_components.dart';

class PinSecurityPage extends StatefulWidget {
  const PinSecurityPage({super.key});

  @override
  State<PinSecurityPage> createState() => _PinSecurityPageState();
}

class _PinSecurityPageState extends State<PinSecurityPage> {
  static const _storage = FlutterSecureStorage();
  static const _pinKey = 'ffm_pin';
  final _pinController = TextEditingController();
  var _enabled = false;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pin = await _storage.read(key: _pinKey);
    if (!mounted) return;
    setState(() {
      _enabled = pin != null && pin.isNotEmpty;
      _pinController.text = pin ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    final pin = _pinController.text.trim();
    if (pin.isNotEmpty && pin.length < 4) {
      _showMessage('PIN minimal 4 angka.');
      return;
    }
    if (pin.isEmpty) {
      await _storage.delete(key: _pinKey);
    } else {
      await _storage.write(key: _pinKey, value: pin);
    }
    if (!mounted) return;
    setState(() => _enabled = pin.isNotEmpty);
    _showMessage(pin.isEmpty ? 'PIN dimatikan.' : 'PIN tersimpan di perangkat.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('PIN aplikasi')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          AppHelpBanner(
            title: _enabled ? 'PIN sedang aktif' : 'PIN belum aktif',
            message: 'PIN ini hanya angka dan disimpan di perangkat. Jangan pakai PIN yang sama dengan PIN penting lainnya.',
            icon: _enabled ? Icons.lock_outline : Icons.lock_open_outlined,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pinController,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 12,
            decoration: const InputDecoration(labelText: 'PIN', hintText: 'Minimal 4 angka'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('Simpan PIN')),
          if (_enabled) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: () { _pinController.clear(); _save(); }, child: const Text('Matikan PIN')),
          ],
        ],
      ),
    );
  }
}
