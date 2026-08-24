import 'app_database.dart';

/// Ringkasan metadata satu tabel FFM. Tidak memuat isi baris atau nilai
/// finansial pengguna; hanya nama tabel, kategori, deskripsi, dan jumlah kolom.
class FfmDatabaseStructureTable {
  const FfmDatabaseStructureTable({
    required this.tableName,
    required this.label,
    required this.category,
    required this.description,
    required this.columnCount,
    required this.hasKnownDescription,
  });

  final String tableName;
  final String label;
  final String category;
  final String description;
  final int columnCount;
  final bool hasKnownDescription;
}

/// Snapshot skema yang dipakai halaman Struktur Database dan jawaban Asisten.
class FfmDatabaseStructureSnapshot {
  const FfmDatabaseStructureSnapshot({required this.tables});

  final List<FfmDatabaseStructureTable> tables;

  int get tableCount => tables.length;

  List<String> get missingDescriptions => tables
      .where((table) => !table.hasKnownDescription)
      .map((table) => table.tableName)
      .toList(growable: false);

  Map<String, int> get categoryCounts {
    final counts = <String, int>{};
    for (final table in tables) {
      counts.update(table.category, (count) => count + 1, ifAbsent: () => 1);
    }
    return counts;
  }
}

/// Membaca metadata SQLite dari [AppDatabase.allTables], yaitu daftar runtime
/// yang dihasilkan Drift. Semua perintahnya berupa PRAGMA pembacaan skema.
class FfmDatabaseStructureService {
  FfmDatabaseStructureService(this._database);

  final AppDatabase _database;

  Future<FfmDatabaseStructureSnapshot> read() async {
    final tableNames =
        _database.allTables
            .map((table) => table.actualTableName)
            .toSet()
            .toList()
          ..sort();
    final tables = <FfmDatabaseStructureTable>[];
    for (final tableName in tableNames) {
      final columns = await _database
          .customSelect('PRAGMA table_info(${_quoteIdentifier(tableName)})')
          .get();
      final definition = _definitions[tableName];
      tables.add(
        FfmDatabaseStructureTable(
          tableName: tableName,
          label: definition?.label ?? _toLabel(tableName),
          category: definition?.category ?? 'Sistem',
          description: definition?.description ?? 'Tabel sistem internal FFM.',
          columnCount: columns.length,
          hasKnownDescription: definition != null,
        ),
      );
    }
    return FfmDatabaseStructureSnapshot(tables: tables);
  }

