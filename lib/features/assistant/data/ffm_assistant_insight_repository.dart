import 'dart:async';
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../domain/ffm_assistant_insight.dart';

class FfmAssistantInsightRepository {
  FfmAssistantInsightRepository(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;
  bool _tableInitialized = false;

  Future<void> _ensureTable() async {
    if (_tableInitialized) return;
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS assistant_insights (
        id TEXT NOT NULL PRIMARY KEY,
        household_id TEXT NOT NULL,
        type TEXT NOT NULL,
        severity TEXT NOT NULL,
        priority INTEGER NOT NULL,
        confidence REAL NOT NULL,
        title TEXT NOT NULL,
        summary TEXT NOT NULL,
        evidence_json TEXT NOT NULL,
        gemini_explanation TEXT,
        suggested_action TEXT,
        destination TEXT,
        action_payload TEXT,
        created_at INTEGER NOT NULL,
        expires_at INTEGER,
        snoozed_until INTEGER,
        dedupe_key TEXT NOT NULL,
        cooldown_key TEXT,
        status TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_assistant_insights_household_status
      ON assistant_insights (household_id, status);
    ''');
    await _db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_assistant_insights_dedupe
      ON assistant_insights (dedupe_key);
    ''');
    _tableInitialized = true;
  }

  /// Menyimpan insight baru. Jika insight aktif dengan `dedupe_key` yang sama
  /// sudah ada, penyimpanan duplikat dihindari secara deterministik.
  Future<FfmAssistantInsight> saveInsight(FfmAssistantInsight insight) async {
    await _ensureTable();

    // Cek apakah ada insight aktif dengan dedupe_key yang sama
    final existing = await findActiveByDedupeKey(
      householdId: insight.householdId,
      dedupeKey: insight.dedupeKey,
    );
    if (existing != null) {
      return existing;
    }

    final map = insight.toMap();
    await _db.customInsert(
      '''
      INSERT OR REPLACE INTO assistant_insights (
        id, household_id, type, severity, priority, confidence,
        title, summary, evidence_json, gemini_explanation, suggested_action,
        destination, action_payload, created_at, expires_at, snoozed_until,
        dedupe_key, cooldown_key, status, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      variables: [
        Variable.withString(map['id']),
        Variable.withString(map['household_id']),
        Variable.withString(map['type']),
        Variable.withString(map['severity']),
        Variable.withInt(map['priority']),
        Variable.withReal(map['confidence']),
        Variable.withString(map['title']),
        Variable.withString(map['summary']),
        Variable.withString(map['evidence_json']),
        Variable.withString(map['gemini_explanation'] ?? ''),
        Variable.withString(map['suggested_action'] ?? ''),
        Variable.withString(map['destination'] ?? ''),
        Variable.withString(map['action_payload'] ?? ''),
        Variable.withInt(map['created_at']),
        Variable.withInt(map['expires_at'] ?? 0),
        Variable.withInt(map['snoozed_until'] ?? 0),
        Variable.withString(map['dedupe_key']),
        Variable.withString(map['cooldown_key'] ?? ''),
        Variable.withString(map['status']),
        Variable.withInt(map['updated_at']),
      ],
    );
    return insight;
  }

  Future<FfmAssistantInsight?> findActiveByDedupeKey({
    required String householdId,
    required String dedupeKey,
  }) async {
    await _ensureTable();
    final now = _clock().millisecondsSinceEpoch;
    final rows = await _db.customSelect(
      '''
      SELECT * FROM assistant_insights
      WHERE household_id = ?
        AND dedupe_key = ?
        AND status NOT IN ('dismissed', 'acted', 'expired')
        AND (expires_at = 0 OR expires_at > ?)
      LIMIT 1
      ''',
      variables: [
        Variable.withString(householdId),
        Variable.withString(dedupeKey),
        Variable.withInt(now),
      ],
    ).get();

    if (rows.isEmpty) return null;
    return _fromRow(rows.first.data);
  }

  Future<List<FfmAssistantInsight>> getActiveInsights({
    required String householdId,
  }) async {
    await _ensureTable();
    final now = _clock().millisecondsSinceEpoch;

    // Bersihkan status expired terlebih dahulu
    await _db.customUpdate(
      '''
      UPDATE assistant_insights
      SET status = 'expired', updated_at = ?
      WHERE household_id = ?
        AND status NOT IN ('dismissed', 'acted', 'expired')
        AND expires_at > 0 AND expires_at <= ?
      ''',
      variables: [
        Variable.withInt(now),
        Variable.withString(householdId),
        Variable.withInt(now),
      ],
    );

    final rows = await _db.customSelect(
      '''
      SELECT * FROM assistant_insights
      WHERE household_id = ?
        AND status IN ('newInsight', 'seen', 'snoozed')
        AND (expires_at = 0 OR expires_at > ?)
        AND (snoozed_until = 0 OR snoozed_until <= ?)
      ORDER BY priority DESC, created_at DESC
      ''',
      variables: [
        Variable.withString(householdId),
        Variable.withInt(now),
        Variable.withInt(now),
      ],
    ).get();

    return rows.map((r) => _fromRow(r.data)).toList();
  }

  Future<List<FfmAssistantInsight>> getAllInsights({
    required String householdId,
    int limit = 50,
  }) async {
    await _ensureTable();
    final rows = await _db.customSelect(
      '''
      SELECT * FROM assistant_insights
      WHERE household_id = ?
      ORDER BY created_at DESC
      LIMIT ?
      ''',
      variables: [
        Variable.withString(householdId),
        Variable.withInt(limit),
      ],
    ).get();

    return rows.map((r) => _fromRow(r.data)).toList();
  }

  Future<void> markSeen(String id) async {
    await _ensureTable();
    final now = _clock().millisecondsSinceEpoch;
    await _db.customUpdate(
      '''
      UPDATE assistant_insights
      SET status = 'seen', updated_at = ?
      WHERE id = ? AND status = 'newInsight'
      ''',
      variables: [Variable.withInt(now), Variable.withString(id)],
    );
  }

  Future<void> dismiss(String id) async {
    await _ensureTable();
    final now = _clock().millisecondsSinceEpoch;
    await _db.customUpdate(
      '''
      UPDATE assistant_insights
      SET status = 'dismissed', updated_at = ?
      WHERE id = ?
      ''',
      variables: [Variable.withInt(now), Variable.withString(id)],
    );
  }

  Future<void> snooze(String id, Duration duration) async {
    await _ensureTable();
    final now = _clock();
    final until = now.add(duration).millisecondsSinceEpoch;
    await _db.customUpdate(
      '''
      UPDATE assistant_insights
      SET status = 'snoozed', snoozed_until = ?, updated_at = ?
      WHERE id = ?
      ''',
      variables: [
        Variable.withInt(until),
        Variable.withInt(now.millisecondsSinceEpoch),
        Variable.withString(id),
      ],
    );
  }

  Future<void> markActed(String id) async {
    await _ensureTable();
    final now = _clock().millisecondsSinceEpoch;
    await _db.customUpdate(
      '''
      UPDATE assistant_insights
      SET status = 'acted', updated_at = ?
      WHERE id = ?
      ''',
      variables: [Variable.withInt(now), Variable.withString(id)],
    );
  }

  FfmAssistantInsight _fromRow(Map<String, dynamic> raw) {
    // Normalisasi nilai null/kosong dari kolom teks
    final geminiExplanation = raw['gemini_explanation']?.toString();
    final suggestedAction = raw['suggested_action']?.toString();
    final destination = raw['destination']?.toString();
    final actionPayload = raw['action_payload']?.toString();
    final cooldownKey = raw['cooldown_key']?.toString();
    final expiresAt = raw['expires_at'] as int?;
    final snoozedUntil = raw['snoozed_until'] as int?;

    final map = Map<String, dynamic>.from(raw);
    if (geminiExplanation?.isEmpty == true) map.remove('gemini_explanation');
    if (suggestedAction?.isEmpty == true) map.remove('suggested_action');
    if (destination?.isEmpty == true) map.remove('destination');
    if (actionPayload?.isEmpty == true) map.remove('action_payload');
    if (cooldownKey?.isEmpty == true) map.remove('cooldown_key');
    if (expiresAt == 0) map.remove('expires_at');
    if (snoozedUntil == 0) map.remove('snoozed_until');

    return FfmAssistantInsight.fromMap(map);
  }
}
