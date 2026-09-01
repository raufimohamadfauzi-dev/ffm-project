import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import 'ffm_assistant_memory_repository.dart';

/// Pengamat kebiasaan aktivitas harian - Activity Intelligence Upgrade
///
/// Setiap kali sesi/jurnal aktivitas tersimpan, pengamat ini menghitung ulang
/// frekuensi aktivitas serupa dalam 60 hari terakhir dengan menggunakan konteks
/// terstruktur (activity type, category, subject, location, frequency) bukan hanya judul.
///
/// Bila pola muncul minimal 3 kali, ia menyimpan/memperbarui satu memori `habit`
/// (disetujui otomatis karena hanya merangkum perilaku pengguna sendiri) sehingga
/// Agent maupun SLM memahami rutinitas user saat menjawab.
///
/// Upgrade:
/// - Menggunakan konteks terstruktur (category, subject, location) bila tersedia
/// - Tidak otomatis menggabung aktivitas berbeda hanya karena kategori sama
/// - Lebih cerdas dalam mengenali pola yang sama dengan variasi judul
class FfmActivityHabitLearner {
  FfmActivityHabitLearner(this._database, this._memories);

  static const int _minOccurrences = 3;
  static const int _windowDays = 60;
  static const String _kind = 'habit';

  final AppDatabase _database;
  final FfmAssistantMemoryRepository _memories;

  Future<void> recordActivityObservation({
    required String title,
    required DateTime occurredAt,
    // Activity Intelligence Upgrade - structured context
    String? category,
    String? activityGroupId,
    String? subjectType,
    String? subjectId,
  }) async {
    final normalized = title.trim().toLowerCase();
    if (normalized.length < 3) return;

    try {
      final since = occurredAt.subtract(const Duration(days: _windowDays));
      final rows =
          await (_database.select(_database.activitySessions)
                ..where(
                  (row) =>
                      row.householdId.equals(
                        FfmAssistantMemoryRepository.householdId,
                      ) &
                      row.isArchived.equals(false) &
                      row.startedAt.isBiggerOrEqualValue(since),
                )
                ..orderBy([
                  (row) => OrderingTerm.desc(row.startedAt),
                ]))
              .get();

      // Upgrade: Gunakan konteks terstruktur untuk matching yang lebih cerdas
      final matchedActivities = <_ActivityPatternMatch>[];
      for (final row in rows) {
        final match = _shouldMatchAsPattern(
          normalized: normalized,
          category: category,
          activityGroupId: activityGroupId,
          subjectType: subjectType,
          subjectId: subjectId,
          row: row,
        );
        if (match != null) {
          matchedActivities.add(match);
        }
      }
      
      if (matchedActivities.length < _minOccurrences) return;

      // Analisis pola dengan konteks terstruktur
      final hourCounts = <int, int>{};
      final categoryCounts = <String, int>{};
      final subjectCounts = <String, int>{};
      
      for (final match in matchedActivities) {
        hourCounts.update(match.hour, (count) => count + 1, ifAbsent: () => 1);
        if (match.category != null) {
          categoryCounts.update(match.category!, (count) => count + 1, ifAbsent: () => 1);
        }
        if (match.subjectId != null) {
          subjectCounts.update(match.subjectId!, (count) => count + 1, ifAbsent: () => 1);
        }
      }

      // Jam paling umum (dibulatkan ke jam).
      var topHour = matchedActivities.first.hour;
      var topCount = -1;
      hourCounts.forEach((hour, count) {
        if (count > topCount) {
          topHour = hour;
          topCount = count;
        }
      });

      // Kategori dan subject paling umum
      final topCategory = categoryCounts.isNotEmpty
          ? categoryCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key
          : null;
      final topSubjectId = subjectCounts.isNotEmpty
          ? subjectCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key
          : null;

      final count = matchedActivities.length;
      final displayTitle = title.trim();
      
      // Generate value text dengan konteks terstruktur
      var value = 'User tercatat melakukan "$displayTitle" $count kali dalam '
          '$_windowDays hari terakhir, biasanya sekitar jam ${topHour.toString().padLeft(2, '0')}:00.';
      
      if (topCategory != null) {
        value += ' Kategori utama: $topCategory.';
      }
      if (topSubjectId != null) {
        value += ' Terkait subjek: $topSubjectId.';
      }

      // Generate memory ID yang lebih spesifik dengan konteks
      final contextHash = _generateContextHash(
        normalized: normalized,
        category: category,
        subjectId: subjectId,
      );
      final memoryId = 'habit-activity-$contextHash';

      await _memories.save(
        id: memoryId,
        kind: _kind,
        triggerText: 'aktivitas:$normalized',
        valueText: value,
        source: 'activity-observer',
        metadata: <String, dynamic>{
          'scope': 'user-model',
          'approved': true,
          'confidence': (count / (count + 4)).clamp(0.0, 0.9),
          'importance': (0.5 + math.min(count, 20) / 100).clamp(0.0, 1.0),
          'occurrences': count,
          'typicalHour': topHour,
          'category': topCategory,
          'subjectId': topSubjectId,
          'lastObservedAt': occurredAt.toIso8601String(),
          'patternType': _determinePatternType(category, subjectId),
        },
      );
    } on Object {
      // Pembelajaran tidak boleh menggagalkan penyimpanan aktivitas.
    }
  }

