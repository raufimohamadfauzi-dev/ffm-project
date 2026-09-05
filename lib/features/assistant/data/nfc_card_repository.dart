import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../../core/database/app_context.dart';
import '../../../core/database/app_database.dart';
import 'nfc_bridge.dart';
import 'payment_draft_repository.dart';
import 'payment_notification_parser.dart';

/// Entitas akun kartu e-Money yang pernah di-scan oleh pengguna.
class NfcCardAccount {
  const NfcCardAccount({
    required this.cardId,
    required this.cardType,
    required this.lastKnownBalance,
    required this.lastScannedAt,
    this.issuer,
    this.accountId,
  });

  final String cardId;
  final String cardType;
  final double lastKnownBalance;
  final DateTime lastScannedAt;
  final String? issuer;
  final String? accountId;

  /// Nama tampilan kartu (mengutamakan alias kustom pengguna, misal "Flazz Avanza Ayah").
  String get displayName => (issuer != null && issuer!.trim().isNotEmpty)
      ? issuer!.trim()
      : cardType;

  Map<String, dynamic> toJson() => {
        'cardId': cardId,
        'cardType': cardType,
        'lastKnownBalance': lastKnownBalance,
        'lastScannedAt': lastScannedAt.toIso8601String(),
        'issuer': issuer,
        'accountId': accountId,
      };

  factory NfcCardAccount.fromJson(Map<String, dynamic> json) => NfcCardAccount(
        cardId: json['cardId'] as String,
        cardType: json['cardType'] as String? ?? 'emoney_generic',
        lastKnownBalance: (json['lastKnownBalance'] as num).toDouble(),
        lastScannedAt: DateTime.parse(json['lastScannedAt'] as String),
        issuer: json['issuer'] as String?,
        accountId: json['accountId'] as String?,
      );

  NfcCardAccount copyWith({
    double? lastKnownBalance,
    DateTime? lastScannedAt,
    String? issuer,
    String? accountId,
  }) {
    return NfcCardAccount(
      cardId: cardId,
      cardType: cardType,
      lastKnownBalance: lastKnownBalance ?? this.lastKnownBalance,
      lastScannedAt: lastScannedAt ?? this.lastScannedAt,
      issuer: issuer ?? this.issuer,
      accountId: accountId ?? this.accountId,
    );
  }
}

/// Hasil analisis adaptasi selisih saldo e-Money.
class NfcAdaptationResult {
  const NfcAdaptationResult({
    required this.cardAccount,
    required this.previousBalance,
    required this.newBalance,
    required this.difference,
    required this.isBaseline,
    required this.balanceAvailable,
    this.draft,
    this.historyDrafts = const <PaymentDraft>[],
  });

  final NfcCardAccount cardAccount;
  final double? previousBalance;
  final double newBalance;

  /// Selisih saldo:
  /// - Positif (`> 0`): Pengeluaran / Debit
  /// - Negatif (`< 0`): Top-Up / Kredit
  /// - Nol (`== 0`): Tidak ada perubahan saldo
  final double difference;

  /// True jika kartu baru pertama kali di-scan (baseline).
  final bool isBaseline;
  final bool balanceAvailable;

  /// Draft transaksi yang dihasilkan (jika ada perubahan saldo).
  final PaymentDraft? draft;

  /// Rincian draft riwayat transaksi individu yang diekstrak langsung dari chip kartu.
  final List<PaymentDraft> historyDrafts;
}

/// Repositori untuk mengelola catatan saldo kartu e-Money
/// dan menjalankan engine adaptasi selisih saldo.
class NfcCardRepository {
  NfcCardRepository(
    this._draftRepository, {
    AppDatabase? database,
    String householdId = AppContext.householdId,
    DateTime Function()? clock,
  })  : _database = database, // ignore: prefer_initializing_formals
        _householdId = householdId, // ignore: prefer_initializing_formals
        _clock = clock ?? DateTime.now;

  final PaymentDraftRepository _draftRepository;
  final AppDatabase? _database;
  final String _householdId;
  final DateTime Function() _clock;

  final List<NfcCardAccount> _testCards = <NfcCardAccount>[];

