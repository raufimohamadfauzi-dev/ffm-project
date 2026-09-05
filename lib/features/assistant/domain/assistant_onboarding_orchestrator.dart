import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/database/app_context.dart';
import '../../../core/database/app_database.dart';
import '../data/onboarding_preference.dart';

enum OnboardingStep {
  notStarted,
  askFamilyName,
  askAccounts,
  completed,
}

/// Tahapan kesiapan data pengguna untuk Onboarding Adaptif Berjenjang.
enum AdaptiveOnboardingStage {
  /// Kunjungan ke-1: Data profil / rekening masih kosong.
  emptyData,

  /// Kunjungan ke-2: Rekening sudah dibuat, namun belum ada transaksi tercatat.
  needsFirstTransaction,

  /// Kunjungan ke-3+: Transaksi sudah mulai tercatat, namun belum ada pagu anggaran.
  needsBudget,

  /// Lulus: Fondasi dasar (rekening, transaksi, anggaran) sudah terpenuhi.
  graduated,
}

class OnboardingTurnResponse {
  const OnboardingTurnResponse({
    required this.message,
    required this.suggestions,
    required this.isCompleted,
    this.nextStep = OnboardingStep.notStarted,
    this.stage = AdaptiveOnboardingStage.emptyData,
  });

  final String message;
  final List<String> suggestions;
  final bool isCompleted;
  final OnboardingStep nextStep;
  final AdaptiveOnboardingStage stage;
}

/// Orchestrator onboarding interaktif berbasis aturan di dalam Chatbot Asisten.
/// Mendukung alur multi-visit adaptif dari data kosong hingga mahir.
/// 100% lokal, deterministik, instan (0 latensi), dan offline-ready.
class AssistantOnboardingOrchestrator {
  AssistantOnboardingOrchestrator({
    required this.database,
    this.householdId = AppContext.householdId,
    SharedPreferences? preferences,
  }) : _prefs = preferences;

  final AppDatabase database;
  final String householdId;
  SharedPreferences? _prefs;

  OnboardingStep _currentStep = OnboardingStep.notStarted;
  String _familyName = 'Keluarga Kami';

  OnboardingStep get currentStep => _currentStep;
  bool get isOnboardingActive =>
      _currentStep == OnboardingStep.askFamilyName ||
      _currentStep == OnboardingStep.askAccounts;

  Future<SharedPreferences> _getPrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Memeriksa apakah pengguna memerlukan alur percakapan onboarding setup awal (Tahap 1).
  Future<bool> checkNeedsOnboarding() async {
    final completed = await OnboardingPreference.isCompleted();
    if (completed) return false;

    // Periksa apakah sudah ada akun yang dibuat
    try {
      final existingAccounts = await (database.select(database.accounts)
            ..where((t) => t.householdId.equals(householdId)))
          .get();
      if (existingAccounts.isNotEmpty) {
        await OnboardingPreference.setCompleted(true);
        return false;
      }
    } catch (_) {}

    return true;
  }

  /// Mengevaluasi tahapan adaptif saat ini berdasarkan kelengkapan data aktual di database.
  Future<AdaptiveOnboardingStage> evaluateAdaptiveStage() async {
    try {
      // 1. Cek rekening aktif
      final accounts = await (database.select(database.accounts)
            ..where((t) =>
                t.householdId.equals(householdId) &
                t.isActive.equals(true) &
                t.isArchived.equals(false)))
          .get();
      if (accounts.isEmpty) {
        return AdaptiveOnboardingStage.emptyData;
      }

      // 2. Cek apakah sudah ada transaksi tercatat
      final transactions = await (database.select(database.transactions)
            ..where((t) =>
                t.householdId.equals(householdId) &
                t.isDeleted.equals(false) &
                t.isArchived.equals(false)))
          .get();
      if (transactions.isEmpty) {
        return AdaptiveOnboardingStage.needsFirstTransaction;
      }

      // 3. Cek apakah sudah ada pagu anggaran dibuat
      final budgets = await (database.select(database.envelopeBudgets)
            ..where((b) =>
                b.householdId.equals(householdId) &
                b.isActive.equals(true)))
          .get();
      if (budgets.isEmpty) {
        return AdaptiveOnboardingStage.needsBudget;
      }

      return AdaptiveOnboardingStage.graduated;
    } catch (_) {
      return AdaptiveOnboardingStage.graduated;
    }
  }

