import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../widgets/forgot_pin_dialog.dart';

class FfmStoragePage extends StatelessWidget {
  const FfmStoragePage({super.key});

  Future<void> _confirmReset(BuildContext context) async {
    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Setel ulang FFM'),
        content: const Text(
          'Semua transaksi, akun, pengaturan, PIN, dan data lokal FFM akan '
          'dihapus secara permanen. Tindakan ini tidak dapat dibatalkan. '
          'Pastikan sudah membuat cadangan jika masih diperlukan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.negative,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Setel ulang sekarang'),
          ),
        ],
      ),
    );
    if (shouldOpenSettings != true || !context.mounted) return;
    final opened = await openFfmAppSettings();
    if (!context.mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Setelan aplikasi belum bisa dibuka. Buka Setelan Android secara manual.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Penyimpanan FFM')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            color: scheme.primaryContainer.withValues(alpha: .55),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.storage_rounded),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Data lokal FFM',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Transaksi, akun, kategori, pengaturan, PIN, cadangan sementara, dan data Asisten tersimpan di perangkat ini.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Kelola data', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Untuk keamanan, penghapusan seluruh data dilakukan melalui Setelan Android.',
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Buka Setelan penyimpanan aplikasi'),
            onPressed: () async {
              final opened = await openFfmAppSettings();
              if (!context.mounted || opened) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Buka Setelan Android secara manual.'),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('Setel ulang FFM'),
            onPressed: () => _confirmReset(context),
          ),
          const SizedBox(height: 10),
          Text(
            'Di halaman Android berikutnya, pilih Penyimpanan lalu Hapus data. FFM tidak menghapus data sistem secara otomatis.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
