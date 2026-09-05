import '../../data/cash_flow_profile_repository.dart';
import '../entities/cash_flow_profile_models.dart';

/// Hasil evaluasi wawancara proaktif status usaha / tani.
class ProactiveCheckInPrompt {
  const ProactiveCheckInPrompt({
    required this.profile,
    required this.greetingMessage,
    required this.suggestedQuestions,
  });

  final CashFlowProfile profile;
  final String greetingMessage;
  final List<String> suggestedQuestions;
}

/// Service untuk memicu wawancara proaktif status usaha dan pertanian (Pilar 2).
///
/// Bertanya kondisi kebun/usaha secara ramah di obrolan Asisten agar
/// estimasi panen dan kebutuhan modal selalu akurat dan terbarui.
class ProactiveCashFlowCheckInService {
  const ProactiveCashFlowCheckInService(this._repository);

  final CashFlowProfileRepository _repository;

  /// Memeriksa apakah ada profil kas aktif yang memerlukan wawancara check-in proaktif.
  Future<ProactiveCheckInPrompt?> evaluateCheckIn(String householdId) async {
    final profiles = await _repository.getAllProfiles(householdId);
    final active = profiles.where((p) => p.isActive).toList();
    if (active.isEmpty) return null;

    // Prioritaskan profil pertanian atau bisnis
    final target = active.firstWhere(
      (p) => p.profileType == CashFlowProfileType.agriculture,
      orElse: () => active.first,
    );

    if (target.profileType == CashFlowProfileType.agriculture) {
      final days = target.daysRemaining;
      final daysText = days > 0 ? '~ $days hari lagi estimasi panen' : 'sudah mendekati waktu panen';
      final msg = '🌾 **Wawancara Status Tani & Kebun**\n\n'
          'Siklus **${target.name}** (${target.commodityOrBusinessType}) saat ini berada pada **${target.phaseLabel}** ($daysText).\n\n'
          'Bagaimana perkembangan tanaman minggu ini? Apakah ada belanja pupuk/bibit tak terduga, atau ada pembaruan tanggal panen?';

      final suggestions = [
        'Kira-kira berapa hari lagi panen ${target.commodityOrBusinessType}?',
        'Catat belanja pupuk dan bibit untuk ${target.name}',
        'Berapa sisa ketahanan kas (runway) sampai panen?',
      ];

      return ProactiveCheckInPrompt(
        profile: target,
        greetingMessage: msg,
        suggestedQuestions: suggestions,
      );
    } else if (target.profileType == CashFlowProfileType.business) {
      final msg = '💼 **Wawancara Status Usaha & Operasional**\n\n'
          'Siklus modal kerja **${target.name}** (${target.commodityOrBusinessType}) sedang aktif berjalan.\n\n'
          'Bagaimana perputaran omzet dan belanja operasional minggu ini? Apakah ada tagihan pelanggan yang sudah cair?';

      final suggestions = [
        'Berapa sisa modal kerja usaha saat ini?',
        'Catat penerimaan kas masuk dari usaha',
        'Bagaimana posisi arus kas usaha minggu ini?',
      ];

      return ProactiveCheckInPrompt(
        profile: target,
        greetingMessage: msg,
        suggestedQuestions: suggestions,
      );
    }

    final msg = '📊 **Wawancara Arus Kas**\n\n'
        'Siklus keuangan **${target.name}** sedang aktif.\n\n'
        'Apakah ada pemasukan atau pengeluaran penting yang ingin diselaraskan hari ini?';

    return ProactiveCheckInPrompt(
      profile: target,
      greetingMessage: msg,
      suggestedQuestions: const [
        'Tampilkan ringkasan kas masuk dan keluar minggu ini',
        'Kategori apa yang paling banyak menyerap anggaran?',
        'Berapa sisa kas likuid yang aman dibelanjakan?',
      ],
    );
  }
}
