import 'dart:convert';

import 'package:drift/drift.dart' hide Column;

import '../../../core/database/app_context.dart';
import '../../../core/database/app_database.dart';
import '../../transaction/domain/usecases/transaction_crud_usecases.dart';

class JsonStudioOptions {
  const JsonStudioOptions({
    this.includeFinance = true,
    this.includeActivities = true,
    this.includeMetadata = true,
    this.includeFamilyProfile = true,
    this.includeNotes = true,
    this.anonymizeIdentity = false,
    this.anonymizeAmounts = false,
    this.from,
    this.to,
    this.reportStyle = 'pembelajaran keluarga',
  });

  final bool includeFinance;
  final bool includeActivities;
  final bool includeMetadata;
  final bool includeFamilyProfile;
  final bool includeNotes;
  final bool anonymizeIdentity;
  final bool anonymizeAmounts;
  final DateTime? from;
  final DateTime? to;
  final String reportStyle;
}

class JsonStudioBundle {
  const JsonStudioBundle({
    required this.json,
    required this.prompt,
    required this.periodLabel,
    required this.moduleCounts,
  });

  final String json;
  final String prompt;
  final String periodLabel;
  final Map<String, int> moduleCounts;
}

class JsonExportStudioService {
  const JsonExportStudioService(this.database);

  final AppDatabase database;

  Future<JsonStudioBundle> build(JsonStudioOptions options) async {
    final root = <String, Object?>{
      'formatVersion': 'ffm-export-studio-v1',
      'jenisBerkas': 'data_untuk_laporan_ai',
      'isBackup': false,
      'canRestore': false,
      'householdId': options.anonymizeIdentity
          ? 'household-anonim'
          : AppContext.householdId,
      'dibuatPada': DateTime.now().toIso8601String(),
      'periode': {
        'mulai': options.from?.toIso8601String(),
        'selesai': options.to?.toIso8601String(),
        'label': _periodLabel(options.from, options.to),
      },
      'pilihanLaporan': {
        'gaya': options.reportStyle,
        'catatanDisertakan': options.includeNotes,
        'identitasDisamarkan': options.anonymizeIdentity,
        'nominalDisamarkan': options.anonymizeAmounts,
      },
    };
    final counts = <String, int>{};

    if (options.includeFamilyProfile) {
      root['profilKeluarga'] = await _familyProfile(options);
      counts['profilKeluarga'] = 1;
    }
    if (options.includeFinance) {
      final finance = await _finance(options);
      root['keuangan'] = finance;
      counts.addAll({
        for (final entry in finance.entries)
          entry.key: entry.value is List ? (entry.value as List).length : 1,
      });
    }
    if (options.includeActivities) {
      final activities = await _activities(options);
      root['aktivitasDanJurnal'] = activities;
      counts.addAll({
        for (final entry in activities.entries)
          entry.key: entry.value is List ? (entry.value as List).length : 1,
      });
    }
    if (options.includeMetadata) {
      final metadata = await _metadata(options);
      root['dataUtama'] = metadata;
      counts['dataUtama'] = metadata.length;
    }

    root['aturanPenting'] = const [
      'Transfer antar rekening bukan pemasukan atau pengeluaran.',
      'Piutang tidak otomatis dihitung sebagai pemasukan kas.',
      'Nominal pada JSON adalah data aplikasi; narasi AI tidak boleh mengubah angka.',
      'Data ini bukan cadangan pemulihan aplikasi.',
    ];
    final json = const JsonEncoder.withIndent('  ').convert(root);
    return JsonStudioBundle(
      json: json,
      prompt: _prompt(options, counts),
      periodLabel: _periodLabel(options.from, options.to),
      moduleCounts: counts,
    );
  }

  Future<Map<String, Object?>> _familyProfile(JsonStudioOptions options) async {
    final row =
        await (database.select(database.households)
              ..where((item) => item.id.equals(AppContext.householdId)))
            .getSingleOrNull();
    if (row == null) {
      return {
        'namaRumahTangga': options.anonymizeIdentity
            ? 'Rumah Tangga'
            : 'Keluarga',
        'anggota': const <String>[],
      };
    }
    return {
      'namaRumahTangga': options.anonymizeIdentity ? 'Rumah Tangga' : row.name,
      'suami': options.anonymizeIdentity ? 'Anggota 1' : row.husbandName,
      'istri': options.anonymizeIdentity ? 'Anggota 2' : row.wifeName,
      'anggota': [
        if (row.husbandName?.trim().isNotEmpty == true)
          options.anonymizeIdentity ? 'Anggota 1' : row.husbandName,
        if (row.wifeName?.trim().isNotEmpty == true)
          options.anonymizeIdentity ? 'Anggota 2' : row.wifeName,
      ],
    };
  }

