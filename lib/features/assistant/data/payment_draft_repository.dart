import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'payment_notification_parser.dart';

/// Status sebuah draft transaksi yang terdeteksi dari notifikasi.
enum PaymentDraftStatus { pending, confirmed, dismissed }

/// Draft transaksi yang dihasilkan dari notifikasi bank/e-wallet.
///
/// Draft ini TIDAK langsung masuk ke database transaksi.
/// Pengguna harus mengonfirmasi secara eksplisit melalui UI (1-ketukan).
class PaymentDraft {
  PaymentDraft({
    required this.id,
    required this.sourceApp,
    required this.rawTitle,
    required this.rawBody,
    required this.amount,
    required this.merchantName,
    required this.mutationType,
    required this.createdAt,
    this.suggestedCategory,
    this.status = PaymentDraftStatus.pending,
  });

  final String id;

  /// Package ID aplikasi bank/e-wallet (misal: `com.bca`).
  final String sourceApp;

  /// Judul notifikasi asli.
  final String rawTitle;

  /// Isi notifikasi asli.
  final String rawBody;

  /// Nominal pembayaran dalam Rupiah.
  final double amount;

  /// Nama merchant / penerima yang diekstrak.
  final String merchantName;

  /// Jenis mutasi (debit / kredit).
  final PaymentMutationType mutationType;

  /// Waktu notifikasi diterima.
  final DateTime createdAt;

  /// Saran kategori otomatis berdasarkan kata kunci merchant.
  final String? suggestedCategory;

  /// Status konfirmasi draft.
  PaymentDraftStatus status;

  /// Label nama bank/e-wallet yang dapat dibaca manusia.
  String get accountLabel => PaymentNotificationParser.labelFor(sourceApp);

  /// Format nominal yang bisa dibaca (Rp 45.000).
  String get formattedAmount {
    final n = amount.toStringAsFixed(0);
    final buf = StringBuffer();
    int count = 0;
    for (int i = n.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buf.write('.');
      buf.write(n[i]);
      count++;
    }
    return 'Rp ${buf.toString().split('').reversed.join()}';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceApp': sourceApp,
    'rawTitle': rawTitle,
    'rawBody': rawBody,
    'amount': amount,
    'merchantName': merchantName,
    'mutationType': mutationType.name,
    'createdAt': createdAt.toIso8601String(),
    'suggestedCategory': suggestedCategory,
    'status': status.name,
  };

  factory PaymentDraft.fromJson(Map<String, dynamic> json) => PaymentDraft(
    id: json['id'] as String,
    sourceApp: json['sourceApp'] as String,
    rawTitle: json['rawTitle'] as String? ?? '',
    rawBody: json['rawBody'] as String? ?? '',
    amount: (json['amount'] as num).toDouble(),
    merchantName: json['merchantName'] as String? ?? '',
    mutationType: PaymentMutationType.values.firstWhere(
      (e) => e.name == json['mutationType'],
      orElse: () => PaymentMutationType.debit,
    ),
    createdAt: DateTime.parse(json['createdAt'] as String),
    suggestedCategory: json['suggestedCategory'] as String?,
    status: PaymentDraftStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => PaymentDraftStatus.pending,
    ),
  );

  PaymentDraft copyWith({PaymentDraftStatus? status}) => PaymentDraft(
    id: id,
    sourceApp: sourceApp,
    rawTitle: rawTitle,
    rawBody: rawBody,
    amount: amount,
    merchantName: merchantName,
    mutationType: mutationType,
    createdAt: createdAt,
    suggestedCategory: suggestedCategory,
    status: status ?? this.status,
  );
}

/// Repository untuk menyimpan dan mengelola daftar draft transaksi sementara.
///
/// Menggunakan SharedPreferences (lazy init) agar ringan dan tanpa schema migration.
/// Draft dikosongkan otomatis setelah lebih dari 7 hari.
class PaymentDraftRepository {
  PaymentDraftRepository();

  static const _key = 'ffm_payment_drafts';

  /// Durasi deduplication window — draft dengan nominal dan source sama
  /// dalam 5 menit dianggap duplikat.
  static const _dedupWindow = Duration(minutes: 5);

  /// Durasi draft disimpan sebelum dibersihkan otomatis.
  static const _retentionDuration = Duration(days: 7);

  SharedPreferences? _cachedPrefs;

  Future<SharedPreferences> _prefs() async =>
      _cachedPrefs ??= await SharedPreferences.getInstance();

  // ---------------------------------------------------------------------------
  // Tulis
  // ---------------------------------------------------------------------------

  /// Tambahkan draft baru jika bukan duplikat.
  /// Kembalikan draft yang ditambahkan, atau null jika duplikat.
  Future<PaymentDraft?> addIfNotDuplicate(PaymentDraft draft) async {
    final drafts = await _loadAll();

    // Periksa duplikat dalam window 5 menit
    final isDuplicate = drafts.any((d) {
      final timeDiff = draft.createdAt.difference(d.createdAt).abs();
      return d.amount == draft.amount &&
          d.sourceApp == draft.sourceApp &&
          d.status == PaymentDraftStatus.pending &&
          timeDiff <= _dedupWindow;
    });

    if (isDuplicate) return null;

    drafts.insert(0, draft); // Terbaru di depan
    await _saveAll(drafts);
    return draft;
  }

  /// Perbarui status draft (konfirmasi / abaikan).
  Future<void> updateStatus(String id, PaymentDraftStatus status) async {
    final drafts = await _loadAll();
    final idx = drafts.indexWhere((d) => d.id == id);
    if (idx >= 0) {
      drafts[idx] = drafts[idx].copyWith(status: status);
      await _saveAll(drafts);
    }
  }

  // ---------------------------------------------------------------------------
  // Baca
  // ---------------------------------------------------------------------------

  /// Semua draft yang masih `pending` (belum dikonfirmasi / diabaikan).
  Future<List<PaymentDraft>> getPendingDrafts() async =>
      (await _loadAll())
          .where((d) => d.status == PaymentDraftStatus.pending)
          .toList();

  /// Riwayat semua draft (untuk halaman pengaturan).
  Future<List<PaymentDraft>> getAllDrafts() => _loadAll();

  // ---------------------------------------------------------------------------
  // Pembersihan
  // ---------------------------------------------------------------------------

  /// Hapus draft yang sudah dikonfirmasi/diabaikan dan lebih dari 7 hari.
  Future<void> cleanup() async {
    final now = DateTime.now();
    final drafts = (await _loadAll()).where((d) {
      final age = now.difference(d.createdAt);
      final isOld = age > _retentionDuration;
      final isDone = d.status != PaymentDraftStatus.pending;
      return !(isOld || isDone);
    }).toList();
    await _saveAll(drafts);
  }

  /// Hapus semua draft.
  Future<void> clearAll() async => (await _prefs()).remove(_key);

  // ---------------------------------------------------------------------------
  // Persistensi internal
  // ---------------------------------------------------------------------------

  Future<List<PaymentDraft>> _loadAll() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => PaymentDraft.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAll(List<PaymentDraft> drafts) async {
    final prefs = await _prefs();
    await prefs.setString(
        _key, jsonEncode(drafts.map((d) => d.toJson()).toList()));
  }
}
