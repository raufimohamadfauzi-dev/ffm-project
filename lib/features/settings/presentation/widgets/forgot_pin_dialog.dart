import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _privacyChannel = MethodChannel('ffm/privacy');

// Global flag untuk mencegah rapid tap di seluruh app
bool _isOpeningForgotPinDialog = false;

// Debounce timer: mencegah trigger dialog berulang dalam 500ms
Timer? _debounceTimer;

Future<bool> openFfmAppSettings() async {
  try {
    await _privacyChannel.invokeMethod<void>('openAppSettings');
    return true;
  } on PlatformException {
    return false;
  }
}

/// Lupa PIN tidak pernah mereset PIN sambil mempertahankan data, karena itu
/// akan menjadi pintu bypass. Pengguna hanya diarahkan ke reset data Android.
Future<void> showForgotPinDialog(BuildContext context) async {
  // Debounce: abaikan jika baru saja dipanggil dalam 500ms
  if (_debounceTimer?.isActive ?? false) return;

  // Cek jika dialog sedang dibuka untuk mencegah rapid tap
  if (_isOpeningForgotPinDialog) return;

  // Cek jika context masih valid
  if (!context.mounted) return;

  _debounceTimer = Timer(const Duration(milliseconds: 500), () {});
  _isOpeningForgotPinDialog = true;

  try {
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
              // Gunakan dialogContext untuk theme, bukan parent context
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Buka setelan aplikasi'),
          ),
        ],
      ),
    );

    if (openSettings != true) return;

    if (!await openFfmAppSettings()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Setelan aplikasi belum bisa dibuka. Buka dari Setelan Android, ya.',
          ),
        ),
      );
    }
  } finally {
    _isOpeningForgotPinDialog = false;
  }
}
