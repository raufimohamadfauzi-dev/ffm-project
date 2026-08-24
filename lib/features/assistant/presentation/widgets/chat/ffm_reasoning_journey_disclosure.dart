import 'package:flutter/material.dart';

import '../../../domain/ffm_assistant_models.dart';

/// Akordeon proses berpikir transparan (Thinking & Tool Call Timeline) ala Claude.
/// Menampilkan pohon tahapan kerja vertikal, sumber tabel SQLite yang diakses,
/// mesin pemroses (SLM vs Rule Engine), serta durasi pengerjaan secara transparan.
class FfmReasoningJourneyDisclosure extends StatefulWidget {
  const FfmReasoningJourneyDisclosure({
    super.key,
    this.intent,
    this.isSlm = false,
    this.elapsedDuration = const Duration(milliseconds: 320),
  });

  final FfmAssistantIntent? intent;
  final bool isSlm;
  final Duration elapsedDuration;

  @override
  State<FfmReasoningJourneyDisclosure> createState() =>
      _FfmReasoningJourneyDisclosureState();
}

class _FfmReasoningJourneyDisclosureState
    extends State<FfmReasoningJourneyDisclosure> {
  var _expanded = false;

  (String engine, String dataAccess, List<_ReasoningStep> steps) _deriveDetails(
    FfmAssistantIntent? intent,
    bool isSlm,
  ) {
    if (isSlm) {
      return (
        'AI Lokal Qwen2-VL 2B (Vision & NLP On-Device)',
        'Model GGUF & Projector Vision (Storage internal)',
        const [
          _ReasoningStep(
            icon: Icons.image_search_outlined,
            title: 'Mendeteksi input multimodal / foto struk',
            detail: 'Memindai teks dan angka pada gambar secara offline',
          ),
          _ReasoningStep(
            icon: Icons.code_rounded,
            title: 'Ekstraksi entitas transaksi (Nama toko, total, tanggal)',
            detail: 'Mengurai struktur JSON draf dari representasi visual',
          ),
          _ReasoningStep(
            icon: Icons.edit_note_rounded,
            title: 'Menyiapkan proposal draf transaksi',
            detail: 'Data siap diverifikasi oleh pengguna sebelum disimpan',
          ),
        ],
      );
    }

    if (intent == null) {
      return (
        'Mesin Aturan Cepat & Basis Pengetahuan FFM',
        'Katalog Fitur & Konteks Halaman Aktif',
        const [
          _ReasoningStep(
            icon: Icons.terminal_rounded,
            title: 'Menganalisis kalimat instruksi pengguna',
            detail: 'Mencocokkan pola bahasa alami dan parameter kueri',
          ),
          _ReasoningStep(
            icon: Icons.menu_book_outlined,
            title: 'Membaca basis pengetahuan & bantuan fitur',
            detail: 'Mengambil panduan penggunaan offline',
          ),
          _ReasoningStep(
            icon: Icons.check_circle_outline,
            title: 'Menyusun respons edukatif yang informatif',
            detail: 'Memberikan penjelasan lengkap dan rekomendasi berikutnya',
          ),
        ],
      );
    }

    return switch (intent.type) {
      FfmAssistantIntentType.createIncome ||
      FfmAssistantIntentType.createExpense ||
      FfmAssistantIntentType.createTransfer => (
        'FfmTransactionActuator & BudgetGuard',
        'Tabel: transactions, accounts, categories, budgets',
        [
          const _ReasoningStep(
            icon: Icons.terminal_rounded,
            title: 'Ekstraksi entitas transaksi keuangan',
            detail: 'Mengekstrak nominal uang, nama akun asal/tujuan, dan kategori',
          ),
          const _ReasoningStep(
            icon: Icons.shield_outlined,
            title: 'Pemeriksaan limit anggaran & saldo rekening',
            detail: 'Memvalidasi batas pengeluaran (Budget Guard)',
          ),
          const _ReasoningStep(
            icon: Icons.edit_note_rounded,
            title: 'Penyusunan draf mutasi',
            detail: 'Draf aman siap dikonfirmasi (tidak disimpan diam-diam)',
          ),
        ],
      ),
      FfmAssistantIntentType.queryData ||
      FfmAssistantIntentType.weeklyAnalysis ||
      FfmAssistantIntentType.transactionStats => (
        'FfmTransactionSense & SQLite Aggregator',
        'Tabel: transactions, accounts (Kueri Agregasi SQLite)',
        [
          const _ReasoningStep(
            icon: Icons.storage_outlined,
            title: 'Membaca database transaksi & saldo rekening lokal',
            detail: 'Menjalankan kueri agregasi SQL pada SQLite lokal',
          ),
          const _ReasoningStep(
            icon: Icons.analytics_outlined,
            title: 'Kalkulasi statistik & arus kas (Cashflow)',
            detail: 'Menghitung total pengeluaran, pemasukan, dan saldo riil',
          ),
          const _ReasoningStep(
            icon: Icons.summarize_outlined,
            title: 'Menyajikan ringkasan keuangan yang akurat',
            detail: 'Angka bersumber langsung dari database perangkat',
          ),
        ],
      ),
      FfmAssistantIntentType.financialWarnings => (
        'SpendingPaceLogic & BudgetGuard',
        'Tabel: budgets, transactions, liabilities',
        [
          const _ReasoningStep(
            icon: Icons.speed_outlined,
            title: 'Analisis laju pengeluaran harian (Daily Burn Rate)',
            detail: 'Menghitung sisa hari vs sisa dana anggaran',
          ),
          const _ReasoningStep(
            icon: Icons.warning_amber_rounded,
            title: 'Evaluasi ambang batas peringatan',
            detail: 'Mendeteksi potensi overbudget pada kategori belanja',
          ),
          const _ReasoningStep(
            icon: Icons.tips_and_updates_outlined,
            title: 'Menyusun rekomendasi penyesuaian pengeluaran',
            detail: 'Tips actionable untuk menjaga kesehatan finansial',
          ),
        ],
      ),
      FfmAssistantIntentType.calendarQuery => (
        'FfmLocalCalendarSense & Hisab Engine',
        'Jam/Kalender HP & Algoritma Hisab Hijriah Offline',
        [
          const _ReasoningStep(
            icon: Icons.access_time_rounded,
            title: 'Sinkronisasi waktu lokal perangkat',
            detail: 'Membaca jam, hari, dan tanggal Masehi riil HP',
          ),
          const _ReasoningStep(
            icon: Icons.calendar_month_outlined,
            title: 'Kalkulasi penanggalan Hijriah (Hisab Lokal)',
            detail: 'Konversi hisab kalender Islam tanpa koneksi internet',
          ),
          const _ReasoningStep(
            icon: Icons.event_note_outlined,
            title: 'Penyajian rincian kalender & jadwal berkala',
            detail: 'Terhubung ke agenda dan pengingat transaksi',
          ),
        ],
      ),
      FfmAssistantIntentType.assistantIdentity => (
        'SelfDescriptionService & Creator Profile',
        'Metadata Profil Asisten & Developer (Rafi Sinkkat)',
        [
          const _ReasoningStep(
            icon: Icons.badge_outlined,
            title: 'Identifikasi peran Asisten FFM',
            detail: 'Pendamping keuangan keluarga offline-first',
          ),
          const _ReasoningStep(
            icon: Icons.person_outline_rounded,
            title: 'Pemuatan profil pembuat aplikasi',
            detail: 'Kreator: Rafi Sinkkat (YouTube & TikTok Clipsmart)',
          ),
          const _ReasoningStep(
            icon: Icons.verified_user_outlined,
            title: 'Penjelasan prinsip keamanan data & draft',
            detail: '100% On-Device, tidak ada pengiriman data ke server cloud',
          ),
        ],
      ),
      _ => (
        'Mesin Aturan & Basis Pengetahuan FFM',
        'Katalog Menu, Konteks Layar & Memori Sesi',
        [
          const _ReasoningStep(
            icon: Icons.terminal_rounded,
            title: 'Memproses maksud instruksi pengguna',
            detail: 'Pencocokan aturan deterministik & konteks percakapan',
          ),
          const _ReasoningStep(
            icon: Icons.folder_open_outlined,
            title: 'Memeriksa referensi katalog & pengetahuan lokal',
            detail: 'Mengecek ketersediaan data dan fungsi terkait',
          ),
          const _ReasoningStep(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Menghasilkan jawaban natural & saran lanjutan',
            detail: 'Menyediakan 3 rekomendasi pertanyaan pintar',
          ),
        ],
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSlm = widget.isSlm;
    final intent = widget.intent;

    final (engine, dataAccess, steps) = _deriveDetails(intent, isSlm);
    final seconds = (widget.elapsedDuration.inMilliseconds / 1000).toStringAsFixed(2);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1B2227)
            : const Color(0xFFEBF1F3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Claude-style Step Summary Header
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7.5),
              child: Row(
                children: [
                  Icon(
                    isSlm ? Icons.auto_awesome : Icons.terminal_rounded,
                    size: 15,
                    color: isSlm
                        ? const Color(0xFF00C5FF)
                        : (isDark ? const Color(0xFF90CAF9) : const Color(0xFF00727A)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Menjalankan ${steps.length} langkah (${seconds}s) • $engine',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: -0.1,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 17,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(
              height: 1,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.06),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Meta info banner (Tabel & Model)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF14191D)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.dns_outlined,
                          size: 13,
                          color: isDark ? const Color(0xFF80D8FF) : const Color(0xFF00727A),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            dataAccess,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Claude Vertical Timeline Steps
                  for (var i = 0; i < steps.length; i++)
                    _TimelineStepWidget(
                      step: steps[i],
                      index: i,
                      isLast: i == steps.length - 1,
                      isDark: isDark,
                      theme: theme,
                    ),
                  const SizedBox(height: 4),
                  // Footer security reassurance
                  Row(
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 12,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          '100% Offline • Disimpan di SQLite lokal perangkat',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReasoningStep {
  const _ReasoningStep({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;
}

class _TimelineStepWidget extends StatelessWidget {
  const _TimelineStepWidget({
    required this.step,
    required this.index,
    required this.isLast,
    required this.isDark,
    required this.theme,
  });

  final _ReasoningStep step;
  final int index;
  final bool isLast;
  final bool isDark;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Vertical Line & Dot
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? const Color(0xFF263238)
                      : const Color(0xFFCFD8DC),
                ),
                child: Center(
                  child: Icon(
                    step.icon,
                    size: 12,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.12),
                    margin: const EdgeInsets.symmetric(vertical: 2),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          // Step content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 6 : 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.title,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1.5),
                  Text(
                    step.detail,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.3,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
