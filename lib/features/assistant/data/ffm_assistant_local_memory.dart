import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Memori kecil di perangkat untuk istilah yang disetujui pengguna.
/// Tidak memuat transaksi atau data keluarga keluar dari perangkat.
class FfmAssistantLocalMemory {
  FfmAssistantLocalMemory([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _aliasesKey = 'ffm_assistant_aliases_v1';
  final FlutterSecureStorage _storage;

  Future<Map<String, String>> readAliases() async {
    try {
      final raw = await _storage.read(key: _aliasesKey);
      if (raw == null || raw.trim().isEmpty) return const {};
      final json = jsonDecode(raw);
      if (json is! Map) return const {};
      return json.map(
        (key, value) => MapEntry(
          key.toString().trim().toLowerCase(),
          value.toString().trim().toLowerCase(),
        ),
      )..removeWhere((key, value) => key.isEmpty || value.isEmpty);
    } catch (_) {
      return const {};
    }
  }

  Future<void> saveAlias(String alias, String canonicalValue) async {
    final safeAlias = alias.trim().toLowerCase();
    final safeValue = canonicalValue.trim().toLowerCase();
    if (safeAlias.isEmpty || safeValue.isEmpty) return;
    final aliases = Map<String, String>.from(await readAliases())
      ..[safeAlias] = safeValue;
    await _storage.write(key: _aliasesKey, value: jsonEncode(aliases));
  }

  Future<String> applyAliases(String normalizedText) async {
    final aliases = await readAliases();
    var resolved = normalizedText;
    final entries = aliases.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final entry in entries) {
      resolved = resolved.replaceAll(entry.key, entry.value);
    }
    return resolved;
  }
}

class FfmAssistantSanityCheck {
  const FfmAssistantSanityCheck._();

  static String? transferWarning({
    required int? amount,
    required String? fromAccount,
    required String? toAccount,
    required int? adminFee,
  }) {
    if (amount == null || amount <= 0) return 'Nominal transfer belum terbaca.';
    if (fromAccount == null || toAccount == null) {
      return 'Pilih rekening asal dan tujuan dulu supaya alur uangnya tidak keliru.';
    }
    if (fromAccount.toLowerCase() == toAccount.toLowerCase()) {
      return 'Rekening asal dan tujuan sama. Cek lagi sebelum membuat transfer.';
    }
    if (adminFee != null && adminFee > amount) {
      return 'Biaya admin lebih besar dari nominal pindahan. Cek nominalnya dulu, ya.';
    }
    return null;
  }

  static String? transactionWarning({
    required int? amount,
    required bool isIncome,
  }) {
    if (amount == null || amount <= 0) {
      return 'Nominal belum terbaca. Sebutkan angka rupiahnya dulu, ya.';
    }
    if (amount >= 1000000000) {
      return 'Nominalnya sangat besar. Pastikan lagi jumlah rupiahnya sebelum disimpan.';
    }
    if (!isIncome && amount >= 100000000) {
      return 'Pengeluaran ini cukup besar. Pastikan kategori dan sumber uangnya sebelum lanjut.';
    }
    return null;
  }
}
