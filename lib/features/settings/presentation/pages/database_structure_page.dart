import 'package:flutter/material.dart';

import '../../../../core/database/ffm_database_structure_service.dart';
import '../../../../core/di/injection.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';

class DatabaseStructurePage extends StatefulWidget {
  const DatabaseStructurePage({super.key});

  @override
  State<DatabaseStructurePage> createState() => _DatabaseStructurePageState();
}

class _DatabaseStructurePageState extends State<DatabaseStructurePage> {
  late final FfmDatabaseStructureService _service;
  late Future<FfmDatabaseStructureSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _service = FfmDatabaseStructureService(getIt());
    _snapshot = _service.read();
  }

  void _reload() => setState(() => _snapshot = _service.read());

  @override
  Widget build(BuildContext context) {
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.databaseStructure,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Struktur database'),
          actions: [
            IconButton(
              tooltip: 'Muat ulang struktur',
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<FfmDatabaseStructureSnapshot>(
          future: _snapshot,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AppEmptyState(
                    icon: Icons.error_outline,
                    title: 'Struktur belum bisa dibaca',
                    message: 'Coba muat ulang. Data keuanganmu tidak diubah.',
                    action: FilledButton(
                      onPressed: _reload,
                      child: const Text('Muat ulang'),
                    ),
                  ),
                ],
              );
            }
            final structure = snapshot.data!;
            final grouped = <String, List<FfmDatabaseStructureTable>>{};
            for (final table in structure.tables) {
              grouped.putIfAbsent(table.category, () => []).add(table);
            }
            final categories = grouped.keys.toList()..sort();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                const AppHelpBanner(
                  title: 'Metadata database lokal',
                  message: 'Halaman ini membaca daftar tabel dan kolom dari skema FFM di perangkat. Tidak ada isi transaksi, saldo, nama rekening, atau data keluarga yang ditampilkan maupun dikirim.',
                  icon: Icons.storage_outlined,
                ),
                const SizedBox(height: 16),
                AppCard(
                  child: Row(
                    children: [
                      const Icon(Icons.table_chart_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${structure.tableCount} tabel aktif dalam ${categories.length} kelompok',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                for (final category in categories) ...[
                  AppSectionHeader(
                    title: '$category · ${grouped[category]!.length} tabel',
                  ),
                  const SizedBox(height: 8),
                  for (final table in grouped[category]!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        child: ListTile(
                          leading: const Icon(Icons.table_rows_outlined),
                          title: Text(table.label),
                          subtitle: Text(
                            '${table.description}\n${table.tableName} · ${table.columnCount} kolom',
                          ),
                          isThreeLine: true,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
