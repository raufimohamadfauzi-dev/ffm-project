import 'ffm_assistant_financial_snapshot_service.dart';
import 'ffm_assistant_proposal_json_service.dart';

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