  /// Memproses hasil scan NFC dan menghitung selisih saldo otomatis.
  Future<NfcAdaptationResult> processCardScan(NfcCardScanResult scan) async {
    final now = _clock();
    if (_database case final AppDatabase database) {
      return _processDatabaseScan(database, scan, now);
    }
    final cards = _testCards;
    final existingIdx = cards.indexWhere((c) => c.cardId == scan.cardId);

    if (existingIdx < 0) {
      // 1. Kartu Baru (Baseline Pertama Kali)
      final newAccount = NfcCardAccount(
        cardId: scan.cardId,
        cardType: scan.cardType,
        lastKnownBalance: scan.balance,
        lastScannedAt: now,
      );
      cards.add(newAccount);

      return NfcAdaptationResult(
        cardAccount: newAccount,
        previousBalance: null,
        newBalance: scan.balance,
        difference: 0.0,
        isBaseline: true,
        balanceAvailable: scan.balanceAvailable,
        draft: null,
      );
    }

    // 2. Kartu Sudah Ada — Hitung Adaptasi Selisih Saldo
    final oldAccount = cards[existingIdx];
    final oldBalance = oldAccount.lastKnownBalance;
    final newBalance = scan.balance;

    // Periode baru dimulai dari baseline scan pertama pada bulan tersebut.
    // Perubahan saldo bulan lalu tidak boleh ikut menjadi draft bulan ini.
    final isNewMonth = oldAccount.lastScannedAt.year != now.year ||
        oldAccount.lastScannedAt.month != now.month;
    if (isNewMonth) {
      final updatedAccount = oldAccount.copyWith(
        lastKnownBalance: newBalance,
        lastScannedAt: now,
      );
      cards[existingIdx] = updatedAccount;
      return NfcAdaptationResult(
        cardAccount: updatedAccount,
        previousBalance: oldBalance,
        newBalance: newBalance,
        difference: 0.0,
        isBaseline: true,
        balanceAvailable: scan.balanceAvailable,
        draft: null,
      );
    }
    final diff = oldBalance - newBalance;

    PaymentDraft? draft;

    if (scan.balanceAvailable && diff > 0) {
      // Pengeluaran / Debit (misal: Tol, Parkir, Minimarket)
      final newDraft = PaymentDraft(
        id: 'nfc_${now.millisecondsSinceEpoch}',
        sourceApp: 'nfc_${scan.cardType}',
        rawTitle: 'NFC ${scan.cardTypeLabel}',
        rawBody: 'Pengeluaran e-Money sebesar ${scan.formattedBalance}',
        amount: diff,
        merchantName: 'Pengeluaran ${scan.cardTypeLabel}',
        mutationType: PaymentMutationType.debit,
        createdAt: now,
        suggestedCategory: 'Transportasi',
      );
      draft = await _draftRepository.addIfNotDuplicate(newDraft);
    } else if (scan.balanceAvailable && diff < 0) {
      // Top-Up / Kredit (Isi Ulang)
      final newDraft = PaymentDraft(
        id: 'nfc_${now.millisecondsSinceEpoch}',
        sourceApp: 'nfc_${scan.cardType}',
        rawTitle: 'NFC ${scan.cardTypeLabel}',
        rawBody: 'Isi ulang e-Money sebesar ${scan.formattedBalance}',
        amount: diff.abs(),
        merchantName: 'Isi Ulang ${scan.cardTypeLabel}',
        mutationType: PaymentMutationType.credit,
        createdAt: now,
        suggestedCategory: 'Isi Ulang / Transfer',
      );
      draft = await _draftRepository.addIfNotDuplicate(newDraft);
    }

    // Perbarui saldo dan waktu pemindaian terbaru
    final updatedAccount = oldAccount.copyWith(
      lastKnownBalance: newBalance,
      lastScannedAt: now,
    );
    cards[existingIdx] = updatedAccount;

    return NfcAdaptationResult(
      cardAccount: updatedAccount,
      previousBalance: oldBalance,
      newBalance: newBalance,
      difference: diff,
      isBaseline: false,
      balanceAvailable: scan.balanceAvailable,
      draft: draft,
    );
  }

