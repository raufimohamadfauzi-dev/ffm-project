/// Plugin kategori Actuator (Tangan) — Menyiapkan draf aksi dan format ekspor.
/// Tidak melakukan penulisan ke database secara langsung (wajib konfirmasi pengguna).

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/ffm_agent_harness.dart';

String _householdId() => 'local-household';


bool _hasSpecificDetails(String text) {
  return RegExp(
    r'(\d+|ribu|juta|miliar|rb|jt|k\b|rp|senilai|bayar|listrik|beli|sekolah|kantor|bca|mandiri|bri|seabank|tunai|gopay|ovo|dana\b)',
    caseSensitive: false,
  ).hasMatch(text);
}

/// Plugin Tangan: Membantu menyiapkan draf transaksi pemasukan/pengeluaran/transfer.
class FfmTransactionActuatorPlugin extends FfmAgentPlugin {
  @override
  String get name => 'transaction_actuator';
  @override
  FfmPluginCategory get category => FfmPluginCategory.actuator;
  @override
  int get priority => 7;
  @override
  List<String> get triggers => [
    'catat transaksi',
    'input transaksi',
    'bikin transaksi',
    'tambah transaksi',
    'catat pengeluaran',
    'catat pemasukan',
    'catat transfer',
    'pindahkan uang',
    'isi form transaksi',
  ];

  @override
  bool canHandle(String normalizedText) {
    if (_hasSpecificDetails(normalizedText)) return false;
    final lower = normalizedText.toLowerCase();
    return triggers.any((t) => lower.contains(t));
  }

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    return const FfmHarnessResult(
      pluginName: 'transaction_actuator',
      category: FfmPluginCategory.actuator,
      isDraft: true,
      text:
          '✍️ **Menyiapkan Draf Transaksi**\n\n'
          'Sebutkan nominal, rekening, dan kategorinya secara lengkap.\n'
          '*Contoh:* `Beli makan 25 ribu dari BCA` atau `Pemasukan gaji 5 juta ke Mandiri`.\n\n'
          'Draf akan aku tampilkan terlebih dahulu untuk kamu konfirmasi sebelum disimpan.',
    );
  }
}

/// Plugin Tangan: Membantu menyiapkan draf target tabungan baru.
class FfmGoalActuatorPlugin extends FfmAgentPlugin {
  @override
  String get name => 'goal_actuator';
  @override
  FfmPluginCategory get category => FfmPluginCategory.actuator;
  @override
  int get priority => 7;
  @override
  List<String> get triggers => [
    'buat target',
    'bikin target',
    'tambah target',
    'target baru',
    'bikin celengan',
    'buat impian',
  ];

  @override
  bool canHandle(String normalizedText) {
    if (_hasSpecificDetails(normalizedText)) return false;
    final lower = normalizedText.toLowerCase();
    return triggers.any((t) => lower.contains(t));
  }

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    return const FfmHarnessResult(
      pluginName: 'goal_actuator',
      category: FfmPluginCategory.actuator,
      isDraft: true,
      text:
          '🎯 **Menyiapkan Draf Target Tabungan**\n\n'
          'Sebutkan nama target dan nominal yang ingin kamu capai.\n'
          '*Contoh:* `Buat target Liburan Akhir Tahun 5 juta` atau `Buat target Dana Darurat 10 juta`.\n\n'
          'Draf akan disiapkan dan kamu bisa memeriksa detailnya di form.',
    );
  }
}

/// Plugin Tangan: Membantu menyiapkan draf pengingat tagihan/aktivitas.
class FfmReminderActuatorPlugin extends FfmAgentPlugin {
  @override
  String get name => 'reminder_actuator';
  @override
  FfmPluginCategory get category => FfmPluginCategory.actuator;
  @override
  int get priority => 7;
  @override
  List<String> get triggers => [
    'buat pengingat',
    'ingatkan saya',
    'set reminder',
    'jadwalkan pengingat',
    'tambah pengingat',
  ];

  @override
  bool canHandle(String normalizedText) {
    if (_hasSpecificDetails(normalizedText)) return false;
    final lower = normalizedText.toLowerCase();
    return triggers.any((t) => lower.contains(t));
  }

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    return const FfmHarnessResult(
      pluginName: 'reminder_actuator',
      category: FfmPluginCategory.actuator,
      isDraft: true,
      text:
          '⏰ **Menyiapkan Draf Pengingat**\n\n'
          'Sebutkan apa yang ingin diingatkan dan kapan jadwalnya.\n'
          '*Contoh:* `Ingatkan bayar listrik tanggal 20` atau `Buat pengingat bayar WiFi tiap awal bulan`.\n\n'
          'Notifikasi pengingat berjalan 100% lokal di perangkatmu tanpa cloud.',
    );
  }
}

