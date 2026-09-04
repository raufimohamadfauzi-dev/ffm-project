import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'gemini_service.dart';

class GeminiDailyQuotaSnapshot {
  const GeminiDailyQuotaSnapshot({
    required this.requestsUsed,
    required this.requestsLimit,
    required this.promptTokens,
    required this.candidateTokens,
    required this.totalTokens,
    required this.nextResetTime,
    required this.timeUntilReset,
    this.lastRequestAt,
  });

  final int requestsUsed;
  final int requestsLimit;
  final int promptTokens;
  final int candidateTokens;
  final int totalTokens;
  final DateTime nextResetTime;
  final Duration timeUntilReset;
  final DateTime? lastRequestAt;

  int get requestsRemaining =>
      (requestsLimit - requestsUsed).clamp(0, requestsLimit);

  double get usageRatio =>
      requestsLimit <= 0 ? 0.0 : (requestsUsed / requestsLimit).clamp(0.0, 1.0);

  bool get isExhausted => requestsRemaining <= 0;

  String get formattedCountdown {
    final hours = timeUntilReset.inHours;
    final minutes = timeUntilReset.inMinutes % 60;
    if (hours > 0) {
      return '$hours jam $minutes menit';
    }
    return '$minutes menit';
  }
}

class GeminiUsageSnapshot {
  const GeminiUsageSnapshot({
    required this.code,
    required this.model,
    required this.ok,
    required this.at,
    this.httpStatus,
    this.latencyMs,
    this.promptTokens,
    this.candidateTokens,
    this.totalTokens,
  });

  final String code;
  final String model;
  final bool ok;
  final DateTime at;
  final int? httpStatus;
  final int? latencyMs;
  final int? promptTokens;
  final int? candidateTokens;
  final int? totalTokens;
}

class SupabaseConfig {
  static const _urlKey = 'supabase_url';
  static const _anonKey = 'supabase_anon_key';
  static const _userKey = 'supabase_user_id';
  static const _geminiKey = 'gemini_api_key';
  static const _geminiModelKey = 'gemini_model';
  static const _geminiVerifiedKey = 'gemini_api_verified';
  static const _geminiUsageCodeKey = 'gemini_last_usage_code';
  static const _geminiUsageModelKey = 'gemini_last_usage_model';
  static const _geminiUsageOkKey = 'gemini_last_usage_ok';
  static const _geminiUsageAtKey = 'gemini_last_usage_at';
  static const _geminiUsageHttpKey = 'gemini_last_usage_http';
  static const _geminiUsageLatencyKey = 'gemini_last_usage_latency_ms';
  static const _geminiUsagePromptTokensKey = 'gemini_last_usage_prompt_tokens';
  static const _geminiUsageCandidateTokensKey = 'gemini_last_usage_candidate_tokens';
  static const _geminiUsageTotalTokensKey = 'gemini_last_usage_total_tokens';
  static const _geminiQuotaCycleResetKey = 'gemini_quota_cycle_reset_at';
  static const _geminiDailyRequestsKey = 'gemini_daily_requests_count';
  static const _geminiDailyPromptTokensKey = 'gemini_daily_prompt_tokens';
  static const _geminiDailyCandidateTokensKey = 'gemini_daily_candidate_tokens';
  static const _geminiDailyTotalTokensKey = 'gemini_daily_total_tokens';
  static const _llmModeKey = 'preferred_llm_mode';

  static const defaultUrl = '';
  static const defaultAnonKey = '';

  final _storage = const FlutterSecureStorage();

  Future<String?> getUrl() async => await _storage.read(key: _urlKey);
  Future<String?> getAnonKey() async => await _storage.read(key: _anonKey);
  Future<String?> getGeminiKey() async => await _storage.read(key: _geminiKey);

  Future<String?> getGeminiModel() async =>
      await _storage.read(key: _geminiModelKey);

