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
        return _financialSnapshot.buildCurrentMonthTransactionDigest(
          householdId: householdId,
          now: now,
        );
      default:
        throw StateError('Capability baca tidak diizinkan.');
    }
  }
}
