import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/entities/utility_meter_models.dart';

class UtilityPurchaseHistory {
  const UtilityPurchaseHistory({
    required this.id,
    required this.meterId,
    required this.meterNumber,
    required this.amount,
    required this.adminFee,
    required this.purchasedAt,
    this.tokenCode,
    this.creditedKwh,
    this.transactionId,
  });

  final String id;
  final String? meterId;
  final String meterNumber;
  final String? tokenCode;
  final int amount;
  final int adminFee;
  final double? creditedKwh;
  final DateTime purchasedAt;
  final String? transactionId;
}

class ElectricityUsageSummary {
  const ElectricityUsageSummary({
    required this.purchaseCount,
    required this.totalCost,
    required this.totalCreditedKwh,
    required this.averageCostPerKwh,
  });

  final int purchaseCount;
  final int totalCost;
  final double totalCreditedKwh;
  final double? averageCostPerKwh;
}

/// Status resolusi target meteran dari sebuah draft pembelian token.
/// Deterministis: asisten harus tahu pasti target sebelum draft dibuat,
/// sehingga pembelian berikutnya tidak pernah membuat identitas meteran baru.
enum UtilityMeterTargetStatus {
  /// Meteran teridentifikasi unik (nomor/ID meter/ref nama cocok, atau satu-satunya meteran).
  resolved,

  /// Nomor meter/IDPEL belum terdaftar; akan didaftarkan saat konfirmasi.
  newMeter,

  /// Tidak ada target dan sudah ada lebih dari satu meteran -> wajib tanya balik.
  missingTarget,

  /// Belum ada meteran sama sekali -> wajib tanya nomor meter atau foto struk.
  noMeters,

  /// Referensi nama cocok dengan beberapa meteran -> wajib tanya balik.
  ambiguous,

  /// Referensi nama tidak dikenal -> wajib tanya balik (daftarkan atau perbaiki).
  unknownReference,

  /// Nomor meter/IDPEL tidak valid panjangnya.
  invalidMeterNumber,
}

/// Hasil deterministik resolusi target meteran + pesan klarifikasi siap pakai.
class UtilityMeterTargetResolution {
  const UtilityMeterTargetResolution({
    required this.status,
    this.meter,
    this.meterNumber,
    this.options = const [],
    required this.message,
    this.isResolvable = false,
  });

  UtilityMeterTargetResolution.resolved(
    UtilityMeter meter, {
    String prefix = '',
    bool auto = false,
  }) : this(
         status: UtilityMeterTargetStatus.resolved,
         meter: meter,
         meterNumber: UtilityMeterRepository.normalizeNumber(meter.meterNumber),
         message: auto
             ? 'Pembelian token dicatat untuk satu-satunya meteran: '
                   '${meter.name} (${meter.meterNumber}).'
             : '$prefix${meter.name} (${meter.meterNumber}).',
         isResolvable: true,
       );

  UtilityMeterTargetResolution.newMeter(String meterNumber)
    : this(
        status: UtilityMeterTargetStatus.newMeter,
        meterNumber: meterNumber,
        message:
            'Meteran $meterNumber belum terdaftar. Meteran baru ini akan didaftarkan setelah kamu mengonfirmasi pembelian.',
        isResolvable: true,
      );

  UtilityMeterTargetResolution.missingTarget(List<UtilityMeter> meters)
    : this(
        status: UtilityMeterTargetStatus.missingTarget,
        options: meters,
        message:
            'Pembelian token ini untuk meteran/listrik rumah yang mana?\n${UtilityMeterRepository.friendlyMeterOptions(meters)}',
      );

  UtilityMeterTargetResolution.noMeters()
    : this(
        status: UtilityMeterTargetStatus.noMeters,
        message:
            'Belum ada meteran listrik yang terdaftar di Profil Keluarga. Kirim nomor meter/IDPEL atau foto struk token agar pembelian bisa dicatat ke rumah yang tepat.',
      );

  UtilityMeterTargetResolution.ambiguous(
    String reference,
    List<UtilityMeter> matches,
  ) : this(
        status: UtilityMeterTargetStatus.ambiguous,
        options: matches,
        message:
            'Referensi "$reference" cocok dengan beberapa meteran:\n${UtilityMeterRepository.friendlyMeterOptions(matches)}\nSebutkan namanya lebih spesifik saat kamu mengetik.',
      );