  /// Memeriksa apakah ada sapaan bimbingan adaptif yang perlu disajikan saat membuka Asisten.
  /// Mengembalikan null jika pengguna sudah lulus atau tidak memerlukan bimbingan hari ini.
  Future<OnboardingTurnResponse?> checkAdaptiveGreeting() async {
    final stage = await evaluateAdaptiveStage();
    if (stage == AdaptiveOnboardingStage.graduated) return null;

    final prefs = await _getPrefs();
    final family = await _fetchFamilyName();

    switch (stage) {
      case AdaptiveOnboardingStage.emptyData:
        final needsInitial = await checkNeedsOnboarding();
        if (needsInitial) return start();
        return null;

      case AdaptiveOnboardingStage.needsFirstTransaction:
        final key = 'ffm_adaptive_onboarding_tx_guided_$householdId';
        final alreadyGuided = prefs.getBool(key) ?? false;
        if (alreadyGuided) return null;

        await prefs.setBool(key, true);
        return OnboardingTurnResponse(
          message:
              'Halo $family! 💳 Rekening keuangan keluarga sudah berhasil disiapkan.\n\n'
              'Langkah berikutnya, mari coba catat transaksi pertama Anda (misal: belanja harian, beli bensin, atau tempel kartu e-money jika HP mendukung NFC).',
          suggestions: const [
            'Beli bensin 25rb',
            'Belanja pasar 50rb',
            'Gaji bulanan 5jt',
          ],
          isCompleted: false,
          nextStep: OnboardingStep.completed,
          stage: AdaptiveOnboardingStage.needsFirstTransaction,
        );

      case AdaptiveOnboardingStage.needsBudget:
        final key = 'ffm_adaptive_onboarding_budget_guided_$householdId';
        final alreadyGuided = prefs.getBool(key) ?? false;
        if (alreadyGuided) return null;

        await prefs.setBool(key, true);
        return OnboardingTurnResponse(
          message:
              'Halo $family! 📊 Catatan transaksi keluarga sudah mulai rapi.\n\n'
              'Agar pengeluaran tidak bocor halus, langkah terbaik selanjutnya adalah menentukan batas pagu anggaran bulanan untuk kebutuhan utama (misal: Makan & Belanja Dapur). Mau buat anggaran sekarang?',
          suggestions: const [
            'Buat anggaran makan 1.5jt',
            'Buat anggaran belanja dapur 1jt',
            'Cek ringkasan keuangan',
          ],
          isCompleted: false,
          nextStep: OnboardingStep.completed,
          stage: AdaptiveOnboardingStage.needsBudget,
        );

      case AdaptiveOnboardingStage.graduated:
        return null;
    }
  }

  Future<String> _fetchFamilyName() async {
    try {
      final household = await (database.select(database.households)
            ..where((t) => t.id.equals(householdId)))
          .getSingleOrNull();
      if (household != null && household.name.trim().isNotEmpty) {
        return household.name.trim();
      }
    } catch (_) {}
    return _familyName;
  }

  /// Memulai alur onboarding dan mengembalikan sapaan pembuka asisten.
  OnboardingTurnResponse start() {
    _currentStep = OnboardingStep.askFamilyName;
    return const OnboardingTurnResponse(
      message:
          'Halo! 👋 Selamat datang di FFM (Family Finance Manager).\n\n'
          'Saya Asisten Keuangan Keluarga Anda. Sebelum mulai, boleh tahu nama panggilan keluarga Anda? (contoh: *Keluarga Budi*, *Keluarga Kami*)',
      suggestions: ['Keluarga Kami', 'Keluarga Bahagia', 'Keluarga Berkah'],
      isCompleted: false,
      nextStep: OnboardingStep.askFamilyName,
      stage: AdaptiveOnboardingStage.emptyData,
    );
  }

