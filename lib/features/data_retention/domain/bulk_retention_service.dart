import 'package:drift/drift.dart';

import '../../../core/database/app_context.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/audit_logger.dart';

/// Preview penghitungan data yang akan diarsipkan atau dihapus permanen.
class BulkRetentionPreview {
  const BulkRetentionPreview({
    required this.beforeDate,
    required this.transactions,
    required this.activitySessions,
    required this.dailyNotes,
  });

  final DateTime beforeDate;
  final int transactions;
  final int activitySessions;
  final int dailyNotes;

  int get total => transactions + activitySessions + dailyNotes;
  bool get isEmpty => total == 0;
}

/// Hasil eksekusi archive/delete massal lintas entity.
class BulkRetentionResult {
  const BulkRetentionResult({
    required this.transactions,
    required this.activitySessions,
    required this.dailyNotes,
  });

  final int transactions;
  final int activitySessions;
  final int dailyNotes;

  int get total => transactions + activitySessions + dailyNotes;
}

/// Executor + verification untuk retensi data lintas entity
/// (Transaksi, Aktivitas, Catatan Harian).
///
/// Mengikuti boundary aplikasi: model tidak pernah langsung memutasi state.
/// Archive bersifat reversible (isArchived), sedangkan penghapusan permanen
/// hanya boleh menjalankan data yang SUDAH diarsipkan, dan wajib melewati
/// backup gate (backupVerified). Setiap mutasi dicatat ke audit log lalu
/// diverifikasi dengan baca ulang database.
class BulkRetentionService {
  const BulkRetentionService(this.database);

  final AppDatabase database;

  /// Menghitung data NON-arsip sebelum [beforeDate] untuk preview archive.
  Future<BulkRetentionPreview> previewArchive(DateTime beforeDate) async {
    final transactions = await _countTransactions(beforeDate, archivedOnly: false);
    final activitySessions = await _countSessions(beforeDate, archivedOnly: false);
    final dailyNotes = await _countDailyNotes(beforeDate, archivedOnly: false);
    return BulkRetentionPreview(
      beforeDate: beforeDate,
      transactions: transactions,
      activitySessions: activitySessions,
      dailyNotes: dailyNotes,
    );
  }

  /// Menghitung data SUDAH-arsip sebelum [beforeDate] untuk preview hapus permanen.
  Future<BulkRetentionPreview> previewDelete(DateTime beforeDate) async {
    final transactions = await _countArchivedTransactions(beforeDate);
    final activitySessions = await _countSessions(beforeDate, archivedOnly: true);
    final dailyNotes = await _countDailyNotes(beforeDate, archivedOnly: true);
    return BulkRetentionPreview(
      beforeDate: beforeDate,
      transactions: transactions,
      activitySessions: activitySessions,
      dailyNotes: dailyNotes,
    );
  }

  /// Executor: arsipkan semua data NON-arsip sebelum [beforeDate].
  /// Reversible — tidak ada yang dihapus.
  Future<BulkRetentionResult> archiveBefore(DateTime beforeDate) async {
    final audit = AuditLogger(database);
    final result = await database.transaction(() async {
      final txCount = await (database.update(database.transactions)..where((
            row,
          ) =>
              row.householdId.equals(AppContext.householdId) &
              row.date.isSmallerThanValue(beforeDate) &
              row.isArchived.equals(false) &
              row.isDeleted.equals(false)))
          .write(
            const TransactionsCompanion(isArchived: Value(true)),
          );

      final sessionCount = await (database.update(database.activitySessions)
            ..where((
              row,
            ) =>
                row.householdId.equals(AppContext.householdId) &
                row.startedAt.isSmallerThanValue(beforeDate) &
                row.isArchived.equals(false)))
          .write(
            const ActivitySessionsCompanion(isArchived: Value(true)),
          );

      final noteCount = await (database.update(database.dailyNotes)..where((
            row,
          ) =>
              row.householdId.equals(AppContext.householdId) &
              row.noteDate.isSmallerThanValue(beforeDate) &
              row.isArchived.equals(false)))
          .write(
            const DailyNotesCompanion(isArchived: Value(true)),
          );

      return BulkRetentionResult(
        transactions: txCount,
        activitySessions: sessionCount,
        dailyNotes: noteCount,
      );
    });

    if (result.total == 0) {
      throw StateError('Tidak ada data sebelum tanggal tersebut untuk diarsipkan.');
    }

    await audit.record(
      action: 'bulk_archive',
      entity: 'transaksi',
      newValue: {
        'beforeDate': beforeDate.toIso8601String(),
        'count': result.transactions,
      },
    );
    await audit.record(
      action: 'bulk_archive',
      entity: 'aktivitas',
      newValue: {
        'beforeDate': beforeDate.toIso8601String(),
        'count': result.activitySessions,
      },
    );
    await audit.record(
      action: 'bulk_archive',
      entity: 'catatan_harian',
      newValue: {
        'beforeDate': beforeDate.toIso8601String(),
        'count': result.dailyNotes,
      },
    );

    await _verifyArchived(beforeDate);
    return result;
  }

