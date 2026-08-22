import 'package:flutter/material.dart';

import '../../../../core/diagnostics/app_diagnostics_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/security/app_pin_service.dart';
import '../../../../shared/widgets/app_components.dart';
import '../widgets/app_pin_entry_panel.dart';

enum _PinFlow {
  idle,
  create,
  confirmCreate,
  verifyCurrentForChange,
  createReplacement,
  confirmReplacement,
  verifyCurrentForDisable,
}

/// UI keamanan FFM: PIN hanya masuk ke keypad khusus dan tidak pernah ke chat.
class PinSecurityPage extends StatefulWidget {
  const PinSecurityPage({super.key, this.pinService, this.diagnostics});

  final AppPinService? pinService;
  final AppDiagnosticsService? diagnostics;

  @override
  State<PinSecurityPage> createState() => _PinSecurityPageState();
}

class _PinSecurityPageState extends State<PinSecurityPage> {
  late final AppPinService _pinService =
      widget.pinService ?? getIt<AppPinService>();
  late final AppDiagnosticsService _diagnostics =
      widget.diagnostics ?? getIt<AppDiagnosticsService>();
  var _enabled = false;
  var _loading = true;
  var _flow = _PinFlow.idle;
  var _existingPinLength = AppPinService.defaultPinLength;
  String? _currentPin;
  String? _nextPin;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final existingPinLength = await _pinService.configuredPinLength();
      if (!mounted) return;
      setState(() {
        _enabled = existingPinLength != null;
        _existingPinLength =
            existingPinLength ?? AppPinService.defaultPinLength;
        _loading = false;
      });
    } catch (error, stackTrace) {
      await _diagnostics.recordException(
        code: 'PIN_STORAGE_READ_FAILED',
        feature: 'Kunci aplikasi',
        error: error,
        stackTrace: stackTrace,
        impact: 'Status PIN belum bisa dibaca. Coba buka lagi.',
      );
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('PIN belum bisa dicek. Coba buka lagi, ya.');
    }
  }

  void _start(_PinFlow flow) => setState(() {
    _flow = flow;
    _currentPin = null;
    _nextPin = null;
  });

  void _cancelFlow() => setState(() {
    _flow = _PinFlow.idle;
    _currentPin = null;
    _nextPin = null;
  });

  Future<String?> _handlePin(String pin) async {
    switch (_flow) {
      case _PinFlow.create:
        _nextPin = pin;
        if (mounted) setState(() => _flow = _PinFlow.confirmCreate);
        return null;
      case _PinFlow.confirmCreate:
        if (pin != _nextPin)
          return 'PIN baru belum sama. Coba ulangi dari awal, ya.';
        final accepted = await _confirm(
          title: 'Aktifkan PIN?',
          message: 'PIN akan dipakai untuk membuka FFM saat aplikasi dikunci.',
          label: 'Aktifkan PIN',
        );
        if (!accepted)
          return 'PIN belum diaktifkan karena kamu membatalkan konfirmasi.';
        return _saveNewPin(pin, isReplacement: false);
      case _PinFlow.verifyCurrentForChange:
        final verification = await _verifyCurrentPin(pin);
        if (verification != null) return verification;
        _currentPin = pin;
        if (mounted) setState(() => _flow = _PinFlow.createReplacement);
        return null;
      case _PinFlow.createReplacement:
        _nextPin = pin;
        if (mounted) setState(() => _flow = _PinFlow.confirmReplacement);
        return null;
      case _PinFlow.confirmReplacement:
        if (pin != _nextPin)
          return 'PIN baru belum sama. Coba ulangi dari awal, ya.';
        final accepted = await _confirm(
          title: 'Ganti PIN?',
          message: 'PIN lama akan berhenti dipakai setelah kamu setuju.',
          label: 'Simpan PIN baru',
        );
        if (!accepted)
          return 'PIN belum diganti karena kamu membatalkan konfirmasi.';
        return _saveNewPin(pin, isReplacement: true);
      case _PinFlow.verifyCurrentForDisable:
        final verification = await _verifyCurrentPin(pin);
        if (verification != null) return verification;
        final accepted = await _confirm(
          title: 'Matikan PIN?',
          message:
              'Setelah dimatikan, FFM bisa dibuka tanpa PIN di perangkat ini.',
          label: 'Matikan PIN',
          isDestructive: true,
        );
        if (!accepted)
          return 'PIN tetap aktif karena kamu membatalkan konfirmasi.';
        return _disablePin(pin);
      case _PinFlow.idle:
        return 'Pilih tindakan PIN dulu, ya.';
    }
  }

  Future<String?> _verifyCurrentPin(String pin) async {
    try {
      final outcome = await _pinService.verifyPin(pin);
      return switch (outcome) {
        FfmAppPinOperation.success => null,
        FfmAppPinOperation.incorrectPin =>
          'PIN-nya belum cocok. Coba lagi, ya.',
        FfmAppPinOperation.invalidPin =>
          'PIN harus berisi $_existingPinLength angka.',
        FfmAppPinOperation.inactive =>
          'PIN belum aktif atau perlu dibuat ulang.',
      };
    } catch (error, stackTrace) {
      await _recordPinFailure('PIN_VERIFY_FAILED', error, stackTrace);
      return 'PIN belum bisa diverifikasi. Coba lagi sebentar, ya.';
    }
  }

  Future<String?> _saveNewPin(String pin, {required bool isReplacement}) async {
    try {
      final outcome = isReplacement
          ? await _pinService.changePin(
              currentPin: _currentPin ?? '',
              nextPin: pin,
            )
          : await _pinService.createPin(pin);
      if (outcome != FfmAppPinOperation.success) {
        return switch (outcome) {
          FfmAppPinOperation.incorrectPin =>
            'PIN lama belum cocok. Tidak ada perubahan.',
          FfmAppPinOperation.invalidPin => 'PIN baru harus berisi 6 angka.',
          FfmAppPinOperation.inactive =>
            'PIN lama belum bisa dipakai. Tidak ada perubahan.',
          FfmAppPinOperation.success => null,
        };
      }
      if (!mounted) return null;
      setState(() {
        _enabled = true;
        _flow = _PinFlow.idle;
        _currentPin = null;
        _nextPin = null;
      });
      _showMessage(
        isReplacement ? 'PIN FFM sudah diganti.' : 'PIN FFM sudah aktif.',
      );
      return null;
    } catch (error, stackTrace) {
      await _recordPinFailure('PIN_STORAGE_WRITE_FAILED', error, stackTrace);
      return 'PIN belum tersimpan. Tidak ada perubahan pada PIN lama.';
    }
  }

  Future<String?> _disablePin(String pin) async {
    try {
      final outcome = await _pinService.disablePin(pin);
      if (outcome != FfmAppPinOperation.success) {
        return outcome == FfmAppPinOperation.incorrectPin
            ? 'PIN-nya belum cocok. PIN tetap aktif.'
            : 'PIN belum bisa dimatikan. Coba lagi, ya.';
      }
      if (!mounted) return null;
      setState(() {
        _enabled = false;
        _flow = _PinFlow.idle;
        _currentPin = null;
        _nextPin = null;
      });
      _showMessage('PIN FFM sudah dimatikan.');
      return null;
    } catch (error, stackTrace) {
      await _recordPinFailure('PIN_STORAGE_DELETE_FAILED', error, stackTrace);
      return 'PIN belum bisa dimatikan. Coba lagi, ya.';
    }
  }

  Future<void> _recordPinFailure(
    String code,
    Object error,
    StackTrace stackTrace,
  ) => _diagnostics.recordException(
    code: code,
    feature: 'Kunci aplikasi',
    error: error,
    stackTrace: stackTrace,
    impact: 'PIN tidak diubah otomatis.',
  );

  Future<bool> _confirm({
    required String title,
    required String message,
    required String label,
    bool isDestructive = false,
  }) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: isDestructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(label),
          ),
        ],
      ),
    );
    return approved ?? false;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_flow != _PinFlow.idle) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Kunci aplikasi'),
          leading: IconButton(
            tooltip: 'Batal',
            onPressed: _cancelFlow,
            icon: const Icon(Icons.close),
          ),
        ),
        body: _buildPinFlow(),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Kunci aplikasi')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          AppHelpBanner(
            title: _enabled ? 'PIN sedang aktif' : 'PIN belum aktif',
            message: _enabled
                ? 'PIN membantu menjaga akses FFM saat aplikasi dibuka kembali. PIN tidak masuk backup atau chat.'
                : 'Aktifkan PIN 6 angka supaya FFM minta verifikasi sebelum dibuka.',
            icon: _enabled ? Icons.lock_outline : Icons.lock_open_outlined,
          ),
          const SizedBox(height: 16),
          if (!_enabled)
            FilledButton.icon(
              onPressed: () => _start(_PinFlow.create),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Aktifkan PIN'),
            )
          else ...[
            FilledButton.icon(
              onPressed: () => _start(_PinFlow.verifyCurrentForChange),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Ganti PIN'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _start(_PinFlow.verifyCurrentForDisable),
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Matikan PIN'),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'Tips: jangan tulis atau ucapkan PIN di chat. Kalau kamu bilang “ganti PIN” ke Asisten, Asisten hanya membuka halaman ini.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildPinFlow() => switch (_flow) {
    _PinFlow.create => AppPinEntryPanel(
      title: 'Bikin PIN buat ngunci FFM',
      message:
          'Pilih 6 angka yang gampang kamu ingat, tapi jangan mudah ditebak.',
      icon: Icons.lock_outline,
      onCompleted: _handlePin,
      cancelLabel: 'Batal',
      onCancel: _cancelFlow,
    ),
    _PinFlow.confirmCreate => AppPinEntryPanel(
      title: 'Ulangi PIN baru',
      message: 'Ketik lagi 6 angka yang sama buat memastikan tidak salah.',
      icon: Icons.verified_user_outlined,
      onCompleted: _handlePin,
      cancelLabel: 'Batal',
      onCancel: _cancelFlow,
    ),
    _PinFlow.verifyCurrentForChange => AppPinEntryPanel(
      title: 'Masukkan PIN lama',
      message: 'Biar aman, cek PIN yang sekarang dulu sebelum diganti.',
      onCompleted: _handlePin,
      pinLength: _existingPinLength,
      cancelLabel: 'Batal',
      onCancel: _cancelFlow,
    ),
    _PinFlow.createReplacement => AppPinEntryPanel(
      title: 'Masukkan PIN baru',
      message: 'Pilih PIN baru 6 angka untuk FFM.',
      icon: Icons.edit_outlined,
      onCompleted: _handlePin,
      cancelLabel: 'Batal',
      onCancel: _cancelFlow,
    ),
    _PinFlow.confirmReplacement => AppPinEntryPanel(
      title: 'Ulangi PIN baru',
      message: 'Ketik lagi PIN baru supaya yakin sudah benar.',
      icon: Icons.verified_user_outlined,
      onCompleted: _handlePin,
      cancelLabel: 'Batal',
      onCancel: _cancelFlow,
    ),
    _PinFlow.verifyCurrentForDisable => AppPinEntryPanel(
      title: 'Masukkan PIN sekarang',
      message: 'Biar aman, PIN lama perlu cocok sebelum dimatikan.',
      icon: Icons.lock_open_outlined,
      onCompleted: _handlePin,
      pinLength: _existingPinLength,
      cancelLabel: 'Batal',
      onCancel: _cancelFlow,
    ),
    _PinFlow.idle => const SizedBox.shrink(),
  };
}