  Future<bool> isGeminiVerified() async =>
      (await _storage.read(key: _geminiVerifiedKey)) == 'true';

  Future<GeminiUsageSnapshot?> getGeminiUsage() async {
    final code = await _storage.read(key: _geminiUsageCodeKey);
    final model = await _storage.read(key: _geminiUsageModelKey);
    final ok = await _storage.read(key: _geminiUsageOkKey);
    final at = await _storage.read(key: _geminiUsageAtKey);
    if (code == null || model == null || ok == null || at == null) return null;
    final parsedAt = DateTime.tryParse(at);
    if (parsedAt == null) return null;
    return GeminiUsageSnapshot(
      code: code,
      model: model,
      ok: ok == 'true',
      at: parsedAt,
      httpStatus: int.tryParse(
        (await _storage.read(key: _geminiUsageHttpKey)) ?? '',
      ),
      latencyMs: int.tryParse(
        (await _storage.read(key: _geminiUsageLatencyKey)) ?? '',
      ),
      promptTokens: int.tryParse(
        (await _storage.read(key: _geminiUsagePromptTokensKey)) ?? '',
      ),
      candidateTokens: int.tryParse(
        (await _storage.read(key: _geminiUsageCandidateTokensKey)) ?? '',
      ),
      totalTokens: int.tryParse(
        (await _storage.read(key: _geminiUsageTotalTokensKey)) ?? '',
      ),
    );
  }

  Future<String> getLlmMode() async {
    // Gemini Cloud is the sole conversational provider. Keep this accessor
    // for persisted settings migration and diagnostics.
    return await _storage.read(key: _llmModeKey) ?? 'gemini_cloud';
  }

  Future<void> setLlmMode(String mode) async {
    await _storage.write(key: _llmModeKey, value: mode);
  }

  Future<void> saveGeminiKey(String key) async {
    await _storage.write(key: _geminiKey, value: key);
    await invalidateGeminiVerification();
  }

  Future<void> saveGeminiModel(String model) async {
    await _storage.write(key: _geminiModelKey, value: model);
    await invalidateGeminiVerification();
  }

  Future<void> setGeminiVerified(bool verified) async {
    await _storage.write(
      key: _geminiVerifiedKey,
      value: verified ? 'true' : 'false',
    );
  }

  Future<void> invalidateGeminiVerification() async {
    await setGeminiVerified(false);
  }

  Future<void> saveVerifiedGeminiConfiguration({
    required String key,
    required String model,
    required bool verified,
  }) async {
    await _storage.write(key: _geminiKey, value: key);
    await _storage.write(key: _geminiModelKey, value: model);
    await setGeminiVerified(verified);
  }

  /// Menghitung waktu reset tengah malam berikutnya di Pacific Time (00:00 PT / Google AI Studio cycle).
  static DateTime computeNextPacificMidnight([DateTime? now]) {
    final current = (now ?? DateTime.now()).toUtc();
    final isDst = isPacificDst(current);
    final pacificOffsetHours = isDst ? -7 : -8;

    // Konversi UTC saat ini ke waktu lokal Pacific
    final pacificNow = current.add(Duration(hours: pacificOffsetHours));

    // Tengah malam berikutnya di Pacific (00:00:00 hari esok)
    final nextMidnightPacific = DateTime.utc(
      pacificNow.year,
      pacificNow.month,
      pacificNow.day + 1,
      0,
      0,
      0,
    );

    // Kembalikan ke format UTC
    return nextMidnightPacific.subtract(Duration(hours: pacificOffsetHours));
  }