  /// Executor: hapus permanen data SUDAH-arsip sebelum [beforeDate].
  /// Wajib lolos backup gate [backupVerified] lalu diverifikasi.
  Future<BulkRetentionResult> deleteBefore(
    DateTime beforeDate, {
    required bool backupVerified,
  }) async {
    if (!backupVerified) {
      throw StateError(
        'Backup/ekspor wajib dibuat dulu sebelum penghapusan massal.',
      );
    }
    final audit = AuditLogger(database);
    final result = await database.transaction(() async {
      final txCount = await (database.update(database.transactions)..where((
            row,
          ) =>
              row.householdId.equals(AppContext.householdId) &
              row.date.isSmallerThanValue(beforeDate) &
              row.isArchived.equals(true) &
              row.isDeleted.equals(false)))
          .write(
            const TransactionsCompanion(isDeleted: Value(true)),
          );

      final sessionIds = await _archivedSessionIdsBefore(beforeDate);
      if (sessionIds.isNotEmpty) {
        await (database.delete(database.activityCheckpoints)..where(
              (row) => row.sessionId.isIn(sessionIds),
            ))
            .go();
        await (database.delete(database.activityEntries)..where(
              (row) => row.sessionId.isIn(sessionIds),
            ))
            .go();
        await (database.delete(database.activitySessions)..where(
              (row) => row.id.isIn(sessionIds),
            ))
            .go();
      }

      final noteCount = await (database.delete(database.dailyNotes)..where((
            row,
          ) =>
              row.householdId.equals(AppContext.householdId) &
              row.noteDate.isSmallerThanValue(beforeDate) &
              row.isArchived.equals(true)))
          .go();

      return BulkRetentionResult(
        transactions: txCount,
        activitySessions: sessionIds.length,
        dailyNotes: noteCount,
      );
    });

    if (result.total == 0) {
      throw StateError(
        'Tidak ada data terarsip sebelum tanggal tersebut untuk dihapus permanen.',
      );
    }

    await audit.record(
      action: 'bulk_delete_permanent',
      entity: 'transaksi',
      oldValue: {
        'beforeDate': beforeDate.toIso8601String(),
        'count': result.transactions,
      },
    );
    await audit.record(
      action: 'bulk_delete_permanent',
      entity: 'aktivitas',
      oldValue: {
        'beforeDate': beforeDate.toIso8601String(),
        'count': result.activitySessions,
      },
    );
    await audit.record(
      action: 'bulk_delete_permanent',
      entity: 'catatan_harian',
      oldValue: {
        'beforeDate': beforeDate.toIso8601String(),
        'count': result.dailyNotes,
      },
    );

    await _verifyDeleted(beforeDate);
    return result;
  }