  static String _quoteIdentifier(String identifier) {
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(identifier)) {
      throw ArgumentError.value(
        identifier,
        'identifier',
        'Nama tabel tidak aman.',
      );
    }
    return '"$identifier"';
  }

  static String _toLabel(String value) => value
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');

  static const _definitions = <String, _TableDefinition>{
    'households': _TableDefinition(
      'Profil keluarga',
      'Data utama',
      'Identitas rumah tangga lokal pemilik data FFM.',
    ),
    'categories': _TableDefinition(
      'Kategori',
      'Data utama',
      'Kategori pemasukan dan pengeluaran untuk transaksi serta anggaran.',
    ),
    'merchants': _TableDefinition(
      'Toko atau pihak',
      'Data utama',
      'Daftar toko, tempat, atau pihak terkait transaksi.',
    ),
    'tags': _TableDefinition(
      'Tag',
      'Data utama',
      'Penanda tambahan untuk menyaring dan mengelompokkan riwayat.',
    ),
    'accounts': _TableDefinition(
      'Rekening atau tunai',
      'Data utama',
      'Lokasi uang berada, seperti tunai, bank, atau dompet digital.',
    ),
    'transaction_parties': _TableDefinition(
      'Pihak transaksi',
      'Transaksi',
      'Pihak atau sumber yang terkait dengan catatan transaksi.',
    ),
    'transactions': _TableDefinition(
      'Transaksi',
      'Transaksi',
      'Catatan pemasukan, pengeluaran, penyesuaian, dan alokasi target.',
    ),
    'transaction_items': _TableDefinition(
      'Rincian transaksi',
      'Transaksi',
      'Item atau rincian yang tergabung dalam satu transaksi.',
    ),
    'transaction_tags': _TableDefinition(
      'Tag transaksi',
      'Transaksi',
      'Penghubung antara transaksi dan tag yang dipilih.',
    ),
    'attachments': _TableDefinition(
      'Lampiran',
      'Transaksi',
      'Metadata lampiran yang dikaitkan dengan transaksi.',
    ),
    'transfers': _TableDefinition(
      'Transfer',
      'Transaksi',
      'Perpindahan saldo antar rekening yang bukan arus kas.',
    ),
    'envelope_budgets': _TableDefinition(
      'Pos anggaran',
      'Anggaran',
      'Batas anggaran mingguan, bulanan, atau tidak rutin.',
    ),
    'envelope_transfers': _TableDefinition(
      'Perpindahan anggaran',
      'Anggaran',
      'Riwayat perpindahan nilai antar pos anggaran.',
    ),
    'assets': _TableDefinition(
      'Aset',
      'Kekayaan',
      'Catatan aset keluarga yang dipantau terpisah dari saldo rekening.',
    ),
    'goals': _TableDefinition(
      'Target keuangan',
      'Kekayaan',
      'Tujuan uang yang sedang dikumpulkan dan progresnya.',
    ),
    'liabilities': _TableDefinition(
      'Hutang',
      'Kewajiban',
      'Kewajiban keluarga yang masih perlu diselesaikan.',
    ),
    'receivables': _TableDefinition(
      'Piutang',
      'Kewajiban',
      'Uang yang masih perlu diterima dan belum menjadi kas.',
    ),
    'recurring_transactions': _TableDefinition(
      'Transaksi berkala',
      'Jadwal',
      'Aturan transaksi, bunga, atau biaya berkala yang dijadwalkan.',
    ),
    'recurring_transaction_runs': _TableDefinition(
      'Riwayat transaksi berkala',
      'Jadwal',
      'Riwayat eksekusi aturan transaksi berkala.',
    ),
    'reminders': _TableDefinition(
      'Pengingat',
      'Jadwal',
      'Pengingat lokal yang aktif maupun selesai.',
    ),
    'reminder_histories': _TableDefinition(
      'Riwayat pengingat',
      'Jadwal',
      'Riwayat tindakan pada pengingat, misalnya tunda atau selesai.',
    ),
    'activity_sessions': _TableDefinition(
      'Sesi aktivitas',
      'Aktivitas',
      'Aktivitas berjalan atau selesai beserta waktu mulai dan akhir.',
    ),
    'activity_checkpoints': _TableDefinition(
      'Pembaruan aktivitas',
      'Aktivitas',
      'Tahapan atau pembaruan waktu dalam satu sesi aktivitas.',
    ),
    'activity_entries': _TableDefinition(
      'Catatan aktivitas',
      'Aktivitas',
      'Riwayat aktivitas harian yang sudah dicatat.',
    ),
    'account_reconciliation_logs': _TableDefinition(
      'Riwayat rekonsiliasi',
      'Pemeriksaan saldo',
      'Riwayat pencocokan saldo nyata dengan saldo catatan.',
    ),
    'hijri_settings': _TableDefinition(
      'Pengaturan Hijriah',
      'Kalender',
      'Pengaturan tampilan kalender Hijriah lokal.',
    ),
    'hijri_month_overrides': _TableDefinition(
      'Penyesuaian bulan Hijriah',
      'Kalender',
      'Penyesuaian awal bulan Hijriah yang dipilih pengguna.',
    ),
    'hijri_correction_logs': _TableDefinition(
      'Riwayat koreksi Hijriah',
      'Kalender',
      'Riwayat perubahan pengaturan kalender Hijriah.',
    ),
    'assistant_memories': _TableDefinition(
      'Memori Asisten',
      'Asisten',
      'Jawaban atau alias yang diajarkan dan disetujui pengguna.',
    ),
    'assistant_learning_examples': _TableDefinition(
      'Contoh belajar Asisten',
      'Asisten',
      'Contoh koreksi yang disetujui untuk membantu aturan lokal.',
    ),
    'assistant_unanswered_questions': _TableDefinition(
      'Pertanyaan belum terjawab',
      'Asisten',
      'Antrian pertanyaan yang belum dipahami atau sedang ditinjau.',
    ),
    'assistant_response_feedbacks': _TableDefinition(
      'Feedback jawaban Asisten',
      'Asisten',
      'Antrean review feedback tersanitasi atas jawaban Asisten; tidak langsung menjadi knowledge.',
    ),
    'user_corrections': _TableDefinition(
      'Koreksi pengguna',
      'Personalisasi',
      'Perbandingan tebakan SLM dengan nilai final yang dikonfirmasi pengguna.',
    ),
    'user_preferences': _TableDefinition(
      'Preferensi pengguna',
      'Personalisasi',
      'Preferensi eksplisit yang ditetapkan pengguna untuk membantu orchestrator.',
    ),
    'interaction_patterns': _TableDefinition(
      'Pola interaksi',
      'Personalisasi',
      'Ringkasan deterministik pola koreksi yang sudah cukup konsisten.',
    ),
  };
}

class _TableDefinition {
  const _TableDefinition(this.label, this.category, this.description);

  final String label;
  final String category;
  final String description;
}