  /// Menentukan apakah waktu UTC saat ini berada dalam periode Daylight Saving Time (PDT, UTC-7).
  static bool isPacificDst(DateTime utc) {
    final year = utc.year;
    // Minggu ke-2 bulan Maret pukul 02:00 PST (10:00 UTC)
    final march1 = DateTime.utc(year, 3, 1);
    final firstSunMarch = 1 + ((7 - march1.weekday) % 7);
    final secondSunMarch = firstSunMarch + 7;
    final dstStart = DateTime.utc(year, 3, secondSunMarch, 10);

    // Minggu ke-1 bulan November pukul 02:00 PDT (09:00 UTC)
    final nov1 = DateTime.utc(year, 11, 1);
    final firstSunNov = 1 + ((7 - nov1.weekday) % 7);
    final dstEnd = DateTime.utc(year, 11, firstSunNov, 9);

    return utc.isAfter(dstStart) && utc.isBefore(dstEnd);
  }

  /// Membaca snapshot kuota harian Gemini Free Tier beserta sisa waktu sampai reset Pacific Time berikutnya.
  Future<GeminiDailyQuotaSnapshot> getGeminiDailyQuota([DateTime? now]) async {
    final currentTime = (now ?? DateTime.now()).toUtc();
    final nextReset = computeNextPacificMidnight(currentTime);
    final timeUntil = nextReset.difference(currentTime);

    final storedResetIso = await _storage.read(key: _geminiQuotaCycleResetKey);
    final storedReset =
        storedResetIso != null ? DateTime.tryParse(storedResetIso) : null;

    final isNewCycle = storedReset == null ||
        currentTime.isAfter(storedReset) ||
        storedReset.difference(nextReset).abs() > const Duration(minutes: 1);

    if (isNewCycle) {
      await _storage.write(
        key: _geminiQuotaCycleResetKey,
        value: nextReset.toIso8601String(),
      );
      await _storage.write(key: _geminiDailyRequestsKey, value: '0');
      await _storage.write(key: _geminiDailyPromptTokensKey, value: '0');
      await _storage.write(key: _geminiDailyCandidateTokensKey, value: '0');
      await _storage.write(key: _geminiDailyTotalTokensKey, value: '0');

      return GeminiDailyQuotaSnapshot(
        requestsUsed: 0,
        requestsLimit: 1500,
        promptTokens: 0,
        candidateTokens: 0,
        totalTokens: 0,
        nextResetTime: nextReset.toLocal(),
        timeUntilReset: timeUntil.isNegative ? Duration.zero : timeUntil,
        lastRequestAt: null,
      );
    }

    final reqUsed =
        int.tryParse(await _storage.read(key: _geminiDailyRequestsKey) ?? '0') ??
            0;
    final promptTok = int.tryParse(
          await _storage.read(key: _geminiDailyPromptTokensKey) ?? '0',
        ) ??
        0;
    final candTok = int.tryParse(
          await _storage.read(key: _geminiDailyCandidateTokensKey) ?? '0',
        ) ??
        0;
    final totalTok = int.tryParse(
          await _storage.read(key: _geminiDailyTotalTokensKey) ?? '0',
        ) ??
        0;
    final lastReqStr = await _storage.read(key: _geminiUsageAtKey);
    final lastReq =
        lastReqStr != null ? DateTime.tryParse(lastReqStr)?.toLocal() : null;

    return GeminiDailyQuotaSnapshot(
      requestsUsed: reqUsed,
      requestsLimit: 1500,
      promptTokens: promptTok,
      candidateTokens: candTok,
      totalTokens: totalTok,
      nextResetTime: nextReset.toLocal(),
      timeUntilReset: timeUntil.isNegative ? Duration.zero : timeUntil,
      lastRequestAt: lastReq,
    );
  }