/// Plugin Tangan: Membantu menyiapkan pratinjau dan ekspor laporan keuangan.
class FfmReportActuatorPlugin extends FfmAgentPlugin {
  @override
  String get name => 'report_actuator';
  @override
  FfmPluginCategory get category => FfmPluginCategory.actuator;
  @override
  int get priority => 7;
  @override
  List<String> get triggers => [
    'buat laporan',
    'ekspor laporan',
    'cetak laporan',
    'download laporan',
    'laporan pdf',
    'laporan excel',
    'rekap laporan',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    return const FfmHarnessResult(
      pluginName: 'report_actuator',
      category: FfmPluginCategory.actuator,
      isDraft: true,
      text:
          '📑 **Menyiapkan Ekspor Laporan Keuangan**\n\n'
          'Kamu bisa mencetak atau membagikan laporan keuangan dalam format **PDF** atau **HTML**.\n'
          'Buka menu **Laporan** untuk memilih rentang tanggal dan jenis laporan yang ingin diekspor.',
    );
  }
}

/// Plugin Tangan & Logika: Pembuat data dan template JSON untuk transaksi,
/// anggaran, dan backup saat diminta user di chat secara natural dari data riil.
class FfmJsonGeneratorPlugin extends FfmAgentPlugin {
  FfmJsonGeneratorPlugin([this._db]);
  final AppDatabase? _db;

  @override
  String get name => 'json_generator';
  @override
  FfmPluginCategory get category => FfmPluginCategory.actuator;
  @override
  int get priority => 8;
  @override
  List<String> get triggers => [
    'buatkan json',
    'format json',
    'contoh json transaksi',
    'template json belanja',
    'generate json',
    'buat format json',
    'ekspor json',
    'json transaksi',
  ];

  @override
  Future<FfmHarnessResult?> execute(FfmHarnessContext context) async {
    final db = _db;
    if (db != null) {
      final householdId = _householdId();
      final latestTxs = await (db.select(db.transactions)
            ..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isArchived.equals(false) &
                  row.isDeleted.equals(false),
            )
            ..orderBy([(row) => OrderingTerm.desc(row.date)])
            ..limit(5))
          .get();

      if (latestTxs.isNotEmpty) {
        final txList = latestTxs.map((t) {
          return {
            'id': t.id,
            'date': '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}-${t.date.day.toString().padLeft(2, '0')}',
            'type': t.type,
            'amount': t.amount.abs(),
            'note': t.note ?? '',
          };
        }).toList();

        final naturalJson = const JsonEncoder.withIndent('  ').convert({
          'householdId': householdId,
          'generatedAt': context.now.toIso8601String(),
          'recentTransactions': txList,
        });

        return FfmHarnessResult(
          pluginName: name,
          category: category,
          isDraft: true,
          text: '📦 **Ekspor Data JSON Transaksi Terkini**\n\n'
              'Berikut data transaksi riil dari database lokal kamu dalam format JSON:\n\n'
              '```json\n$naturalJson\n```\n\n'
              '💡 Format ini valid dan siap dipakai untuk integrasi atau arsip data.',
        );
      }
    }

    const jsonExample = '''```json
{
  "transactions": [
    {
      "date": "2026-08-25",
      "type": "expense",
      "amount": 50000,
      "account": "BCA",
      "category": "Makan & Minum",
      "note": "Makan Siang Soto Ayam"
    },
    {
      "date": "2026-08-25",
      "type": "income",
      "amount": 5000000,
      "account": "BCA",
      "category": "Gaji Bulanan",
      "note": "Gaji Bulan Ini"
    }
  ]
}
```''';

    return const FfmHarnessResult(
      pluginName: 'json_generator',
      category: FfmPluginCategory.actuator,
      isDraft: true,
      text: '📋 **Template JSON Transaksi FFM**\n\n'
          'Berikut format JSON siap pakai untuk impor data atau pencatatan batch:\n\n'
          '$jsonExample\n\n'
          'Kamu bisa menyalin format di atas dan mengisinya dengan data yang kamu inginkan.',
    );
  }
}