  /// Memproses respon pengguna di setiap langkah onboarding.
  Future<OnboardingTurnResponse> processInput(String rawInput) async {
    final text = rawInput.trim();
    if (_currentStep == OnboardingStep.askFamilyName) {
      _familyName = text.isNotEmpty ? text : 'Keluarga Kami';
      // Simpan nama keluarga ke database lokal
      try {
        await (database.update(database.households)
              ..where((t) => t.id.equals(householdId)))
            .write(
          HouseholdsCompanion(
            name: Value(_familyName),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } catch (_) {}

      _currentStep = OnboardingStep.askAccounts;
      return OnboardingTurnResponse(
        message:
            'Senang berkenalan dengan $_familyName! 🏡\n\n'
            'Sekarang, mari siapkan akun keuangan awal untuk mencatat keluar-masuk uang. Biasanya keluarga memakai akun apa saja?',
        suggestions: const [
          'Dompet Tunai & Bank BCA',
          'Dompet Tunai & Bank Mandiri',
          'Dompet Tunai & Bank BRI',
          'Dompet Tunai Saja',
        ],
        isCompleted: false,
        nextStep: OnboardingStep.askAccounts,
        stage: AdaptiveOnboardingStage.emptyData,
      );
    } else if (_currentStep == OnboardingStep.askAccounts) {
      await _createAccountsFromInput(text);
      _currentStep = OnboardingStep.completed;
      await OnboardingPreference.setCompleted(true);

      return const OnboardingTurnResponse(
        message:
            'Akun keuangan sudah siap! 💳\n\n'
            'Kategori kebutuhan harian keluarga (Belanja dapur, Makan, Listrik, BBM) juga sudah otomatis aktif.\n\n'
            'Semuanya sudah beres! Anda bisa langsung minta saya mencatat transaksi, cek saldo, atau ubah tampilan aplikasi (misal: *"Ubah ke mode gelap"*). Mau mulai apa hari ini?',
        suggestions: [
          'Catat pengeluaran pertama',
          'Ubah ke mode gelap 🌙',
          'Cek ringkasan keuangan',
        ],
        isCompleted: true,
        nextStep: OnboardingStep.completed,
        stage: AdaptiveOnboardingStage.needsFirstTransaction,
      );
    }

    return const OnboardingTurnResponse(
      message: 'Onboarding sudah selesai. Ada yang bisa saya bantu?',
      suggestions: [],
      isCompleted: true,
      nextStep: OnboardingStep.completed,
      stage: AdaptiveOnboardingStage.graduated,
    );
  }

  /// Membuat akun-akun awal secara deterministik berdasarkan pilihan pengguna.
  Future<void> _createAccountsFromInput(String input) async {
    final clean = input.toLowerCase();
    final now = DateTime.now();

    final accountsToCreate = <(String id, String name, String type)>[];

    // Selalu buat Dompet Tunai / Kas
    accountsToCreate.add(('acc-cash-1', 'Dompet Tunai', 'cash'));

    // Deteksi bank/e-wallet dari teks
    if (clean.contains('bca')) {
      accountsToCreate.add(('acc-bank-bca', 'Bank BCA', 'bank'));
    } else if (clean.contains('mandiri')) {
      accountsToCreate.add(('acc-bank-mandiri', 'Bank Mandiri', 'bank'));
    } else if (clean.contains('bri')) {
      accountsToCreate.add(('acc-bank-bri', 'Bank BRI', 'bank'));
    } else if (clean.contains('bni')) {
      accountsToCreate.add(('acc-bank-bni', 'Bank BNI', 'bank'));
    } else if (clean.contains('jago')) {
      accountsToCreate.add(('acc-bank-jago', 'Bank Jago', 'bank'));
    } else if (clean.contains('seabank')) {
      accountsToCreate.add(('acc-bank-seabank', 'SeaBank', 'bank'));
    } else if (!clean.contains('saja')) {
      // Default jika memilih bank tapi tidak sebut nama spesifik
      accountsToCreate.add(('acc-bank-1', 'Rekening Bank', 'bank'));
    }

    if (clean.contains('gopay') || clean.contains('go-pay')) {
      accountsToCreate.add(('acc-ewallet-gopay', 'GoPay', 'ewallet'));
    }
    if (clean.contains('ovo')) {
      accountsToCreate.add(('acc-ewallet-ovo', 'OVO', 'ewallet'));
    }
    if (clean.contains('dana')) {
      accountsToCreate.add(('acc-ewallet-dana', 'DANA', 'ewallet'));
    }

    for (final (id, name, type) in accountsToCreate) {
      await database.into(database.accounts).insertOnConflictUpdate(
        AccountsCompanion.insert(
          id: id,
          householdId: householdId,
          name: name,
          type: type,
          openingBalance: const Value(0),
          isActive: const Value(true),
          isArchived: const Value(false),
          createdAt: now,
        ),
      );
    }
  }
}
