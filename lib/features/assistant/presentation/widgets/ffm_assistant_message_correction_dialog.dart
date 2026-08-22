import 'package:flutter/material.dart';

class FfmAssistantMessageCorrection {
  const FfmAssistantMessageCorrection({
    required this.correctedText,
    required this.rememberLocally,
  });

  final String correctedText;
  final bool rememberLocally;
}

/// Koreksi bahasa yang dipakai ulang oleh Asisten tanpa meminta pengguna
/// menulis jawaban chatbot atau mengajari data finansial.
class FfmAssistantMessageCorrectionDialog extends StatefulWidget {
  const FfmAssistantMessageCorrectionDialog({
    super.key,
    required this.originalMessage,
  });

  final String originalMessage;

  @override
  State<FfmAssistantMessageCorrectionDialog> createState() =>
      _FfmAssistantMessageCorrectionDialogState();
}

class _FfmAssistantMessageCorrectionDialogState
    extends State<FfmAssistantMessageCorrectionDialog> {
  late final TextEditingController _controller;
  var _rememberLocally = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.originalMessage);
  }

  bool get _canRemember {
    final value = _controller.text.trim();
    return value.isNotEmpty &&
        value.length <= 140 &&
        !RegExp(r'\d').hasMatch(value) &&
        !RegExp(
          r'\b(pin|password|kata sandi)\b',
          caseSensitive: false,
        ).hasMatch(value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canRemember = _canRemember;
    return AlertDialog(
      title: const Text('Benarkan pesan atau typo'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tulis ulang versi yang kamu maksud. Asisten akan memproses ulang kalimat ini, bukan menyimpan data apa pun.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              minLines: 2,
              maxLines: 5,
              autofocus: true,
              onChanged: (_) {
                if (_rememberLocally && !_canRemember) {
                  setState(() => _rememberLocally = false);
                } else {
                  setState(() {});
                }
              },
              decoration: const InputDecoration(
                labelText: 'Versi yang sebenarnya kamu maksud',
                hintText: 'Contoh: fungsi draft buat apa',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _rememberLocally,
              onChanged: canRemember
                  ? (value) => setState(() => _rememberLocally = value)
                  : null,
              title: const Text('Ingat koreksi bahasa ini di HP'),
              subtitle: Text(
                canRemember
                    ? 'Opsional. Hanya untuk kalimat singkat tanpa angka atau data rahasia.'
                    : 'Tidak bisa diingat karena kalimat berisi angka, PIN, atau terlalu panjang.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: () {
            final corrected = _controller.text.trim();
            if (corrected.isEmpty) return;
            Navigator.of(context).pop(
              FfmAssistantMessageCorrection(
                correctedText: corrected,
                rememberLocally: _rememberLocally && canRemember,
              ),
            );
          },
          icon: const Icon(Icons.auto_fix_high_outlined),
          label: const Text('Proses ulang'),
        ),
      ],
    );
  }
}
