import 'package:flutter/foundation.dart';

import '../../../core/database/app_context.dart';
import 'ffm_assistant_autonomy_trigger_service.dart';

/// Service untuk mengintegrasikan LLM dengan Telegram reporting.
/// Service ini memanggil LLM untuk generate laporan mingguan dan mengirim
/// ke Telegram via existing infrastructure.
class FfmAssistantTelegramLlmService {
  FfmAssistantTelegramLlmService({
    required this.triggerService,
  });

  final FfmAssistantAutonomyTriggerService triggerService;

  /// Trigger LLM job untuk generate laporan mingguan ke Telegram.
  ///
  /// [reportType] - Tipe laporan (weekly, monthly, dll)
  /// [periodStart] - Tanggal mulai periode laporan
  /// [periodEnd] - Tanggal akhir periode laporan
  Future<bool> generateWeeklyReport({
    String reportType = 'weekly',
    DateTime? periodStart,
    DateTime? periodEnd,
  }) async {
    final householdId = AppContext.householdId;

    // Construct user prompt untuk LLM
    final userPrompt = _buildWeeklyReportPrompt(
      reportType: reportType,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );

    // Construct context tambahan
    final context = _buildWeeklyReportContext(
      reportType: reportType,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );

    // Emit LLM job trigger
    final success = await triggerService.emitLlmJob(
      jobType: 'telegram_report',
      userPrompt: userPrompt,
      context: context,
      householdId: householdId,
      triggerId: 'telegram_weekly_report_${DateTime.now().millisecondsSinceEpoch}',
    );

    if (success) {
      debugPrint('Telegram weekly report LLM job triggered successfully');
    } else {
      debugPrint('Failed to trigger Telegram weekly report LLM job');
    }

    return success;
  }

  /// Build user prompt untuk weekly report.
  String _buildWeeklyReportPrompt({
    required String reportType,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) {
    final periodInfo = _formatPeriodInfo(periodStart, periodEnd);
    return '''
Generate laporan keuangan mingguan untuk Telegram.

Tipe laporan: $reportType
Periode: $periodInfo

Laporan harus mencakup:
1. Ringkasan pemasukan dan pengeluaran
2. Kategori pengeluaran terbesar
3. Transaksi anomali (jika ada)
4. Status budget (over/under)
5. Rekomendasi hemat

Format output: JSON dengan struktur:
{
  "action": "sendTelegramReport",
  "parameters": {
    "reportType": "$reportType",
    "content": "isi laporan dalam format plain text untuk Telegram"
  }
}
''';
  }

  /// Build context tambahan untuk weekly report.
  String _buildWeeklyReportContext({
    required String reportType,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) {
    final periodInfo = _formatPeriodInfo(periodStart, periodEnd);
    return '''
Report Context:
- Report type: $reportType
- Period: $periodInfo
- Target: Telegram delivery
- Format: Plain text for Telegram (no Markdown bolding)
- Language: Indonesian
- Tone: Professional yet friendly
''';
  }

  /// Format period info untuk prompt.
  String _formatPeriodInfo(DateTime? start, DateTime? end) {
    if (start != null && end != null) {
      return '${_formatDate(start)} - ${_formatDate(end)}';
    } else if (start != null) {
      return 'sejak ${_formatDate(start)}';
    } else if (end != null) {
      return 'sampai ${_formatDate(end)}';
    } else {
      return 'minggu ini';
    }
  }

  /// Format date untuk prompt.
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
