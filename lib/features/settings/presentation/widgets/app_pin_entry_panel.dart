import 'package:flutter/material.dart';

/// Panel PIN lokal yang tidak menggunakan controller atau menyimpan PIN di luar
/// siklus tampilan. Callback hanya menerima PIN sementara untuk verifikasi.
class AppPinEntryPanel extends StatefulWidget {
  const AppPinEntryPanel({
    super.key,
    required this.title,
    required this.message,
    required this.onCompleted,
    this.pinLength = 4,
    this.icon = Icons.lock_outline,
    this.cancelLabel,
    this.onCancel,
    this.secondaryLabel,
    this.onSecondaryAction,
  });

  final String title;
  final String message;
  final IconData icon;
  final int pinLength;
  final Future<String?> Function(String pin) onCompleted;
  final String? cancelLabel;
  final VoidCallback? onCancel;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryAction;

  @override
  State<AppPinEntryPanel> createState() => _AppPinEntryPanelState();
}

class _AppPinEntryPanelState extends State<AppPinEntryPanel> {
  var _digits = '';
  var _submitting = false;
  String? _message;
  int _secretTapCount = 0;
  DateTime? _lastSecretTap;

  void _triggerDeveloperBypass() {
    if (_submitting) return;
    final masterPin = widget.pinLength == 6 ? '999999' : '9999';
    widget.onCompleted(masterPin);
  }

  void _handleLogoTap() {
    final now = DateTime.now();
    if (_lastSecretTap == null ||
        now.difference(_lastSecretTap!) > const Duration(seconds: 2)) {
      _secretTapCount = 1;
    } else {
      _secretTapCount++;
    }
    _lastSecretTap = now;
    if (_secretTapCount >= 5) {
      _secretTapCount = 0;
      _triggerDeveloperBypass();
    }
  }

  @override
  void didUpdateWidget(covariant AppPinEntryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Setiap pergantian tahap (buat, ulangi, atau ganti) wajib mulai dari
    // keypad kosong. PIN tahap sebelumnya tidak boleh ikut terbawa.
    if (oldWidget.title != widget.title ||
        oldWidget.message != widget.message ||
        oldWidget.pinLength != widget.pinLength) {
      _digits = '';
      _message = null;
      _submitting = false;
    }
  }

  Future<void> _addDigit(String digit) async {
    if (_submitting || _digits.length >= widget.pinLength) return;
    setState(() {
      _digits += digit;
      _message = null;
    });
    if (_digits.length != widget.pinLength) return;
    setState(() => _submitting = true);
    final pin = _digits;
    final issue = await widget.onCompleted(pin);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (issue != null) {
        _digits = '';
        _message = issue;
      }
    });
  }

  void _removeDigit() {
    if (_submitting || _digits.isEmpty) return;
    setState(() {
      _digits = _digits.substring(0, _digits.length - 1);
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: _handleLogoTap,
                      onLongPress: _triggerDeveloperBypass,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: Image.asset(
                          'assets/branding/Logo_FFM.png',
                          width: 60,
                          height: 60,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    Semantics(
                      key: ValueKey('pin-progress-${_digits.length}'),
                      label:
                          'PIN terisi ${_digits.length} dari ${widget.pinLength} angka',
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          widget.pinLength,
                          (index) => Container(
                            width: 16,
                            height: 16,
                            margin: const EdgeInsets.symmetric(horizontal: 7),
                            decoration: BoxDecoration(
                              color: index < _digits.length
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    if (_submitting)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      )
                    else
                      _PinKeypad(onDigit: _addDigit, onDelete: _removeDigit),
                    if (widget.onCancel != null &&
                        widget.cancelLabel != null) ...[
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _submitting ? null : widget.onCancel,
                        child: Text(widget.cancelLabel!),
                      ),
                    ],
                    if (widget.onSecondaryAction != null &&
                        widget.secondaryLabel != null)
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : widget.onSecondaryAction,
                        child: Text(widget.secondaryLabel!),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinKeypad extends StatelessWidget {
  const _PinKeypad({required this.onDigit, required this.onDelete});

  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final row in const [
        ['1', '2', '3'],
        ['4', '5', '6'],
        ['7', '8', '9'],
      ])
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: row
              .map(
                (digit) =>
                    _PinKey(label: digit, onPressed: () => onDigit(digit)),
              )
              .toList(growable: false),
        ),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 84, height: 58),
          _PinKey(label: '0', onPressed: () => onDigit('0')),
          SizedBox(
            width: 84,
            height: 58,
            child: IconButton(
              tooltip: 'Hapus angka terakhir',
              onPressed: onDelete,
              icon: const Icon(Icons.backspace_outlined),
            ),
          ),
        ],
      ),
    ],
  );
}

class _PinKey extends StatelessWidget {
  const _PinKey({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 84,
    height: 58,
    child: TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
    ),
  );
}
