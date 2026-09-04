import 'package:drift/drift.dart';

import '../../../core/database/app_context.dart';
import '../../../core/database/app_database.dart';
import '../data/onboarding_preference.dart';

enum OnboardingStep {
  notStarted,
  askFamilyName,
  askAccounts,
  completed,
}

class OnboardingTurnResponse {
  const OnboardingTurnResponse({
    required this.message,
    required this.suggestions,
    required this.isCompleted,
    this.nextStep = OnboardingStep.notStarted,
  });

  final String message;
  final List<String> suggestions;
  final bool isCompleted;
  final OnboardingStep nextStep;
}

/// Orchestrator onboarding interaktif berbasis aturan di dalam Chatbot Asisten.
/// 100% lokal, deterministik, instan (0 latensi), dan offline-ready.
class AssistantOnboardingOrchestrator {
  AssistantOnboardingOrchestrator({
    required AppDatabase database,
    String householdId = AppContext.householdId,
  })  : _database = database, // ignore: prefer_initializing_formals
        _householdId = householdId; // ignore: prefer_initializing_formals

  final AppDatabase _database;
  final String _householdId;

  OnboardingStep _currentStep = OnboardingStep.notStarted;
  String _familyName = 'Keluarga Kami';

  OnboardingStep get currentStep => _currentStep;
  bool get isOnboardingActive =>
      _currentStep == OnboardingStep.askFamilyName ||
      _currentStep == OnboardingStep.askAccounts;

  /// Memeriksa apakah pengguna memerlukan alur onboarding.
  Future<bool> checkNeedsOnboarding() async {
    final completed = await OnboardingPreference.isCompleted();
    if (completed) return false;

    // Periksa apakah sudah ada akun yang dibuat
    try {
      final existingAccounts = await (_database.select(_database.accounts)
            ..where((t) => t.householdId.equals(_householdId)))
          .get();
      if (existingAccounts.isNotEmpty) {
        await OnboardingPreference.setCompleted(true);
        return false;
      }
    } catch (_) {}

    return true;
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
    );
  }

  /// Memproses respon pengguna di setiap langkah onboarding.
  Future<OnboardingTurnResponse> processInput(String rawInput) async {
    final text = rawInput.trim();
    if (_currentStep == OnboardingStep.askFamilyName) {
      _familyName = text.isNotEmpty ? text : 'Keluarga Kami';
      // Simpan nama keluarga ke database lokal
      try {
        await (_database.update(_database.households)
              ..where((t) => t.id.equals(_householdId)))
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
        suggestions: [
          'Dompet Tunai & Bank BCA',
          'Dompet Tunai & Bank Mandiri',
          'Dompet Tunai & Bank BRI',
          'Dompet Tunai Saja',
        ],
        isCompleted: false,
        nextStep: OnboardingStep.askAccounts,
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
      );
    }

    return const OnboardingTurnResponse(
      message: 'Onboarding sudah selesai. Ada yang bisa saya bantu?',
      suggestions: [],
      isCompleted: true,
      nextStep: OnboardingStep.completed,
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
      await _database.into(_database.accounts).insertOnConflictUpdate(
        AccountsCompanion.insert(
          id: id,
          householdId: _householdId,
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
