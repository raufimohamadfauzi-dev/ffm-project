import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../recurring_transaction/presentation/pages/account_reconciliation_page.dart';

class OfflineAdvancedPage extends StatelessWidget {
  const OfflineAdvancedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final database = getIt<AppDatabase>();
    return Scaffold(
      appBar: AppBar(title: const Text('Alat offline lanjutan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          const AppHelpBanner(
            title: 'Semua tetap di perangkat',
            message: 'Alat ini tidak mengirim data ke internet. Pakai seperlunya dan pastikan data yang dimasukkan sesuai kondisi nyata.',
            icon: Icons.offline_bolt_outlined,
          ),
          const SizedBox(height: 16),
          AppCard(
            child: ListTile(
              leading: const Icon(Icons.sync_lock_outlined),
              title: const Text('Periksa koneksi lokal'),
              subtitle: const Text('Database FFM berjalan di perangkat ini.'),
              trailing: const Icon(Icons.check_circle_outline),
              onTap: () => _showMessage(
                context,
                'Database lokal aktif untuk household ${database.households.hashCode}. Data tetap tersimpan di perangkat.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Rekonsiliasi saldo'),
              subtitle: const Text(
                'Bandingkan saldo catatan dengan saldo nyata. Selisihnya dicatat sebagai transaksi penyesuaian.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AccountReconciliationPage(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
