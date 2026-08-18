import 'package:flutter/material.dart';

import '../../../../shared/widgets/app_components.dart';

class DatabaseStructurePage extends StatelessWidget {
  const DatabaseStructurePage({super.key});

  static const _tables = <(String, String)>[
    ('Households', 'Profil rumah tangga lokal'),
    ('Categories', 'Kategori pemasukan dan pengeluaran'),
    ('Merchants', 'Toko atau tempat transaksi'),
    ('Tags', 'Penanda untuk penyaringan riwayat'),
    ('Accounts', 'Tempat uang berada: tunai, bank, atau e-wallet'),
    ('Transactions', 'Catatan uang masuk dan uang keluar'),
    ('TransactionItems', 'Rincian item di dalam transaksi'),
    ('Transfers', 'Perpindahan saldo antar rekening'),
    ('EnvelopeBudgets', 'Pos anggaran berbasis kategori'),
    ('Assets', 'Aset keluarga'),
    ('Goals', 'Target keuangan'),
    ('Liabilities', 'Hutang keluarga'),
    ('Receivables', 'Piutang keluarga'),
    ('RecurringTransactions', 'Transaksi berkala'),
    ('HijriSettings', 'Pengaturan kalender Hijriah'),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Struktur database')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            const AppHelpBanner(
              title: 'Database lokal FFM',
              message: 'Daftar ini hanya menjelaskan struktur penyimpanan. Data Anda tidak dikirim atau dibagikan dari halaman ini.',
              icon: Icons.storage_outlined,
            ),
            const SizedBox(height: 16),
            Text('${_tables.length} kelompok tabel aktif', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._tables.map(
              (table) => AppCard(
                child: ListTile(
                  leading: const Icon(Icons.table_chart_outlined),
                  title: Text(table.$1),
                  subtitle: Text(table.$2),
                ),
              ),
            ),
          ],
        ),
      );
}
