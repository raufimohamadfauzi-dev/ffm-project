import 'ffm_assistant_financial_snapshot_service.dart';
import 'ffm_assistant_proposal_json_service.dart';

/// Kebijakan resmi dan tersentralisasi untuk seluruh capability baca Gemini Cloud.
/// Menyatukan allowlist, validasi rentang tanggal, penjelasan privasi, dan kontrak bounded.
class FfmGeminiReadCapabilityPolicy {
  const FfmGeminiReadCapabilityPolicy._();

  static const String policyName = 'ffm-gemini-bounded-read-v1';

  static const Set<String> allowedCapabilityIds = <String>{
    'read.summary',
    'read.transactions',
    'read.hijriDate',
    'read.goals',
    'read.liabilities',
    'read.debts',
    'read.receivables',
    'read.receivable',
    'read.activity',
    'read.activities',
    'read.reminders',
    'read.reminder',
    'read.assets',
    'read.asset',
    'read.budget',
    'read.budgets',
  };

  static const List<String> canonicalToolChoices = <String>[
    'read.summary',
    'read.transactions',
    'read.goals',
    'read.liabilities',
    'read.receivables',
    'read.activities',
    'read.reminders',
    'read.assets',
    'read.budget',
    'read.hijriDate',
  ];

  static String get formattedToolChoices =>
      canonicalToolChoices.map((c) => '`$c`').join(', ');

  static const String privacyContractExplanation =
      'Data yang dibaca Gemini dibatasi ketat: hanya agregat ringkas bulan berjalan atau maksimal 8 transaksi bertanggal tanpa nomor rekening, nama merchant sensitif, catatan pribadi, atau pengenal unik database.';

  static bool isAllowed(String capabilityId) =>
      allowedCapabilityIds.contains(capabilityId.trim());
}

/// Menjalankan capability Gemini yang telah tervalidasi dan bersifat read-only.
///
/// Service ini sengaja kecil: ia tidak mengetahui chat, Gemini API, repository
/// mutation, atau executor write. Menambah capability baru wajib menambahkan
/// validator allowlist dan evidence bounded yang setara.
class FfmGeminiReadCapabilityService {
  const FfmGeminiReadCapabilityService(this._financialSnapshot);

  final FfmAssistantFinancialSnapshotService _financialSnapshot;

  Future<String> execute(
    FfmAssistantReadCapabilityRequest request, {
    required String householdId,
    required DateTime now,
  }) async {
    switch (request.capabilityId) {
      case 'read.summary':
        final evidence = await _financialSnapshot.readCurrentMonth(
          householdId: householdId,
          now: now,
        );
        return _financialSnapshot.buildBoundedPrompt(evidence);
      case 'read.transactions':
        _validateTransactionRange(request, now);
        return _financialSnapshot.buildCurrentMonthTransactionDigest(
          householdId: householdId,
          now: now,
          startDate: request.startDate,
          endDate: request.endDate,
        );
      case 'read.hijriDate':
        return await _financialSnapshot.buildHijriContext(
          householdId: householdId,
          now: now,
        );
      case 'read.goals':
        return await _financialSnapshot.buildGoalsDigest(
          householdId: householdId,
        );
      case 'read.liabilities':
      case 'read.debts':
        return await _financialSnapshot.buildLiabilitiesDigest(
          householdId: householdId,
        );
      case 'read.receivables':
      case 'read.receivable':
        return await _financialSnapshot.buildReceivablesDigest(
          householdId: householdId,
        );
      case 'read.activity':
      case 'read.activities':
        return await _financialSnapshot.buildActivitiesDigest(
          householdId: householdId,
        );
      case 'read.reminders':
      case 'read.reminder':
        return await _financialSnapshot.buildRemindersDigest(
          householdId: householdId,
        );
      case 'read.assets':
      case 'read.asset':
        return await _financialSnapshot.buildAssetsDigest(
          householdId: householdId,
        );
      case 'read.budget':
      case 'read.budgets':
        return await _financialSnapshot.buildBudgetDigest(
          householdId: householdId,
          now: now,
        );
      default:
        throw StateError('Capability baca tidak diizinkan.');
    }
  }

  void _validateTransactionRange(
    FfmAssistantReadCapabilityRequest request,
    DateTime now,
  ) {
    final startDate = request.startDate;
    final endDate = request.endDate;
    if (startDate == null && endDate == null) return;
    if (startDate == null || endDate == null) {
      throw StateError('Rentang tanggal transaksi tidak lengkap.');
    }
    if (endDate.isBefore(startDate) ||
        endDate.difference(startDate).inDays > 13) {
      throw StateError('Rentang transaksi tidak valid atau melebihi 14 hari.');
    }
    final monthStart = DateTime(now.year, now.month);
    final monthEnd = DateTime(now.year, now.month + 1);
    if (startDate.isBefore(monthStart) || !endDate.isBefore(monthEnd)) {
      throw StateError('Rentang transaksi harus berada dalam bulan berjalan.');
    }
  }
}
