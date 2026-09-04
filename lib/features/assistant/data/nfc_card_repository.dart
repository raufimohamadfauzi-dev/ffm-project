import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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
  });

  final String cardId;
  final String cardType;
  final double lastKnownBalance;
  final DateTime lastScannedAt;

  Map<String, dynamic> toJson() => {
        'cardId': cardId,
        'cardType': cardType,
        'lastKnownBalance': lastKnownBalance,
        'lastScannedAt': lastScannedAt.toIso8601String(),
      };

  factory NfcCardAccount.fromJson(Map<String, dynamic> json) => NfcCardAccount(
        cardId: json['cardId'] as String,
        cardType: json['cardType'] as String? ?? 'emoney_generic',
        lastKnownBalance: (json['lastKnownBalance'] as num).toDouble(),
        lastScannedAt: DateTime.parse(json['lastScannedAt'] as String),
      );

  NfcCardAccount copyWith({
    double? lastKnownBalance,
    DateTime? lastScannedAt,
  }) {
    return NfcCardAccount(
      cardId: cardId,
      cardType: cardType,
      lastKnownBalance: lastKnownBalance ?? this.lastKnownBalance,
      lastScannedAt: lastScannedAt ?? this.lastScannedAt,
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
    this.draft,
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

  /// Draft transaksi yang dihasilkan (jika ada perubahan saldo).
  final PaymentDraft? draft;
}

/// Repositori untuk mengelola catatan saldo kartu e-Money
/// dan menjalankan engine adaptasi selisih saldo.
class NfcCardRepository {
  NfcCardRepository(this._draftRepository);

  final PaymentDraftRepository _draftRepository;

  static const _key = 'ffm_nfc_card_accounts';

  SharedPreferences? _cachedPrefs;

  Future<SharedPreferences> _prefs() async =>
      _cachedPrefs ??= await SharedPreferences.getInstance();

  /// Memproses hasil scan NFC dan menghitung selisih saldo otomatis.
  Future<NfcAdaptationResult> processCardScan(NfcCardScanResult scan) async {
    final cards = await _loadAll();
    final existingIdx = cards.indexWhere((c) => c.cardId == scan.cardId);

    final now = DateTime.now();

    if (existingIdx < 0) {
      // 1. Kartu Baru (Baseline Pertama Kali)
      final newAccount = NfcCardAccount(
        cardId: scan.cardId,
        cardType: scan.cardType,
        lastKnownBalance: scan.balance,
        lastScannedAt: now,
      );
      cards.add(newAccount);
      await _saveAll(cards);

      return NfcAdaptationResult(
        cardAccount: newAccount,
        previousBalance: null,
        newBalance: scan.balance,
        difference: 0.0,
        isBaseline: true,
        draft: null,
      );
    }

    // 2. Kartu Sudah Ada — Hitung Adaptasi Selisih Saldo
    final oldAccount = cards[existingIdx];
    final oldBalance = oldAccount.lastKnownBalance;
    final newBalance = scan.balance;
    final diff = oldBalance - newBalance;

    PaymentDraft? draft;

    if (diff > 0) {
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
    } else if (diff < 0) {
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
    await _saveAll(cards);

    return NfcAdaptationResult(
      cardAccount: updatedAccount,
      previousBalance: oldBalance,
      newBalance: newBalance,
      difference: diff,
      isBaseline: false,
      draft: draft,
    );
  }

  /// Mengambil semua daftar kartu e-Money yang pernah di-scan.
  Future<List<NfcCardAccount>> getCardAccounts() => _loadAll();

  // ---------------------------------------------------------------------------
  // Persistensi Internal
  // ---------------------------------------------------------------------------

  Future<List<NfcCardAccount>> _loadAll() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => NfcCardAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAll(List<NfcCardAccount> cards) async {
    final prefs = await _prefs();
    await prefs.setString(
        _key, jsonEncode(cards.map((c) => c.toJson()).toList()));
  }
}
