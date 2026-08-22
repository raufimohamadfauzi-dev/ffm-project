import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _privacyChannel = MethodChannel('ffm/privacy');

/// Lupa PIN tidak pernah mereset PIN sambil mempertahankan data, karena itu
/// akan menjadi pintu bypass. Pengguna hanya diarahkan ke reset data Android.
Future<void> showForgotPinDialog(BuildContext context) async {
  final openSettings = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Lupa PIN?'),
      content: const Text(
        'Demi keamanan, PIN tidak bisa dihapus atau diganti tanpa PIN lama. '
        'Kalau tetap mau masuk, kamu perlu hapus data aplikasi dari Setelan Android. '
        'Semua data FFM yang belum dicadangkan akan hilang. Setelah itu, buka FFM lagi lalu impor cadangan yang kamu punya.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Buka setelan aplikasi'),
        ),
      ],
    ),
  );
  if (openSettings != true) return;
  try {
    await _privacyChannel.invokeMethod<void>('openAppSettings');
  } on PlatformException {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Setelan aplikasi belum bisa dibuka. Buka dari Setelan Android, ya.',
        ),
      ),
    );
  }
}
