import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/database/app_database.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../../recurring_transaction/presentation/pages/account_reconciliation_page.dart';
import '../../../settings/presentation/pages/master_data_page.dart';
import '../../../transaction/domain/usecases/transaction_crud_usecases.dart';
import '../../../transaction/presentation/pages/transaction_pages.dart';

class OfflineAdvancedPage extends StatelessWidget {
  const OfflineAdvancedPage({super.key});

  Future<_OfflineReadiness> _loadReadiness() async {
    final database = getIt<AppDatabase>();
    final accounts =
        await (database.select(database.accounts)..where(
              (row) =>
                  row.householdId.equals(AppContext.householdId) &
                  row.isArchived.equals(false),
            ))
            .get();
    final transactions = await getIt<GetTransactions>()(AppContext.householdId);
    return _OfflineReadiness(
      hasAccount: accounts.isNotEmpty,
      hasTransaction: transactions.isNotEmpty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final database = getIt<AppDatabase>();
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.offlineAdvanced,
      child: Scaffold(
        appBar: AppBar(title: const Text('Alat offline lanjutan')),
        body: FutureBuilder<_OfflineReadiness>(
          future: _loadReadiness(),
          builder: (context, snapshot) {
            final readiness = snapshot.data;
            final ready = readiness?.isReady == true;
            return ListView(
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
                    subtitle: const Text(
                      'Database FFM berjalan di perangkat ini.',
                    ),
                    trailing: const Icon(Icons.check_circle_outline),
                    onTap: () => _showMessage(
                      context,
                      'Database lokal aktif untuk household ${database.households.hashCode}. Data tetap tersimpan di perangkat.',
                    ),
                  ),
                ),
                if (readiness != null && !ready) ...[
                  const SizedBox(height: 12),
                  AppCard(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Belum perlu rekonsiliasi',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          readiness.hasAccount
                              ? 'Tambahkan transaksi dulu supaya saldo catatan bisa dibandingkan dengan saldo nyata.'
                              : 'Buat rekening di Data Utama lalu catat transaksi pertama. Setelah itu saldo bisa diperiksa.',
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => readiness.hasAccount
                                  ? const TransactionListPage()
                                  : const MasterDataPage(),
                            ),
                          ),
                          icon: Icon(
                            readiness.hasAccount
                                ? Icons.receipt_long_outlined
                                : Icons.tune_outlined,
                          ),
                          label: Text(
                            readiness.hasAccount
                                ? 'Buka Transaksi'
                                : 'Buka Data Utama',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                AppCard(
                  child: ListTile(
                    enabled: ready,
                    leading: Icon(
                      Icons.account_balance_wallet_outlined,
                      color: ready
                          ? null
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    title: const Text('Rekonsiliasi saldo'),
                    subtitle: Text(
                      ready
                          ? 'Bandingkan saldo catatan dengan saldo nyata. Selisihnya dicatat sebagai transaksi penyesuaian.'
                          : 'Aktif setelah ada rekening dan minimal satu transaksi.',
                    ),
                    trailing: Icon(
                      ready ? Icons.chevron_right : Icons.lock_outline,
                    ),
                    onTap: ready
                        ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AccountReconciliationPage(),
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _OfflineReadiness {
  const _OfflineReadiness({
    required this.hasAccount,
    required this.hasTransaction,
  });

  final bool hasAccount;
  final bool hasTransaction;

  bool get isReady => hasAccount && hasTransaction;
}