  /// Activity Intelligence Upgrade - Matching yang lebih cerdas dengan konteks
  _ActivityPatternMatch? _shouldMatchAsPattern({
    required String normalized,
    required String? category,
    required String? activityGroupId,
    required String? subjectType,
    required String? subjectId,
    required ActivitySession row,
  }) {
    final rowTitle = row.title.trim().toLowerCase();
    
    // 1. Exact title match (highest confidence)
    if (rowTitle == normalized) {
      return _ActivityPatternMatch(
        hour: row.startedAt.hour,
        category: row.category,
        subjectId: row.subjectId,
        confidence: 1.0,
      );
    }

    // 2. Same category + similar title pattern
    if (category != null && row.category == category) {
      if (_isSimilarTitle(normalized, rowTitle)) {
        return _ActivityPatternMatch(
          hour: row.startedAt.hour,
          category: row.category,
          subjectId: row.subjectId,
          confidence: 0.8,
        );
      }
    }

    // 3. Same subject + similar activity (pertanian context)
    if (subjectId != null && row.subjectId == subjectId) {
      if (_isSimilarTitle(normalized, rowTitle)) {
        return _ActivityPatternMatch(
          hour: row.startedAt.hour,
          category: row.category,
          subjectId: row.subjectId,
          confidence: 0.9,
        );
      }
    }

    // 4. Same activity group (rangkaian proses yang sama)
    if (activityGroupId != null && row.activityGroupId == activityGroupId) {
      return _ActivityPatternMatch(
        hour: row.startedAt.hour,
        category: row.category,
        subjectId: row.subjectId,
        confidence: 0.85,
      );
    }

    // Jangan otomatis menggabung hanya karena kategori sama
    return null;
  }

  /// Cek apakah dua judul cukup mirip untuk dianggap pola yang sama
  bool _isSimilarTitle(String a, String b) {
    // Sederhana: cek overlap kata kunci
    final wordsA = a.split(' ').where((w) => w.length > 2).toSet();
    final wordsB = b.split(' ').where((w) => w.length > 2).toSet();
    
    if (wordsA.isEmpty || wordsB.isEmpty) return false;
    
    final intersection = wordsA.intersection(wordsB);
    final union = wordsA.union(wordsB);
    
    // Jika >50% kata kunci sama, anggap mirip
    return intersection.length / union.length > 0.5;
  }

  /// Generate hash yang lebih spesifik dengan konteks
  String _generateContextHash({
    required String normalized,
    required String? category,
    required String? subjectId,
  }) {
    var hash = 0x7fffffff;
    final context = '$normalized|${category ?? ''}|${subjectId ?? ''}';
    for (final code in context.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash.toRadixString(36);
  }

  /// Tentukan tipe pola untuk metadata
  String _determinePatternType(String? category, String? subjectId) {
    if (subjectId != null) return 'subject-based';
    if (category != null) return 'category-based';
    return 'title-based';
  }
}

/// Helper class untuk pattern matching
class _ActivityPatternMatch {
  const _ActivityPatternMatch({
    required this.hour,
    required this.category,
    required this.subjectId,
    required this.confidence,
  });

  final int hour;
  final String? category;
  final String? subjectId;
  final double confidence;
}
