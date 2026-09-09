import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

/// Penyimpanan antrean pengiriman pesan Telegram yang durabel.
///
/// Pesan dimasukkan lewat [enqueue] dengan `INSERT OR IGNORE` sehingga
/// `deliveryId`/`dedupeKey` menjadi idempotency key lintas sesi. Pengiriman
/// memakai [claim] atomik (status pending/failed -> processing sambil
/// menambah attempt) agar dua proses tidak mengirim pesan yang sama.
/// Kegagalan permanen (retryable = false) tidak pernah diantrekan ulang.
class TelegramDeliveryRepository {
  TelegramDeliveryRepository(this._db, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const String householdId = 'local-household';

  final AppDatabase _db;
  final DateTime Function() _now;

  /// Memasukkan pesan ke antrean. Mengembalikan `true` bila baris baru
  /// dibuat, `false` bila pesan dengan id/dedupe yang sama sudah ada.
  Future<bool> enqueue({
    required String deliveryId,
    required String householdId,
    required String operation,
    required String messageText,
    String? entityId,
    String? dedupeKey,
    String? credentialFingerprint,
    DateTime? createdAt,
  }) async {
    final entityClause = entityId == null ? 'NULL' : '?';
    final dedupeClause = dedupeKey == null ? 'NULL' : '?';
    final fingerprintClause =
        credentialFingerprint == null ? 'NULL' : '?';
    final variables = <Variable<Object>>[
      Variable.withString(deliveryId),
      Variable.withString(householdId),
      Variable.withString(operation),
      Variable.withString(messageText),
    ];
    if (entityId != null) variables.add(Variable.withString(entityId));
    if (dedupeKey != null) variables.add(Variable.withString(dedupeKey));
    if (credentialFingerprint != null) {
      variables.add(Variable.withString(credentialFingerprint));
    }
    variables.add(Variable.withDateTime(createdAt ?? _now()));

    final inserted = await _db.customUpdate(
      'INSERT OR IGNORE INTO telegram_deliveries '
      '(delivery_id, household_id, operation, message_text, entity_id, '
      'dedupe_key, credential_fingerprint, status, retryable, attempt_count, '
      'max_attempts, created_at) '
      'VALUES (?, ?, ?, ?, $entityClause, $dedupeClause, '
      '$fingerprintClause, \'pending\', 1, 0, 3, ?)',
      variables: variables,
      updates: {_db.telegramDeliveries},
    );
    return inserted == 1;
  }

  /// Pesan yang layak dikirim: pending/failed, masih dapat dicoba diulang,
  /// dan sudah jatuh tempo (tanpa `nextAttemptAt` atau sudah lewat).
  Future<List<TelegramDelivery>> pendingDue({
    String householdId = TelegramDeliveryRepository.householdId,
    int limit = 10,
    DateTime? now,
  }) async {
    final boundedLimit = limit < 1
        ? 1
        : limit > 100
        ? 100
        : limit;
    final current = now ?? _now();
    return (_db.select(_db.telegramDeliveries)
          ..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.status.isIn(const ['pending', 'failed']) &
                row.retryable.equals(true) &
                (row.nextAttemptAt.isNull() |
                    row.nextAttemptAt.isSmallerThanValue(current)),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt)])
          ..limit(boundedLimit))
        .get();
  }

  /// Klaim atomik satu pesan untuk diproses. Hanya pending/failed yang
  /// retryable dan sudah jatuh tempo yang dapat diklaim; attempt ikut dihitung.
  Future<bool> claim(String deliveryId, {DateTime? now}) async {
    final current = now ?? _now();
    final changed = await _db.customUpdate(
      'UPDATE telegram_deliveries '
      'SET status = ?, attempt_count = attempt_count + 1, last_attempt_at = ? '
      "WHERE delivery_id = ? AND status IN ('pending', 'failed') "
      'AND retryable = 1 '
      'AND (next_attempt_at IS NULL OR next_attempt_at <= ?)',
      variables: [
        Variable.withString('processing'),
        Variable.withDateTime(current),
        Variable.withString(deliveryId),
        Variable.withDateTime(current),
      ],
      updates: {_db.telegramDeliveries},
    );
    return changed == 1;
  }

  /// Menandai pesan terkirim.
  Future<void> markSent(String deliveryId, {DateTime? sentAt}) async {
    await (_db.update(
      _db.telegramDeliveries,
    )..where((row) => row.deliveryId.equals(deliveryId))).write(
      TelegramDeliveriesCompanion(
        status: const Value('sent'),
        retryable: const Value(false),
        sentAt: Value(sentAt ?? _now()),
        nextAttemptAt: const Value(null),
        lastError: const Value(null),
      ),
    );
  }

  /// Menandai pesan gagal. Bila [retryable] `false` atau attempt sudah
  /// mencapai batas, pesan berhenti diantrekan ulang (status tetap failed
  /// agar dapat ditinjau, tidak dihapus).
  Future<void> markFailed(
    String deliveryId, {
    required String error,
    required bool retryable,
    DateTime? nextAttemptAt,
    int? attemptCount,
    int? maxAttempts,
    DateTime? at,
  }) async {
    final now = at ?? _now();
    final exhausted =
        !retryable ||
        (attemptCount != null &&
            maxAttempts != null &&
            attemptCount >= maxAttempts);
    await (_db.update(
      _db.telegramDeliveries,
    )..where((row) => row.deliveryId.equals(deliveryId))).write(
      TelegramDeliveriesCompanion(
        status: const Value('failed'),
        retryable: Value(!exhausted),
        lastError: Value(error),
        lastAttemptAt: Value(now),
        nextAttemptAt: Value(exhausted ? null : nextAttemptAt),
      ),
    );
  }

  /// Menandai pesan dibatalkan (kredensial berubah / integrasi nonaktif).
  /// Tidak pernah dikirim dan tidak diantrekan ulang.
  Future<void> markSkipped(
    String deliveryId, {
    String? reason,
    DateTime? at,
  }) async {
    await (_db.update(
      _db.telegramDeliveries,
    )..where((row) => row.deliveryId.equals(deliveryId))).write(
      TelegramDeliveriesCompanion(
        status: const Value('skipped'),
        retryable: const Value(false),
        lastError: Value(reason),
        lastAttemptAt: Value(at ?? _now()),
      ),
    );
  }

  Future<TelegramDelivery?> deliveryById(String deliveryId) =>
      (_db.select(_db.telegramDeliveries)
            ..where((row) => row.deliveryId.equals(deliveryId)))
          .getSingleOrNull();

  /// Riwayat pengiriman terbaru untuk ditampilkan di halaman setup.
  Future<List<TelegramDelivery>> recentDeliveries({
    String householdId = TelegramDeliveryRepository.householdId,
    int limit = 20,
  }) {
    final boundedLimit = limit < 1
        ? 1
        : limit > 100
        ? 100
        : limit;
    return (_db.select(_db.telegramDeliveries)
          ..where((row) => row.householdId.equals(householdId))
          ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
          ..limit(boundedLimit))
        .get();
  }

  /// Jumlah pesan yang masih menunggu atau gagal yang masih dapat diulang.
  Future<int> pendingCount({
    String householdId = TelegramDeliveryRepository.householdId,
  }) async {
    final rows =
        await (_db.select(_db.telegramDeliveries)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.status.isIn(const ['pending', 'failed']) &
                  row.retryable.equals(true),
            ))
            .get();
    return rows.length;
  }
}