  /// Catat penambahan kuota harian lokal (jumlah request & konsumsi token).
  Future<void> recordGeminiDailyUsage({
    int? promptTokens,
    int? candidateTokens,
    int? totalTokens,
    DateTime? now,
  }) async {
    final currentTime = (now ?? DateTime.now()).toUtc();
    final nextReset = computeNextPacificMidnight(currentTime);

    final storedResetIso = await _storage.read(key: _geminiQuotaCycleResetKey);
    final storedReset =
        storedResetIso != null ? DateTime.tryParse(storedResetIso) : null;

    final isNewCycle = storedReset == null ||
        currentTime.isAfter(storedReset) ||
        storedReset.difference(nextReset).abs() > const Duration(minutes: 1);

    var prevReq = 0;
    var prevPrompt = 0;
    var prevCand = 0;
    var prevTotal = 0;

    if (!isNewCycle) {
      prevReq = int.tryParse(
            await _storage.read(key: _geminiDailyRequestsKey) ?? '0',
          ) ??
          0;
      prevPrompt = int.tryParse(
            await _storage.read(key: _geminiDailyPromptTokensKey) ?? '0',
          ) ??
          0;
      prevCand = int.tryParse(
            await _storage.read(key: _geminiDailyCandidateTokensKey) ?? '0',
          ) ??
          0;
      prevTotal = int.tryParse(
            await _storage.read(key: _geminiDailyTotalTokensKey) ?? '0',
          ) ??
          0;
    }

    await _storage.write(
      key: _geminiQuotaCycleResetKey,
      value: nextReset.toIso8601String(),
    );
    await _storage.write(
      key: _geminiDailyRequestsKey,
      value: '${prevReq + 1}',
    );
    await _storage.write(
      key: _geminiDailyPromptTokensKey,
      value: '${prevPrompt + (promptTokens ?? 0)}',
    );
    await _storage.write(
      key: _geminiDailyCandidateTokensKey,
      value: '${prevCand + (candidateTokens ?? 0)}',
    );
    await _storage.write(
      key: _geminiDailyTotalTokensKey,
      value: '${prevTotal + (totalTokens ?? 0)}',
    );
  }

  Future<void> saveGeminiUsage({
    required String code,
    required String model,
    required bool ok,
    required DateTime at,
    int? httpStatus,
    Duration? latency,
    GeminiUsageMetadata? usageMetadata,
  }) async {
    await _storage.write(key: _geminiUsageCodeKey, value: code);
    await _storage.write(key: _geminiUsageModelKey, value: model);
    await _storage.write(key: _geminiUsageOkKey, value: ok ? 'true' : 'false');
    await _storage.write(key: _geminiUsageAtKey, value: at.toIso8601String());
    if (httpStatus == null) {
      await _storage.delete(key: _geminiUsageHttpKey);
    } else {
      await _storage.write(
        key: _geminiUsageHttpKey,
        value: httpStatus.toString(),
      );
    }
    if (latency == null) {
      await _storage.delete(key: _geminiUsageLatencyKey);
    } else {
      await _storage.write(
        key: _geminiUsageLatencyKey,
        value: latency.inMilliseconds.toString(),
      );
    }
    if (usageMetadata != null) {
      await _storage.write(
        key: _geminiUsagePromptTokensKey,
        value: usageMetadata.promptTokenCount.toString(),
      );
      await _storage.write(
        key: _geminiUsageCandidateTokensKey,
        value: usageMetadata.candidatesTokenCount.toString(),
      );
      await _storage.write(
        key: _geminiUsageTotalTokensKey,
        value: usageMetadata.totalTokenCount.toString(),
      );
    }
    await recordGeminiDailyUsage(
      promptTokens: usageMetadata?.promptTokenCount,
      candidateTokens: usageMetadata?.candidatesTokenCount,
      totalTokens: usageMetadata?.totalTokenCount,
      now: at,
    );
  }

  Future<String> getUserId() async {
    final stored = await _storage.read(key: _userKey);
    if (stored != null) return stored;
    final newId = const Uuid().v4();
    await _storage.write(key: _userKey, value: newId);
    return newId;
  }

  Future<void> save(String url, String anonKey) async {
    await _storage.write(key: _urlKey, value: url);
    await _storage.write(key: _anonKey, value: anonKey);
  }

  Future<void> clear() async {
    await _storage.delete(key: _urlKey);
    await _storage.delete(key: _anonKey);
    await _storage.delete(key: _userKey);
  }
}