  /// Baca ulang: tidak boleh ada data NON-arsip tersisa sebelum tanggal archive.
  Future<void> _verifyArchived(DateTime beforeDate) async {
    final remaining = await previewArchive(beforeDate);
    if (remaining.total != 0) {
      throw StateError(
        'Verifikasi gagal: masih tersisa ${remaining.total} data sebelum periode arsip.',
      );
    }
  }

  /// Baca ulang: tidak boleh ada data arsip tersisa sebelum tanggal hapus permanen.
  Future<void> _verifyDeleted(DateTime beforeDate) async {
    final remaining = await previewDelete(beforeDate);
    if (remaining.total != 0) {
      throw StateError(
        'Verifikasi gagal: masih tersisa ${remaining.total} data terarsip.',
      );
    }
  }

  Future<int> _countTransactions(
    DateTime beforeDate, {
    required bool archivedOnly,
  }) async {
    final query = database.selectOnly(database.transactions)
      ..addColumns([database.transactions.id.count()])
      ..where(
        database.transactions.householdId.equals(AppContext.householdId) &
        database.transactions.date.isSmallerThanValue(beforeDate) &
        database.transactions.isDeleted.equals(false) &
        database.transactions.isArchived.equals(archivedOnly),
      );
    final row = await query.getSingle();
    return row.read(database.transactions.id.count()) ?? 0;
  }

  Future<int> _countArchivedTransactions(DateTime beforeDate) async {
    final query = database.selectOnly(database.transactions)
      ..addColumns([database.transactions.id.count()])
      ..where(
        database.transactions.householdId.equals(AppContext.householdId) &
        database.transactions.date.isSmallerThanValue(beforeDate) &
        database.transactions.isDeleted.equals(false) &
        database.transactions.isArchived.equals(true),
      );
    final row = await query.getSingle();
    return row.read(database.transactions.id.count()) ?? 0;
  }

  Future<int> _countSessions(
    DateTime beforeDate, {
    required bool archivedOnly,
  }) async {
    final query = database.selectOnly(database.activitySessions)
      ..addColumns([database.activitySessions.id.count()])
      ..where(
        database.activitySessions.householdId.equals(AppContext.householdId) &
        database.activitySessions.startedAt.isSmallerThanValue(beforeDate) &
        database.activitySessions.isArchived.equals(archivedOnly),
      );
    final row = await query.getSingle();
    return row.read(database.activitySessions.id.count()) ?? 0;
  }

  Future<int> _countDailyNotes(
    DateTime beforeDate, {
    required bool archivedOnly,
  }) async {
    final query = database.selectOnly(database.dailyNotes)
      ..addColumns([database.dailyNotes.id.count()])
      ..where(
        database.dailyNotes.householdId.equals(AppContext.householdId) &
        database.dailyNotes.noteDate.isSmallerThanValue(beforeDate) &
        database.dailyNotes.isArchived.equals(archivedOnly),
      );
    final row = await query.getSingle();
    return row.read(database.dailyNotes.id.count()) ?? 0;
  }

  /// Semua sesi arsip sebelum [beforeDate] beserta turunannya (parentSessionId)
  /// agar cascade penghapusan ikut menyapu checkpoint dan entry tertaut.
  Future<Set<String>> _archivedSessionIdsBefore(DateTime beforeDate) async {
    final rows = await (database.select(database.activitySessions)
          ..where(
            (row) =>
                row.householdId.equals(AppContext.householdId) &
                row.isArchived.equals(true) &
                row.startedAt.isSmallerThanValue(beforeDate),
          ))
        .get();
    final byParent = <String, List<String>>{};
    for (final row in rows) {
      final parent = row.parentSessionId;
      if (parent != null) {
        byParent.putIfAbsent(parent, () => []).add(row.id);
      }
    }
    final ids = rows.map((r) => r.id).toSet();
    final pending = ids.toList();
    while (pending.isNotEmpty) {
      final parentId = pending.removeLast();
      for (final childId in byParent[parentId] ?? const <String>[]) {
        if (ids.add(childId)) pending.add(childId);
      }
    }
    return ids;
  }
}