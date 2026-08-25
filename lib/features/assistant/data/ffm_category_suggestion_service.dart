import 'dart:convert';

import 'package:drift/drift.dart' hide Column;

import '../../../core/database/app_database.dart';
import '../domain/ffm_assistant_models.dart';
import 'ffm_assistant_personalization_repository.dart';

/// Kontrak lapis SLM untuk menebak kategori transaksi.
///
/// Implementasi harus memilih SATU nama dari [allowedCategories] atau
/// mengembalikan null. Dilarang mengarang kategori di luar daftar.
abstract interface class FfmAssistantCategoryAdvisor {
  Future<String?> suggestCategory({
    required String description,
    required List<String> allowedCategories,
  });
}

/// Validator keluaran SLM: hasil hanya diterima bila persis salah satu
/// kategori resmi (case-insensitive).
class FfmAssistantCategoryAdviceContract {
  const FfmAssistantCategoryAdviceContract._();

  static String? parse(String raw, List<String> allowed) {
    if (allowed.isEmpty) return null;
    var value = raw.trim();
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        final category = decoded['category'];
        if (category is String && category.trim().isNotEmpty) {
          value = category.trim();
        }
      }
    } on FormatException {
      // Bukan JSON — perlakukan sebagai teks biasa.
    }
    if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
      value = value.substring(1, value.length - 1).trim();
    }
    for (final candidate in allowed) {
      if (candidate.toLowerCase() == value.toLowerCase()) return candidate;
    }
    return null;
  }
}

/// Hasil saran kategori beserta asal-usulnya agar UI bisa menjelaskan.
class FfmCategorySuggestion {
  const FfmCategorySuggestion({
    required this.categoryName,
    required this.sourceLabel,
  });

  final String categoryName;

  /// 'pola penggunaanmu' (Agent) atau 'AI lokal' (SLM).
  final String sourceLabel;
}

/// Saran kategori otomatis untuk draft pemasukan/pengeluaran yang belum
/// memiliki kategori. Kerjanya berlapis:
///
/// 1. Lapis Agent (deterministik): pakai pola historis per merchant dari
///    koreksi pengguna sebelumnya (`InteractionPatterns`), divalidasi ulang
///    terhadap daftar kategori aktif.
/// 2. Lapis SLM: kalau tidak ada pola kuat, model lokal diminta memilih dari
///    daftar kategori resmi; jawaban di luar daftar dibuang.
class FfmCategorySuggestionService {
  FfmCategorySuggestionService({
    required this.database,
    required this.personalization,
    this.advisor,
  });

  static const householdId = 'local-household';

  final AppDatabase database;
  final FfmAssistantPersonalizationRepository personalization;
  final FfmAssistantCategoryAdvisor? advisor;

  Future<FfmCategorySuggestion?> suggestForDraft({
    required FfmAssistantDraftKind kind,
    required String queryText,
    String? merchantName,
  }) async {
    if (kind != FfmAssistantDraftKind.expense &&
        kind != FfmAssistantDraftKind.income) {
      return null;
    }
    final type = kind == FfmAssistantDraftKind.income ? 'income' : 'expense';
    final allowed = await _activeCategoryNames(type);
    if (allowed.isEmpty) return null;

    // 1. Pola historis per merchant (Agent).
    final merchant = merchantName?.trim();
    if (merchant != null && merchant.isNotEmpty) {
      try {
        final pattern = await personalization.getPatternForMerchant(
          householdId: householdId,
          merchantName: merchant,
          fieldName: 'category',
          strongOnly: true,
        );
        final learned = pattern?.mostCommonValue.trim() ?? '';
        final matched = allowed.where(
          (name) => name.toLowerCase() == learned.toLowerCase(),
        );
        if (learned.isNotEmpty && matched.isNotEmpty) {
          return FfmCategorySuggestion(
            categoryName: matched.first,
            sourceLabel: 'pola penggunaanmu',
          );
        }
      } on Object {
        // Pola gagal dibaca → lanjut ke lapis SLM.
      }
    }

    // 2. Tebakan SLM dari deskripsi bebas.
    final categoryAdvisor = advisor;
    if (categoryAdvisor == null) return null;
    final description = queryText.trim();
    if (description.length < 3) return null;
    try {
      final raw = await categoryAdvisor.suggestCategory(
        description: description,
        allowedCategories: allowed,
      );
      if (raw == null) return null;
      final parsed = FfmAssistantCategoryAdviceContract.parse(raw, allowed);
      if (parsed == null) return null;
      return FfmCategorySuggestion(categoryName: parsed, sourceLabel: 'AI lokal');
    } on Object {
      return null;
    }
  }

  Future<List<String>> _activeCategoryNames(String type) async {
    final rows =
        await (database.select(database.categories)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.isActive.equals(true) &
                    row.type.equals(type),
              ))
            .get();
    final names = rows.map((row) => row.name.trim()).toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    return names;
  }
}