  /// Mengubah nama alias kustom kartu e-Money (contoh: "Flazz Avanza Ayah")
  /// dan otomatis memperbarui nama rekening terkait di Data Utama.
  Future<bool> updateCardAlias(String cardIdOrHash, String newAlias) async {
    final database = _database;
    if (database == null) return false;
    final cleanAlias = newAlias.trim();
    if (cleanAlias.isEmpty) return false;

    final cardHash = cardIdOrHash.length >= 64
        ? cardIdOrHash
        : sha256.convert(utf8.encode(cardIdOrHash)).toString();

    final row = await (database.select(database.nfcCardAccounts)
          ..where((r) =>
              r.householdId.equals(_householdId) &
              (r.cardUidHash.equals(cardHash) |
                  r.cardUidHash.equals(cardIdOrHash) |
                  r.id.equals(cardIdOrHash))))
        .getSingleOrNull();
    if (row == null) return false;

    await database.transaction(() async {
      await (database.update(database.nfcCardAccounts)
            ..where((r) => r.id.equals(row.id)))
          .write(NfcCardAccountsCompanion(issuer: Value(cleanAlias)));

      await (database.update(database.accounts)
            ..where((a) => a.id.equals(row.accountId)))
          .write(AccountsCompanion(name: Value(cleanAlias)));
    });
    return true;
  }

  /// Mengambil semua daftar kartu e-Money yang pernah di-scan.
  Future<List<NfcCardAccount>> getCardAccounts() async {
    if (_database case final AppDatabase database) {
      final rows = await (database.select(database.nfcCardAccounts)
            ..where((row) => row.householdId.equals(_householdId)))
          .get();
      return rows
          .map(
            (row) => NfcCardAccount(
              cardId: row.cardUidHash,
              cardType: row.cardType,
              lastKnownBalance: (row.lastKnownBalance ?? 0).toDouble(),
              lastScannedAt: row.lastScannedAt ?? row.createdAt,
              issuer: row.issuer,
              accountId: row.accountId,
            ),
          )
          .toList(growable: false);
    }
    return List.unmodifiable(_testCards);
  }

  Future<NfcAdaptationResult> _processDatabaseScan(
    AppDatabase database,
    NfcCardScanResult scan,
    DateTime now,
  ) async {
    final cardHash = sha256.convert(utf8.encode(scan.cardId)).toString();
    final previous = await (database.select(database.nfcCardAccounts)
          ..where(
            (row) =>
                row.householdId.equals(_householdId) &
                row.cardUidHash.equals(cardHash),
          ))
        .getSingleOrNull();

    final card = NfcCardAccount(
      cardId: cardHash,
      cardType: scan.cardType,
      lastKnownBalance: scan.balance,
      lastScannedAt: now,
      issuer: previous?.issuer,
      accountId: previous?.accountId,
    );

    // Proses riwayat log transaksi chip APDU jika tersedia
    final historyDrafts = <PaymentDraft>[];
    if (scan.history.isNotEmpty) {
      for (final item in scan.history) {
        if (item.amount > 0) {
          final recordSig = item.rawHex != null && item.rawHex!.isNotEmpty
              ? sha256.convert(utf8.encode(item.rawHex!)).toString().substring(0, 12)
              : 'rec${item.recordIndex}_${item.amount.toInt()}';
          final draftId = 'nfc_hist_${cardHash.substring(0, 8)}_$recordSig';
          final hDraft = await _draftRepository.addIfNotDuplicate(
            PaymentDraft(
              id: draftId,
              sourceApp: 'nfc_${scan.cardType}',
              rawTitle: 'NFC ${card.displayName}',
              rawBody: 'Transaksi Tol/Parkir chip #${item.recordIndex}',
              amount: item.amount,
              merchantName: 'Tol / Parkir (${card.displayName})',
              mutationType: PaymentMutationType.debit,
              createdAt: now.subtract(Duration(minutes: item.recordIndex * 15)),
              suggestedCategory: 'Transportasi',
            ),
          );
          if (hDraft != null) {
            historyDrafts.add(hDraft);
          }
        }
      }
    }

    final oldBalance = previous?.lastKnownBalance?.toDouble();
    final isNewMonth = previous == null ||
        previous.lastScannedAt == null ||
        previous.lastScannedAt!.year != now.year ||
        previous.lastScannedAt!.month != now.month ||
        !scan.balanceAvailable ||
        !previous.balanceAvailable ||
        oldBalance == null;
    if (isNewMonth) {
      await _persistDatabaseScan(scan, now, previous?.issuer);
      return NfcAdaptationResult(
        cardAccount: card,
        previousBalance: oldBalance,
        newBalance: scan.balance,
        difference: 0,
        isBaseline: true,
        balanceAvailable: scan.balanceAvailable,
        historyDrafts: historyDrafts,
      );
    }
    final difference = oldBalance - scan.balance;
    final draft = await _createDraft(scan, difference, now, card.displayName);
    await _persistDatabaseScan(scan, now, previous.issuer);
    return NfcAdaptationResult(
      cardAccount: card,
      previousBalance: oldBalance,
      newBalance: scan.balance,
      difference: difference,
      isBaseline: false,
      balanceAvailable: true,
      draft: draft,
      historyDrafts: historyDrafts,
    );
  }