  UtilityMeterTargetResolution.unknownReference(
    String reference,
    List<UtilityMeter> meters,
  ) : this(
        status: UtilityMeterTargetStatus.unknownReference,
        options: meters,
        message:
            'Meteran "$reference" belum terdaftar. Meteran yang terdaftar:\n${UtilityMeterRepository.friendlyMeterOptions(meters)}\nKirim nomor meter/IDPEL atau foto struk token.',
      );

  UtilityMeterTargetResolution.invalidMeterNumber(String meterNumber)
    : this(
        status: UtilityMeterTargetStatus.invalidMeterNumber,
        meterNumber: meterNumber,
        message:
            'Nomor meter/IDPEL "$meterNumber" tidak valid. Nomor meter harus 9-13 digit.',
      );

  /// Status resolusi.
  final UtilityMeterTargetStatus status;

  /// Meteran yang teridentifikasi (status [resolved]).
  final UtilityMeter? meter;

  /// Nomor meter/IDPEL ternormalisasi yang dipakai untuk penyimpanan.
  final String? meterNumber;

  /// Pilihan meteran yang membutuhkan keputusan user (ambiguous/missing).
  final List<UtilityMeter> options;

  /// Pesan yang aman ditampilkan ke user (klarifikasi/status).
  final String message;

  /// True bila target sudah pasti dan pembelian bisa lanjut ke penyimpanan.
  final bool isResolvable;
}

/// Penyimpanan meter dan riwayat listrik. Produksi memakai SQLite/Drift.
/// SharedPreferences hanya dibaca untuk migrasi instalasi lama dan fallback tes.
class UtilityMeterRepository {
  UtilityMeterRepository([this._database]);

  static const _keyPrefix = 'ffm_utility_meters_';
  static const _migrationPrefix = 'ffm_utility_meters_drift_migrated_';
  final AppDatabase? _database;
  SharedPreferences? _cachedPrefs;

  Future<SharedPreferences> _prefs() async =>
      _cachedPrefs ??= await SharedPreferences.getInstance();
  String _getKey(String householdId) => '$_keyPrefix$householdId';
  String _migrationKey(String householdId) => '$_migrationPrefix$householdId';
  static String normalizeNumber(String value) =>
      value.replaceAll(RegExp(r'\D'), '');

  /// Format ramah untuk satu meteran pada pesan klarifikasi asisten.
  static String friendlyMeterOption(UtilityMeter meter,
          {String prefix = '• '}) =>
      '$prefix${meter.name} (no. ${meter.meterNumber})';

  /// Format ramah untuk daftar meteran pada pesan klarifikasi asisten.
  static String friendlyMeterOptions(List<UtilityMeter> meters) =>
      meters.map(friendlyMeterOption).join('\n');