  Future<Map<String, Object?>> _finance(JsonStudioOptions options) async {
    final records = await GetTransactions(database)(AppContext.householdId);
    final transactions = records
        .where((entry) {
          final date = entry.transaction.date;
          return _inPeriod(date, options.from, options.to);
        })
        .map((entry) {
          final transaction = entry.transaction;
          final amount = options.anonymizeAmounts ? null : transaction.amount;
          return <String, Object?>{
            'id': transaction.id,
            'tanggalKejadian': transaction.date.toIso8601String(),
            'waktuInputSistem': transaction.recordedAt.toIso8601String(),
            'jenis': transaction.type == 'income' ? 'pemasukan' : 'pengeluaran',
            'nominal': amount,
            'kategoriId': transaction.categoryId,
            'rekeningId': transaction.accountId,
            'targetId': transaction.goalId,
            'sumberAtauDipakaiOleh': options.anonymizeIdentity
                ? 'Disamarkan'
                : transaction.partyName,
            'lokasi': options.anonymizeIdentity
                ? 'Disamarkan'
                : transaction.location,
            if (options.includeNotes)
              'catatan': options.anonymizeIdentity
                  ? 'Disamarkan'
                  : transaction.note,
            'rincian': entry.items
                .map(
                  (item) => {
                    'nama': options.anonymizeIdentity ? 'Item' : item.itemName,
                    'jumlah': item.qty,
                    'satuan': item.unit,
                    'harga': options.anonymizeAmounts ? null : item.price,
                    'total': options.anonymizeAmounts ? null : item.amount,
                  },
                )
                .toList(),
          };
        })
        .toList();
    final modules = <String, Object?>{'transaksi': transactions};
    for (final table in const [
      'assets',
      'liabilities',
      'receivables',
      'goals',
      'envelope_budgets',
      'transfers',
    ]) {
      modules[table] = await _rows(table, options);
    }
    return modules;
  }

  Future<Map<String, Object?>> _activities(JsonStudioOptions options) async {
    final sessions = await _rows('activity_sessions', options);
    final checkpoints = await _rows('activity_checkpoints', options);
    final entries = await _rows('activity_entries', options);
    return {'sesi': sessions, 'checkpoint': checkpoints, 'jurnal': entries};
  }

  Future<Map<String, Object?>> _metadata(JsonStudioOptions options) async {
    final result = <String, Object?>{};
    for (final table in const [
      'categories',
      'merchants',
      'tags',
      'accounts',
      'transaction_parties',
    ]) {
      result[table] = await _rows(table, options, applyPeriod: false);
    }
    return result;
  }

  Future<List<Map<String, Object?>>> _rows(
    String table,
    JsonStudioOptions options, {
    bool applyPeriod = true,
  }) async {
    if (!await _tableExists(table)) return const [];
    final tableInfo = await database
        .customSelect('PRAGMA table_info("$table")')
        .get();
    final hasHouseholdId = tableInfo.any(
      (row) => row.data['name'] == 'household_id',
    );
    final rows = await database
        .customSelect(
          hasHouseholdId
              ? 'SELECT * FROM "$table" WHERE household_id = ?'
              : 'SELECT * FROM "$table"',
          variables: hasHouseholdId
              ? [Variable.withString(AppContext.householdId)]
              : const [],
        )
        .get();
    return rows
        .map((row) {
          final result = <String, Object?>{};
          row.data.forEach((key, value) {
            if (!options.includeNotes && key.toLowerCase().contains('note'))
              return;
            if (options.anonymizeIdentity &&
                (key.toLowerCase().contains('name') ||
                    key.toLowerCase().contains('party') ||
                    key.toLowerCase().contains('participant') ||
                    key.toLowerCase().contains('place') ||
                    key.toLowerCase().contains('location'))) {
              result[key] = 'Disamarkan';
            } else if (options.anonymizeAmounts &&
                (key.toLowerCase().contains('amount') ||
                    key.toLowerCase().contains('balance') ||
                    key.toLowerCase().contains('value') ||
                    key.toLowerCase().contains('price'))) {
              result[key] = null;
            } else {
              result[key] = _jsonValue(key, value);
            }
          });
          return result;
        })
        .where((row) {
          if (!applyPeriod || (options.from == null && options.to == null)) {
            return true;
          }
          final date = _dateFromRow(row);
          return date == null || _inPeriod(date, options.from, options.to);
        })
        .toList();
  }

