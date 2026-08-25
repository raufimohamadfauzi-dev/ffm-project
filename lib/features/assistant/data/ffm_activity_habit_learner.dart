import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import 'ffm_assistant_memory_repository.dart';

/// Pengamat kebiasaan aktivitas harian.
///
/// Setiap kali sesi/jurnal aktivitas tersimpan, pengamat ini menghitung ulang
/// frekuensi judul serupa dalam 60 hari terakhir. Bila pola muncul minimal
/// 3 kali, ia menyimpan/memperbarui satu memori `habit` (disetujui otomatis
/// karena hanya merangkum perilaku pengguna sendiri) sehingga Agent maupun
/// SLM memahami rutinitas user saat menjawab.
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

      final matchedHours = <int>[];
      for (final row in rows) {
        if (row.title.trim().toLowerCase() != normalized) continue;
        matchedHours.add(row.startedAt.hour);
      }
      if (matchedHours.length < _minOccurrences) return;

      // Jam paling umum (dibulatkan ke jam).
      final hourCounts = <int, int>{};
      for (final hour in matchedHours) {
        hourCounts.update(hour, (count) => count + 1, ifAbsent: () => 1);
      }
      var topHour = matchedHours.first;
      var topCount = -1;
      hourCounts.forEach((hour, count) {
        if (count > topCount) {
          topHour = hour;
          topCount = count;
        }
      });

      final count = matchedHours.length;
      final displayTitle = title.trim();
      final value =
          'User tercatat melakukan "$displayTitle" $count kali dalam '
          '$_windowDays hari terakhir, biasanya sekitar jam ${topHour.toString().padLeft(2, '0')}:00.';
      final memoryId = 'habit-activity-${_stableHash(normalized)}';


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
          'lastObservedAt': occurredAt.toIso8601String(),
        },
      );
    } on Object {
      // Pembelajaran tidak boleh menggagalkan penyimpanan aktivitas.
    }
  }

  String _stableHash(String value) {
    var hash = 0x7fffffff;
    for (final code in value.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash.toRadixString(36);
  }
}