  Future<PaymentDraft?> _createDraft(
    NfcCardScanResult scan,
    double difference,
    DateTime now, [
    String? cardDisplayName,
  ]) {
    if (!scan.balanceAvailable || difference == 0) return Future.value(null);
    final isDebit = difference > 0;
    final displayName = cardDisplayName ?? scan.cardTypeLabel;
    return _draftRepository.addIfNotDuplicate(
      PaymentDraft(
        id: 'nfc_${now.microsecondsSinceEpoch}',
        sourceApp: 'nfc_${scan.cardType}',
        rawTitle: 'NFC $displayName',
        rawBody: '${isDebit ? 'Pengeluaran' : 'Isi ulang'} e-Money sebesar ${scan.formattedBalance}',
        amount: difference.abs(),
        merchantName: '${isDebit ? 'Pengeluaran' : 'Isi Ulang'} $displayName',
        mutationType: isDebit
            ? PaymentMutationType.debit
            : PaymentMutationType.credit,
        createdAt: now,
        suggestedCategory: isDebit ? 'Transportasi' : 'Isi Ulang / Transfer',
      ),
    );
  }

  Future<void> _persistDatabaseScan(
    NfcCardScanResult scan,
    DateTime scannedAt, [
    String? existingCustomIssuer,
  ]) async {
    final database = _database;
    if (database == null) return;

    final cardHash = sha256.convert(utf8.encode(scan.cardId)).toString();
    final cardId = 'nfc-card-${cardHash.substring(0, 24)}';
    final accountId = 'nfc-account-${cardHash.substring(0, 24)}';

    // Periksa apakah nama akun sudah pernah diubah kustom oleh user
    final existingAccount = await (database.select(database.accounts)
          ..where((a) => a.id.equals(accountId)))
        .getSingleOrNull();

    final accountName = existingCustomIssuer ??
        existingAccount?.name ??
        (scan.cardType == 'emoney_generic' ? 'Kartu NFC' : scan.cardTypeLabel);
    final accountType = scan.cardType.contains('bank') ? 'bank' : 'ewallet';

    await database.transaction(() async {
      await database.into(database.accounts).insertOnConflictUpdate(
        AccountsCompanion.insert(
          id: accountId,
          householdId: _householdId,
          name: accountName,
          type: accountType,
          openingBalance: const Value(0),
          isActive: const Value(true),
          isArchived: const Value(false),
          createdAt: scannedAt,
        ),
      );
      await database.into(database.nfcCardAccounts).insertOnConflictUpdate(
        NfcCardAccountsCompanion.insert(
          id: cardId,
          householdId: _householdId,
          accountId: accountId,
          cardUidHash: cardHash,
          issuer: Value(accountName),
          cardType: scan.cardType,
          lastKnownBalance: Value(
            scan.balanceAvailable ? scan.balance.round() : null,
          ),
          balanceAvailable: Value(scan.balanceAvailable),
          lastScannedAt: Value(scannedAt),
          createdAt: scannedAt,
        ),
      );
      await database.into(database.nfcScanSnapshots).insertOnConflictUpdate(
        NfcScanSnapshotsCompanion.insert(
          id: '$cardId-${scannedAt.microsecondsSinceEpoch}',
          householdId: _householdId,
          nfcCardAccountId: cardId,
          balance: Value(scan.balanceAvailable ? scan.balance.round() : null),
          balanceAvailable: Value(scan.balanceAvailable),
          periodKey: '${scannedAt.year}-${scannedAt.month.toString().padLeft(2, '0')}',
          scannedAt: scannedAt,
        ),
      );
    });
  }
}