  Future<bool> _tableExists(String table) async {
    final rows = await database
        .customSelect(
          'SELECT name FROM sqlite_master WHERE type = ? AND name = ?',
          variables: [Variable.withString('table'), Variable.withString(table)],
        )
        .get();
    return rows.isNotEmpty;
  }

  String _prompt(JsonStudioOptions options, Map<String, int> counts) {
    final modules = counts.keys.join(', ');
    return '''Kamu adalah analis dan penulis laporan manajemen keluarga berbahasa Indonesia.

Gunakan JSON FFM yang akan ditempel setelah instruksi ini sebagai satu-satunya sumber angka. Buat laporan dengan gaya "${options.reportStyle}" untuk periode ${_periodLabel(options.from, options.to)}.

Aturan wajib:
1. Jangan mengubah, menebak, atau mengarang nominal, tanggal, jumlah, nama kategori, atau durasi.
2. Bedakan bagian DATA ASLI, PERHITUNGAN, dan INTERPRETASI AI.
3. Transfer antar rekening bukan pemasukan atau pengeluaran.
4. Piutang tidak otomatis dianggap pemasukan kas.
5. Jika nominal disamarkan atau null, jangan menghitung nominal tersebut.
6. Jelaskan rumus persentase secara singkat dan tampilkan pembilang serta penyebut jika tersedia.
7. Gunakan bahasa Indonesia yang ramah, tidak menghakimi, dan cocok untuk pembelajaran keluarga.
8. Jangan meminta pengguna mengirim data lain yang sudah ada di JSON.

Modul yang tersedia: $modules.

Buat keluaran dalam HTML mandiri berbahasa Indonesia dengan judul, ringkasan keluarga, tabel/persentase manajemen keluarga, pembelajaran yang terlihat dari data, dan saran praktis. Jika HTML tidak diminta, gunakan Markdown yang mudah dikonversi ke PDF. Jangan menambahkan angka fiktif.''';
  }

  bool _inPeriod(DateTime date, DateTime? from, DateTime? to) {
    if (from != null && date.isBefore(from)) return false;
    if (to != null && date.isAfter(to.add(const Duration(days: 1))))
      return false;
    return true;
  }

  DateTime? _dateFromRow(Map<String, Object?> row) {
    for (final key in const [
      'date',
      'started_at',
      'occurred_at',
      'created_at',
      'updated_at',
    ]) {
      final value = row[key];
      if (value is String) {
        final date = DateTime.tryParse(value);
        if (date != null) return date;
      }
    }
    return null;
  }

  Object? _jsonValue(String key, Object? value) {
    if (value is int && _looksLikeTimestamp(key)) {
      return DateTime.fromMillisecondsSinceEpoch(
        value * 1000,
        isUtc: true,
      ).toIso8601String();
    }
    return _jsonSafe(value);
  }

  bool _looksLikeTimestamp(String key) {
    final normalized = key.toLowerCase();
    return normalized == 'date' ||
        normalized.endsWith('_at') ||
        normalized.contains('timestamp');
  }

  Object? _jsonSafe(Object? value) {
    if (value is DateTime) return value.toIso8601String();
    if (value is Uint8List) return base64Encode(value);
    if (value is Map) {
      return value.map(
        (key, value) => MapEntry(key.toString(), _jsonSafe(value)),
      );
    }
    if (value is Iterable) return value.map(_jsonSafe).toList();
    return value;
  }

  String _periodLabel(DateTime? from, DateTime? to) {
    if (from == null && to == null) return 'Semua periode';
    final start = from == null
        ? 'awal'
        : '${from.day}/${from.month}/${from.year}';
    final end = to == null ? 'sekarang' : '${to.day}/${to.month}/${to.year}';
    return '$start sampai $end';
  }
}
