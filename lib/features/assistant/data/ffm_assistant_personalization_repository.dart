import 'dart:math';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

class FfmPersonalizationPattern {
  const FfmPersonalizationPattern({
    required this.merchantName,
    required this.fieldName,
    required this.mostCommonValue,
    required this.confidenceScore,
    required this.sampleCount,
    required this.lastUpdated,
  });

  static const minimumSampleCount = 5;
  static const minimumConfidenceScore = 0.8;

  final String merchantName;
  final String fieldName;
  final String mostCommonValue;
  final double confidenceScore;
  final int sampleCount;
  final DateTime lastUpdated;

  bool get isStrong =>
      sampleCount >= minimumSampleCount &&
      confidenceScore >= minimumConfidenceScore;
}

/// Penyimpanan pembelajaran terkontrol di sisi orchestrator.
///
/// Repository ini hanya menyimpan koreksi/preferensi/pola terstruktur. Ia tidak
/// melatih ulang model, tidak menyimpan riwayat chat, dan tidak membaca baris
/// transaksi mentah untuk dimasukkan ke prompt.
class FfmAssistantPersonalizationRepository {
  static const allowedCorrectionFields = <String>{
    'category',
    'account',
    'amount',
  };

  FfmAssistantPersonalizationRepository(
    this._database, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final DateTime Function() _clock;
  final _random = Random();

  Future<void> recordCorrection({
    required String householdId,
    required String merchantName,
    required String fieldName,
    required String? slmValue,
    required String correctedValue,
  }) async {
    final merchant = _bounded(merchantName, 160);
    final field = _bounded(fieldName, 80);
    final corrected = _bounded(correctedValue, 240);
    if (merchant.isEmpty ||
        field.isEmpty ||
        corrected.isEmpty ||
        !allowedCorrectionFields.contains(field)) {
      return;
    }

    final now = _clock();
    await _database
        .into(_database.userCorrections)
        .insert(
          UserCorrectionsCompanion.insert(
            id: _id(now),
            householdId: _bounded(householdId, 120),
            merchantName: merchant,
            fieldName: field,
            slmValue: Value(slmValue == null ? null : _bounded(slmValue, 240)),
            correctedValue: corrected,
            timestamp: now,
          ),
        );
  }

  Future<void> setPreference({
    required String householdId,
    required String preferenceKey,
    required String preferenceValue,
  }) async {
    final household = _bounded(householdId, 120);
    final key = _bounded(preferenceKey, 120);
    final value = _bounded(preferenceValue, 500);
    if (household.isEmpty || key.isEmpty || value.isEmpty) return;

    final existing =
        await (_database.select(_database.userPreferences)..where(
              (row) =>
                  row.householdId.equals(household) &
                  row.preferenceKey.equals(key),
            ))
            .getSingleOrNull();
    final now = _clock();
    if (existing == null) {
      await _database
          .into(_database.userPreferences)
          .insert(
            UserPreferencesCompanion.insert(
              id: _id(now),
              householdId: household,
              preferenceKey: key,
              preferenceValue: value,
              updatedAt: now,
            ),
          );
    } else {
      await (_database.update(
        _database.userPreferences,
      )..where((row) => row.id.equals(existing.id))).write(
        UserPreferencesCompanion(
          preferenceValue: Value(value),
          updatedAt: Value(now),
        ),
      );
    }
  }

  Future<void> deletePreference({
    required String householdId,
    required String preferenceKey,
  }) async {
    final household = _bounded(householdId, 120);
    final key = _bounded(preferenceKey, 120);
    if (household.isEmpty || key.isEmpty) return;
    await (_database.delete(_database.userPreferences)..where(
          (row) =>
              row.householdId.equals(household) & row.preferenceKey.equals(key),
        ))
        .go();
  }

  Future<List<InteractionPattern>> getAllPatterns(String householdId) =>
      (_database.select(
            _database.interactionPatterns,
          )..where((row) => row.householdId.equals(_bounded(householdId, 120))))
          .get();

  Future<void> importPatterns({
    required String householdId,
    required List<Map<String, dynamic>> patterns,
  }) async {
    final household = _bounded(householdId, 120);
    if (household.isEmpty || patterns.isEmpty) return;

    for (final p in patterns) {
      final merchant = _bounded(p['merchantName'] as String? ?? '', 160);
      final field = _bounded(p['fieldName'] as String? ?? '', 80);
      final value = _bounded(p['mostCommonValue'] as String? ?? '', 240);
      final confidence = (p['confidenceScore'] as num?)?.toDouble() ?? 0.0;
      final sampleCount = (p['sampleCount'] as num?)?.toInt() ?? 0;
      if (merchant.isEmpty ||
          field.isEmpty ||
          value.isEmpty ||
          !allowedCorrectionFields.contains(field) ||
          confidence < 0 ||
          confidence > 1 ||
          sampleCount < 0) {
        continue;
      }

      final existing =
          await (_database.select(_database.interactionPatterns)..where(
                (row) =>
                    row.householdId.equals(household) &
                    row.merchantName.equals(merchant) &
                    row.fieldName.equals(field),
              ))
              .getSingleOrNull();
      final lastUpdated =
          DateTime.tryParse(p['lastUpdated'] as String? ?? '') ?? _clock();
      final companion = InteractionPatternsCompanion(
        householdId: Value(household),
        merchantName: Value(merchant),
        fieldName: Value(field),
        mostCommonValue: Value(value),
        confidenceScore: Value(confidence),
        sampleCount: Value(sampleCount),
        lastUpdated: Value(lastUpdated),
      );
      if (existing == null) {
        await _database
            .into(_database.interactionPatterns)
            .insert(
              InteractionPatternsCompanion.insert(
                id: _id(lastUpdated),
                householdId: household,
                merchantName: merchant,
                fieldName: field,
                mostCommonValue: value,
                confidenceScore: confidence,
                sampleCount: sampleCount,
                lastUpdated: lastUpdated,
              ),
            );
      } else {
        await (_database.update(
          _database.interactionPatterns,
        )..where((row) => row.id.equals(existing.id))).write(companion);
      }
    }
  }

  Future<List<UserPreference>> getPreferences(String householdId) =>
      (_database.select(_database.userPreferences)
            ..where((row) => row.householdId.equals(_bounded(householdId, 120)))
            ..orderBy([(row) => OrderingTerm.asc(row.preferenceKey)]))
          .get();

  Future<FfmPersonalizationPattern?> getPatternForMerchant({
    required String householdId,
    required String merchantName,
    required String fieldName,
    bool strongOnly = true,
  }) async {
    final row =
        await (_database.select(_database.interactionPatterns)..where(
              (pattern) =>
                  pattern.householdId.equals(_bounded(householdId, 120)) &
                  pattern.merchantName.equals(_bounded(merchantName, 160)) &
                  pattern.fieldName.equals(_bounded(fieldName, 80)),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    final pattern = _toPattern(row);
    if (strongOnly && !pattern.isStrong) return null;
    return pattern;
  }

  Future<String> buildPersonalizedContext({
    required String householdId,
    required String query,
    int maxCharacters = 900,
  }) async {
    final household = _bounded(householdId, 120);
    final budget = maxCharacters.clamp(1, 900);
    final normalizedQuery = query.toLowerCase();
    final preferences = await getPreferences(household);
    final patterns = await (_database.select(
      _database.interactionPatterns,
    )..where((row) => row.householdId.equals(household))).get();
    final relevantPatterns = patterns
        .map(_toPattern)
        .where((pattern) {
          if (!pattern.isStrong) return false;
          final merchant = pattern.merchantName.toLowerCase();
          return merchant.isNotEmpty && normalizedQuery.contains(merchant);
        })
        .take(8)
        .toList(growable: false);

    final lines = <String>[
      if (preferences.isNotEmpty)
        'Preferensi eksplisit: ${preferences.take(8).map((item) => '${item.preferenceKey}=${item.preferenceValue}').join('; ')}',
      ...relevantPatterns.map(
        (pattern) =>
            'Pola kuat: merchant=${pattern.merchantName}; field=${pattern.fieldName}; nilai=${pattern.mostCommonValue}; konsistensi=${(pattern.confidenceScore * 100).round()}%; sampel=${pattern.sampleCount}',
      ),
    ];
    if (lines.isEmpty) return '';
    return _bounded(
      'Personalisasi lokal (hanya saran, verifikasi tetap wajib): ${lines.join(' | ')}',
      budget,
    );
  }

  Future<int> recalculatePatterns(String householdId) async {
    final household = _bounded(householdId, 120);
    final corrections = await (_database.select(
      _database.userCorrections,
    )..where((row) => row.householdId.equals(household))).get();
    final groups = <String, List<UserCorrection>>{};
    for (final correction in corrections) {
      final key = '${correction.merchantName}\u0000${correction.fieldName}';
      (groups[key] ??= <UserCorrection>[]).add(correction);
    }

    await (_database.delete(
      _database.interactionPatterns,
    )..where((row) => row.householdId.equals(household))).go();

    final companions = <InteractionPatternsCompanion>[];
    for (final group in groups.values) {
      if (group.isEmpty) continue;
      final counts = <String, int>{};
      for (final correction in group) {
        counts.update(
          correction.correctedValue,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      final winner = counts.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      final latest = group
          .map((correction) => correction.timestamp)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      companions.add(
        InteractionPatternsCompanion.insert(
          id: _id(latest),
          householdId: household,
          merchantName: group.first.merchantName,
          fieldName: group.first.fieldName,
          mostCommonValue: winner.key,
          confidenceScore: winner.value / group.length,
          sampleCount: group.length,
          lastUpdated: latest,
        ),
      );
    }
    if (companions.isNotEmpty) {
      await _database.batch((batch) {
        batch.insertAll(_database.interactionPatterns, companions);
      });
    }
    return companions.length;
  }

  Future<void> resetLearning(
    String householdId, {
    bool includePreferences = false,
  }) async {
    final household = _bounded(householdId, 120);
    await (_database.delete(
      _database.userCorrections,
    )..where((row) => row.householdId.equals(household))).go();
    await (_database.delete(
      _database.interactionPatterns,
    )..where((row) => row.householdId.equals(household))).go();

    if (includePreferences) {
      await (_database.delete(
        _database.userPreferences,
      )..where((row) => row.householdId.equals(household))).go();
    }
  }

  FfmPersonalizationPattern _toPattern(InteractionPattern row) =>
      FfmPersonalizationPattern(
        merchantName: row.merchantName,
        fieldName: row.fieldName,
        mostCommonValue: row.mostCommonValue,
        confidenceScore: row.confidenceScore,
        sampleCount: row.sampleCount,
        lastUpdated: row.lastUpdated,
      );

  String _id(DateTime now) =>
      '${now.microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';

  String _bounded(String value, int maxLength) {
    final normalized = value.trim();
    if (normalized.length <= maxLength) return normalized;
    return normalized.substring(0, maxLength);
  }
}