  Future<List<UtilityMeter>> getAllMeters(String householdId) async {
    final database = _database;
    if (database == null) return _readLegacyMeters(householdId);
    await _migrateLegacyMeters(householdId);
    final rows =
        await (database.select(database.electricityMeters)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.name)]))
            .get();
    return rows
        .map(
          (row) => UtilityMeter(
            id: row.id,
            householdId: row.householdId,
            name: row.name,
            meterNumber: row.meterNumber,
            customerName: row.customerName,
            tariffPower: row.tariffPower,
            location: row.location,
            notes: row.notes,
            createdAt: row.createdAt,
            lastTokenNumber: row.lastTokenNumber,
            lastPurchasedAt: row.lastPurchasedAt,
            lastAmount: row.lastAmount,
          ),
        )
        .toList(growable: false);
  }

  Future<UtilityMeter?> findMeterByNumber(
    String householdId,
    String rawNumber,
  ) async {
    final clean = normalizeNumber(rawNumber);
    if (clean.isEmpty) return null;
    return (await getAllMeters(householdId))
        .where((meter) => normalizeNumber(meter.meterNumber) == clean)
        .firstOrNull;
  }

  /// Menentukan target meteran sebuah draft pembelian token secara
  /// deterministik sebelum draft dibuat. Asisten wajib tahu pasti apakah
  /// IDPEL itu baru atau sudah ada agar pembelian berikutnya TIDAK pernah
  /// membuat identitas meteran duplikat.
  Future<UtilityMeterTargetResolution> resolveMeterTarget({
    required String householdId,
    required Map<Object?, Object?> proposal,
  }) async {
    final meters = await getAllMeters(householdId);

    final meterId = proposal['meterId']?.toString().trim();
    if (meterId != null && meterId.isNotEmpty) {
      final meter = meters.where((item) => item.id == meterId).firstOrNull;
      if (meter != null) {
        return UtilityMeterTargetResolution.resolved(meter);
      }
    }

    final meterNumber = normalizeNumber(
      proposal['meterNumber']?.toString() ?? '',
    );
    final meterReference = proposal['meterReference']?.toString().trim();
    if (meterNumber.isNotEmpty) {
      if (meterNumber.length < 9 || meterNumber.length > 13) {
        return UtilityMeterTargetResolution.invalidMeterNumber(meterNumber);
      }
      final match = await findMeterByNumber(householdId, meterNumber);
      if (match != null) return UtilityMeterTargetResolution.resolved(match);
      return UtilityMeterTargetResolution.newMeter(meterNumber);
    }

    if (meterReference != null && meterReference.isNotEmpty) {
      final reference = meterReference.toLowerCase();
      final matches = meters
          .where(
            (meter) =>
                meter.name.trim().toLowerCase() == reference ||
                meter.customerName.trim().toLowerCase() == reference ||
                normalizeNumber(meter.meterNumber) == normalizeNumber(reference),
          )
          .toList(growable: false);
      if (matches.length == 1) {
        return UtilityMeterTargetResolution.resolved(matches.single);
      }
      if (matches.length > 1) {
        return UtilityMeterTargetResolution.ambiguous(reference, matches);
      }
      return UtilityMeterTargetResolution.unknownReference(reference, meters);
    }

    if (meters.isEmpty) return UtilityMeterTargetResolution.noMeters();
    if (meters.length == 1) {
      return UtilityMeterTargetResolution.resolved(
        meters.single,
        auto: true,
      );
    }
    return UtilityMeterTargetResolution.missingTarget(meters);
  }

  /// Memeriksa anomali pembelian token sebelum/ketika disimpan. Hasil berupa
  /// warning yang aman ditampilkan user; tidak menghalangi penyimpanan yang
  /// sah, hanya memberi tahu kemungkinan dobel entri / salah struk.
  Future<List<String>> scanPurchaseAnomalies({
    required String householdId,
    required Map<Object?, Object?> proposal,
  }) async {
    final warnings = <String>[];
    final amount = (proposal['amount'] as num?)?.round();
    final token = normalizeNumber(proposal['tokenCode']?.toString() ?? '');
    final meterNumber = normalizeNumber(
      proposal['meterNumber']?.toString() ?? '',
    );
    final creditedKwh = (proposal['creditedKwh'] as num?)?.toDouble();
    final timestamp =
        DateTime.tryParse(proposal['timestamp']?.toString() ?? '') ??
        DateTime.now();

    if (amount != null && amount > 0 && creditedKwh != null && creditedKwh > 0) {
      final rate = amount / creditedKwh;
      if (rate < 300 || rate > 2000) {
        warnings.add(
          'Nilai kWh (${creditedKwh.toStringAsFixed(2)}) tidak wajar untuk '
          'nominal Rp${_formatRp(amount)} — tarif token PLN normal sekitar '
          'Rp300-Rp2.000 per kWh. Cek kembali struknya.',
        );
      }
    }

    if (token.isNotEmpty && token.length == 20) {
      final database = _database;
      if (database != null) {
        final rows = await database.customSelect(
          'SELECT purchased_at, token_code FROM utility_token_purchases '
          'WHERE household_id = ? AND token_code = ? LIMIT 1',
          variables: [Variable.withString(householdId), Variable.withString(token)],
        ).get();
        if (rows.isNotEmpty) {
          final purchasedAtValue = rows.first.data['purchased_at'];
          final String date;
          if (purchasedAtValue is DateTime) {
            date = purchasedAtValue.toIso8601String().substring(0, 10);
          } else if (purchasedAtValue is String) {
            date = DateTime.parse(purchasedAtValue).toIso8601String().substring(0, 10);
          } else {
            date = 'tanggal tidak diketahui';
          }
          warnings.add(
            'Kode token ini sudah pernah dicatat pada $date. Kemungkinan '
            'dobel entri atau struk lama — cek kembali.',
          );
        }
      }
    }

    if (meterNumber.isNotEmpty) {
      final database = _database;
      if (database != null) {
        final meter = await findMeterByNumber(householdId, meterNumber);
        final meterId = meter?.id;
        if (meterId != null && amount != null && amount > 0) {
          final startOfDay = DateTime(timestamp.year, timestamp.month, timestamp.day);
          final endOfDay = startOfDay.add(const Duration(days: 1));
          final rows = await database.customSelect(
            'SELECT COUNT(*) AS duplicate_count FROM utility_token_purchases '
            'WHERE household_id = ? AND meter_id = ? AND amount = ? '
            'AND purchased_at >= ? AND purchased_at < ?',
            variables: [
              Variable.withString(householdId),
              Variable.withString(meterId),
              Variable.withInt(amount),
              Variable.withDateTime(startOfDay),
              Variable.withDateTime(endOfDay),
            ],
          ).get();
          final countValue = rows.first.data['duplicate_count'];
          final count = countValue is int
              ? countValue
              : int.tryParse(countValue?.toString() ?? '0') ?? 0;
          if (count > 0) {
            warnings.add(
              '${meter!.name} sudah mencatat pembelian Rp${_formatRp(amount)} '
              'hari ini. Kemungkinan entri ganda — pastikan bukan pembelian ulang.',
            );
          }
        }
      }
    }

    return warnings;
  }

  static String _formatRp(int value) => value.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );

  Future<void> saveMeter(UtilityMeter meter) async {
    final clean = normalizeNumber(meter.meterNumber);
    if (clean.length < 9 || clean.length > 13) {
      throw ArgumentError.value(
        meter.meterNumber,
        'meterNumber',
        'Nomor meter/IDPEL harus 9-13 digit.',
      );
    }
    final database = _database;
    if (database == null) {
      await _saveLegacyMeter(meter);
      return;
    }
    await _migrateLegacyMeters(meter.householdId);
    await database
        .into(database.electricityMeters)
        .insertOnConflictUpdate(
          ElectricityMetersCompanion.insert(
            id: meter.id,
            householdId: meter.householdId,
            name: meter.name.trim(),
            meterNumber: clean,
            normalizedMeterNumber: clean,
            customerName: Value(meter.customerName.trim()),
            tariffPower: Value(meter.tariffPower.trim()),
            location: Value(meter.location.trim()),
            notes: Value(meter.notes.trim()),
            lastTokenNumber: Value(meter.lastTokenNumber),
            lastPurchasedAt: Value(meter.lastPurchasedAt),
            lastAmount: Value(meter.lastAmount),
            createdAt: meter.createdAt,
            updatedAt: DateTime.now(),
          ),
        );
  }

  Future<void> archiveMeter(String householdId, String meterId) async {
    final database = _database;
    if (database == null) {
      final list = await _readLegacyMeters(householdId);
      final archived = list.where((meter) => meter.id == meterId).toList();
      if (archived.isEmpty) return;
      await _writeLegacyMeters(
        householdId,
        list
            .map(
              (meter) => meter.id == meterId
                  ? meter.copyWith(
                      name: '${meter.name} (Diarsipkan)',
                    )
                  : meter,
            )
            .toList(),
      );
      return;
    }
    await (database.update(database.electricityMeters)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(meterId),
        ))
        .write(
          ElectricityMetersCompanion(
            isArchived: const Value(true),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> deleteMeter(String householdId, String meterId) async {
    final database = _database;
    if (database == null) {
      final list = await _readLegacyMeters(householdId);
      await _writeLegacyMeters(
        householdId,
        list.where((meter) => meter.id != meterId).toList(),
      );
      return;
    }
    await archiveMeter(householdId, meterId);
  }

  Future<void> updateLastToken({
    required String householdId,
    required String meterNumber,
    required String tokenCode,
    double? amount,
    DateTime? timestamp,
  }) => _updateLatest(
    householdId: householdId,
    meterNumber: meterNumber,
    tokenCode: tokenCode,
    amount: amount,
    timestamp: timestamp,
  );

  Future<void> recordPurchase({
    required String householdId,
    required String meterNumber,
    String? tokenCode,
    double? amount,
    DateTime? timestamp,
  }) => _updateLatest(
    householdId: householdId,
    meterNumber: meterNumber,
    tokenCode: tokenCode,
    amount: amount,
    timestamp: timestamp,
  );

  Future<void> _updateLatest({
    required String householdId,
    required String meterNumber,
    String? tokenCode,
    double? amount,
    DateTime? timestamp,
  }) async {
    final meter = await findMeterByNumber(householdId, meterNumber);
    if (meter == null) return;
    await saveMeter(
      meter.copyWith(
        lastTokenNumber: tokenCode ?? meter.lastTokenNumber,
        lastAmount: amount ?? meter.lastAmount,
        lastPurchasedAt: timestamp ?? DateTime.now(),
      ),
    );
  }

  /// Menyimpan sisi listrik dari transaksi terkonfirmasi. transactionId unik
  /// menjaga relasi 1:1 dan membuat retry aman dari duplikasi.
  Future<UtilityPurchaseHistory> recordLinkedPurchase({
    required String householdId,
    required String transactionId,
    required Map<Object?, Object?> proposal,
  }) async {
    final database = _database;
    if (database == null) throw StateError('Database listrik belum tersedia.');
    final amount = (proposal['amount'] as num?)?.round();
    if (amount == null || amount <= 0) {
      throw StateError('Nominal pembelian token tidak valid.');
    }
    final resolution = await resolveMeterTarget(
      householdId: householdId,
      proposal: proposal,
    );
    if (!resolution.isResolvable) {
      throw StateError(resolution.message);
    }
    final meterNumber =
        resolution.meterNumber ??
        normalizeNumber(proposal['meterNumber']?.toString() ?? '');
    if (meterNumber.length < 9 || meterNumber.length > 13) {
      throw StateError('Nomor meter/IDPEL pada draft tidak valid.');
    }
    final token = normalizeNumber(proposal['tokenCode']?.toString() ?? '');
    if (token.isNotEmpty && token.length != 20) {
      throw StateError('Kode token pada draft harus 20 digit.');
    }
    final timestamp =
        DateTime.tryParse(proposal['timestamp']?.toString() ?? '') ??
        DateTime.now();
    final creditedKwh = (proposal['creditedKwh'] as num?)?.toDouble();
    if (creditedKwh != null && creditedKwh <= 0) {
      throw StateError('Nilai kWh pada draft harus lebih dari nol.');
    }
    final adminFee = (proposal['adminFee'] as num?)?.round() ?? 0;
    final existing =
        await (database.select(database.utilityTokenPurchases)
              ..where((item) => item.transactionId.equals(transactionId)))
            .getSingleOrNull();
    if (existing != null) {
      final samePayload =
          existing.householdId == householdId &&
          normalizeNumber(existing.meterNumber) == meterNumber &&
          existing.amount == amount &&
          existing.adminFee == adminFee &&
          existing.creditedKwh == creditedKwh &&
          normalizeNumber(existing.tokenCode ?? '') == token;
      if (!samePayload) {
        throw StateError(
          'Transaksi ini sudah tertaut ke data token listrik yang berbeda.',
        );
      }
      return _purchaseFromRow(existing);
    }
    var meter = resolution.meter;
    meter ??= UtilityMeter(
      id: const Uuid().v4(),
      householdId: householdId,
      name: proposal['proposedMeterName']?.toString().trim().isNotEmpty == true
          ? proposal['proposedMeterName'].toString().trim()
          : 'Meteran PLN $meterNumber',
      meterNumber: meterNumber,
      createdAt: timestamp,
    );
    await saveMeter(
      meter.copyWith(
        lastTokenNumber: token.isEmpty ? meter.lastTokenNumber : token,
        lastAmount: amount.toDouble(),
        lastPurchasedAt: timestamp,
      ),
    );
    await database
        .into(database.utilityTokenPurchases)
        .insert(
          UtilityTokenPurchasesCompanion.insert(
            id: 'token_$transactionId',
            householdId: householdId,
            meterId: Value(meter.id),
            meterNumber: meterNumber,
            tokenCode: Value(token.isEmpty ? null : token),
            amount: amount,
            adminFee: Value(adminFee),
            creditedKwh: Value(creditedKwh),
            purchasedAt: timestamp,
            transactionId: Value(transactionId),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    final row = await (database.select(
      database.utilityTokenPurchases,
    )..where((item) => item.transactionId.equals(transactionId))).getSingle();
    return _purchaseFromRow(row);
  }

  Future<List<UtilityPurchaseHistory>> getPurchaseHistory(
    String householdId, {
    String? meterId,
    int limit = 50,
  }) async {
    final database = _database;
    if (database == null) return const [];
    final query = database.select(database.utilityTokenPurchases)
      ..where((row) => row.householdId.equals(householdId))
      ..orderBy([(row) => OrderingTerm.desc(row.purchasedAt)])
      ..limit(limit.clamp(1, 100));
    if (meterId != null) query.where((row) => row.meterId.equals(meterId));
    return (await query.get()).map(_purchaseFromRow).toList(growable: false);
  }

  Future<ElectricityUsageSummary> summarizeUsage(
    String householdId, {
    String? meterId,
  }) async {
    final rows = await getPurchaseHistory(
      householdId,
      meterId: meterId,
      limit: 100,
    );
    final totalCost = rows.fold<int>(0, (sum, row) => sum + row.amount);
    final totalKwh = rows.fold<double>(
      0,
      (sum, row) => sum + (row.creditedKwh ?? 0),
    );
    return ElectricityUsageSummary(
      purchaseCount: rows.length,
      totalCost: totalCost,
      totalCreditedKwh: totalKwh,
      averageCostPerKwh: totalKwh > 0 ? totalCost / totalKwh : null,
    );
  }

  Future<void> recordMeterReading({
    required String householdId,
    required String meterId,
    required double readingKwh,
    DateTime? recordedAt,
    String source = 'manual',
    String? note,
  }) async {
    final database = _database;
    if (database == null) {
      throw StateError('Database listrik belum tersedia.');
    }
    if (readingKwh < 0) {
      throw StateError('Pembacaan meter tidak boleh negatif.');
    }
    if (source != 'manual' && source != 'photo') {
      throw ArgumentError.value(source, 'source', 'Use manual or photo');
    }
    final meter = await (database.select(database.electricityMeters)
          ..where(
            (row) =>
                row.id.equals(meterId) &
                row.householdId.equals(householdId) &
                row.isArchived.equals(false),
          ))
        .getSingleOrNull();
    if (meter == null) {
      throw StateError('Meteran yang dipilih tidak ditemukan atau sudah diarsipkan.');
    }

    final timestamp = recordedAt ?? DateTime.now();
    final latest = await getLatestReading(householdId, meterId);
    if (latest != null &&
        timestamp.isAfter(latest.recordedAt) &&
        readingKwh < latest.readingKwh) {
      throw StateError(
        'Pembacaan meter lebih rendah dari sebelumnya '
        '(${latest.readingKwh.toStringAsFixed(2)} kWh).',
      );
    }

    await database.into(database.electricityMeterReadings).insert(
      ElectricityMeterReadingsCompanion.insert(
        id: const Uuid().v4(),
        householdId: householdId,
        meterId: meterId,
        readingKwh: readingKwh,
        recordedAt: timestamp,
        source: Value(source),
        note: Value(note),
      ),
    );
  }

  Future<List<MeterReading>> getMeterReadings(
    String householdId, {
    required String meterId,
    int limit = 30,
  }) async {
    final database = _database;
    if (database == null) return const [];
    final rows = await (database.select(database.electricityMeterReadings)
          ..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.meterId.equals(meterId),
          )
          ..orderBy([(row) => OrderingTerm.desc(row.recordedAt)])
          ..limit(limit.clamp(1, 100)))
        .get();
    return rows.map(_readingFromRow).toList(growable: false);
  }

  Future<MeterReading?> getLatestReading(
    String householdId,
    String meterId,
  ) async {
    final readings = await getMeterReadings(
      householdId,
      meterId: meterId,
      limit: 1,
    );
    return readings.isEmpty ? null : readings.first;
  }

  Future<double?> calculateActualUsage(
    String householdId, {
    required String meterId,
    required DateTime from,
    required DateTime to,
  }) async {
    if (!to.isAfter(from)) {
      throw ArgumentError.value(to, 'to', 'Must be after from');
    }
    final database = _database;
    if (database == null) return null;
    final before = await (database.select(database.electricityMeterReadings)
          ..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.meterId.equals(meterId) &
                row.recordedAt.isSmallerOrEqualValue(from),
          )
          ..orderBy([(row) => OrderingTerm.desc(row.recordedAt)])
          ..limit(1))
        .getSingleOrNull();
    final after = await (database.select(database.electricityMeterReadings)
          ..where(
            (row) =>
                row.householdId.equals(householdId) &
                row.meterId.equals(meterId) &
                row.recordedAt.isBiggerOrEqualValue(to),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.recordedAt)])
          ..limit(1))
        .getSingleOrNull();
    if (before == null || after == null) return null;
    final usage = after.readingKwh - before.readingKwh;
    return usage < 0 ? null : usage;
  }

  MeterReading _readingFromRow(ElectricityMeterReading row) => MeterReading(
    id: row.id,
    householdId: row.householdId,
    meterId: row.meterId,
    readingKwh: row.readingKwh,
    recordedAt: row.recordedAt,
    source: row.source,
    note: row.note,
  );

  Future<List<PeriodUsage>> summarizeUsageByPeriod(
    String householdId, {
    required String meterId,
    String period = 'monthly',
    int limit = 6,
    bool includeReadings = false,
  }) async {
    final database = _database;
    if (database == null) return const [];
    if (period != 'monthly' && period != 'weekly') {
      throw ArgumentError.value(period, 'period', 'Use monthly or weekly');
    }

    final safeLimit = limit.clamp(1, 24);
    final periodExpression = period == 'monthly'
      ? "CASE WHEN typeof(purchased_at) IN ('integer', 'real') "
              "THEN strftime('%Y-%m', purchased_at, 'unixepoch') "
          "ELSE strftime('%Y-%m', purchased_at) END"
      : "CASE WHEN typeof(purchased_at) IN ('integer', 'real') "
              "THEN strftime('%Y-%W', purchased_at, 'unixepoch') "
          "ELSE strftime('%Y-%W', purchased_at) END";
    final rows = await database.customSelect(
      'SELECT $periodExpression AS period, '
      "CASE WHEN typeof(MIN(purchased_at)) IN ('integer', 'real') "
      "THEN datetime(MIN(purchased_at), 'unixepoch') "
      "ELSE MIN(purchased_at) END AS first_purchase, "
      'SUM(amount) AS total_cost, '
      'COALESCE(SUM(credited_kwh), 0) AS total_kwh, '
      'COUNT(*) AS purchase_count '
      'FROM utility_token_purchases '
      'WHERE household_id = ? AND meter_id = ? '
      'GROUP BY period ORDER BY period DESC LIMIT ?',
      variables: [
        Variable.withString(householdId),
        Variable.withString(meterId),
        Variable.withInt(safeLimit),
      ],
    ).get();

    final usages = rows.map((row) {
      final firstPurchase = _periodDate(row.data['first_purchase']);
      final dateFrom = period == 'monthly'
          ? DateTime(firstPurchase.year, firstPurchase.month)
          : _startOfWeek(firstPurchase);
      final dateTo = period == 'monthly'
          ? DateTime(firstPurchase.year, firstPurchase.month + 1)
          : dateFrom.add(const Duration(days: 7));
      return PeriodUsage(
        label: period == 'monthly'
            ? _formatPeriodMonth(firstPurchase)
            : _formatPeriodWeek(firstPurchase),
        dateFrom: dateFrom,
        dateTo: dateTo,
        totalCost: _asInt(row.data['total_cost']),
        totalKwh: _asDouble(row.data['total_kwh']),
        purchaseCount: _asInt(row.data['purchase_count']),
      );
    }).toList(growable: false);
    if (!includeReadings) return usages;

    return Future.wait(
      usages.map((usage) async {
        final actualKwh = await calculateActualUsage(
          householdId,
          meterId: meterId,
          from: usage.dateFrom,
          to: usage.dateTo,
        );
        return PeriodUsage(
          label: usage.label,
          dateFrom: usage.dateFrom,
          dateTo: usage.dateTo,
          totalCost: usage.totalCost,
          totalKwh: usage.totalKwh,
          purchaseCount: usage.purchaseCount,
          actualKwh: actualKwh,
        );
      }),
    );
  }

  DateTime _periodDate(Object? value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
  }

  DateTime _startOfWeek(DateTime date) {
    final dayOffset = date.weekday - DateTime.monday;
    final start = DateTime(date.year, date.month, date.day);
    return start.subtract(Duration(days: dayOffset));
  }

  String _formatPeriodMonth(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  String _formatPeriodWeek(DateTime date) {
    final weekOfMonth = ((date.day - 1) ~/ 7) + 1;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    return 'Minggu $weekOfMonth ${months[date.month - 1]}';
  }

  int _asInt(Object? value) => value is int
      ? value
      : int.tryParse(value?.toString() ?? '') ?? 0;

  double _asDouble(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  UtilityPurchaseHistory _purchaseFromRow(UtilityTokenPurchase row) =>
      UtilityPurchaseHistory(
        id: row.id,
        meterId: row.meterId,
        meterNumber: row.meterNumber,
        tokenCode: row.tokenCode,
        amount: row.amount,
        adminFee: row.adminFee,
        creditedKwh: row.creditedKwh,
        purchasedAt: row.purchasedAt,
        transactionId: row.transactionId,
      );

  Future<List<Map<String, Object?>>> exportRaw(String householdId) async =>
      (await getAllMeters(householdId)).map((meter) => meter.toJson()).toList();

  Future<void> importRaw(
    String householdId,
    List<Map<String, Object?>> rows,
  ) async {
    for (final row in rows) {
      final meter = UtilityMeter.fromJson(row);
      if (await findMeterByNumber(householdId, meter.meterNumber) == null) {
        await saveMeter(meter);
      }
    }
  }

  Future<void> _migrateLegacyMeters(String householdId) async {
    final database = _database;
    if (database == null) return;
    final prefs = await _prefs();
    if (prefs.getBool(_migrationKey(householdId)) == true) return;
    final legacy = await _readLegacyMeters(householdId);
    for (final meter in legacy) {
      final clean = normalizeNumber(meter.meterNumber);
      if (clean.length < 9 || clean.length > 13) continue;
      await database
          .into(database.electricityMeters)
          .insert(
            ElectricityMetersCompanion.insert(
              id: meter.id,
              householdId: meter.householdId,
              name: meter.name,
              meterNumber: clean,
              normalizedMeterNumber: clean,
              customerName: Value(meter.customerName),
              tariffPower: Value(meter.tariffPower),
              location: Value(meter.location),
              notes: Value(meter.notes),
              lastTokenNumber: Value(meter.lastTokenNumber),
              lastPurchasedAt: Value(meter.lastPurchasedAt),
              lastAmount: Value(meter.lastAmount),
              createdAt: meter.createdAt,
              updatedAt: DateTime.now(),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    await prefs.setBool(_migrationKey(householdId), true);
  }

  Future<List<UtilityMeter>> _readLegacyMeters(String householdId) async {
    final raw = (await _prefs()).getString(_getKey(householdId));
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((item) => UtilityMeter.fromJson(item as Map<String, dynamic>))
          .toList();
    } on Object {
      return [];
    }
  }

  Future<void> _saveLegacyMeter(UtilityMeter meter) async {
    final list = await _readLegacyMeters(meter.householdId);
    final index = list.indexWhere(
      (item) =>
          item.id == meter.id ||
          normalizeNumber(item.meterNumber) ==
              normalizeNumber(meter.meterNumber),
    );
    if (index >= 0) {
      list[index] = meter;
    } else {
      list.insert(0, meter);
    }
    await _writeLegacyMeters(meter.householdId, list);
  }

  Future<void> _writeLegacyMeters(
    String householdId,
    List<UtilityMeter> meters,
  ) async {
    await (await _prefs()).setString(
      _getKey(householdId),
      jsonEncode(meters.map((meter) => meter.toJson()).toList()),
    );
  }
}
