import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/network/gemini_service.dart';
import 'package:ffm_manager/core/network/supabase_config.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_analysis_engine.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_verified_fact_service.dart';

class _FakeConfig extends SupabaseConfig {
  @override
  Future<String?> getGeminiKey() async => 'test-key';

  @override
  Future<String?> getGeminiModel() async => 'gemini-2.5-flash';

  @override
  Future<bool> isGeminiVerified() async => true;

  @override
  Future<String> getLlmMode() async => 'gemini';
}

class _SpyGeminiService extends GeminiService {
  _SpyGeminiService({required this.responseToReturn});

  final String responseToReturn;
  String? lastSystemInstruction;
  var calls = 0;

  @override
  Future<GeminiResult> chat({
    required String prompt,
    String? systemInstruction,
    List<Map<String, String>> history = const [],
    String? apiKey,
    String? model,
    List<Map<String, dynamic>>? tools,
    GeminiImageInput? image,
    int? maxOutputTokens,
  }) async {
    calls++;
    lastSystemInstruction = systemInstruction;
    return GeminiResult(
      model: model ?? 'gemini-2.5-flash',
      statusCode: 200,
      message: 'OK',
      text: responseToReturn,
    );
  }
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = createInMemoryDatabaseForTests();
  });

  tearDown(() async {
    await db.close();
  });

  group('FfmAnalysisFacts Multi-Month Context', () {
    test('FfmAnalysisFacts menyertakan rata-rata bulanan untuk periode 90 hari / 3 bulan', () {
      final facts = FfmAnalysisFacts(
        period: FfmAnalysisPeriod.last90Days,
        periodLabel: '90 hari terakhir',
        income: 30000000, // 30 juta dalam 3 bulan
        expense: 15000000, // 15 juta dalam 3 bulan
        netCashflow: 15000000,
        transactionCount: 45,
        topCategory: 'Belanja dapur',
        mostFrequentCategory: 'Belanja dapur',
        mostFrequentMerchant: 'Supermarket',
        categoryBreakdown: {
          'Belanja dapur': 9000000,
          'Transportasi': 3000000,
        },
        categoryFrequency: {'Belanja dapur': 30, 'Transportasi': 15},
        capturedAt: DateTime(2026, 9, 3),
      );

      final llmContext = facts.toLLMContext();

      expect(llmContext, contains('ANALYSIS FACTS (90 hari terakhir'));
      expect(llmContext, contains('- Income: Rp30.000.000'));
      expect(llmContext, contains('- Expense: Rp15.000.000'));
      // Rata-rata bulanan deterministik (dibagi 3)
      expect(llmContext, contains('- Monthly Average Income: Rp10.000.000'));
      expect(llmContext, contains('- Monthly Average Expense: Rp5.000.000'));
      expect(llmContext, contains('- Monthly Average Net Cashflow: Rp5.000.000'));
      // Rata-rata run-rate kategori bulanan
      expect(llmContext, contains('Belanja dapur: Rp9.000.000 (avg: Rp3.000.000/month)'));
      expect(llmContext, contains('Transportasi: Rp3.000.000 (avg: Rp1.000.000/month)'));
    });

    test('FfmAnalysisFacts menyertakan Diagnosis Kesehatan Finansial & Siklus AgroTrack', () {
      final facts = FfmAnalysisFacts(
        period: FfmAnalysisPeriod.last30Days,
        periodLabel: '30 hari terakhir',
        income: 10000000,
        expense: 6000000,
        netCashflow: 4000000,
        transactionCount: 20,
        topCategory: 'Belanja dapur',
        mostFrequentCategory: 'Belanja dapur',
        mostFrequentMerchant: 'Pasar Induk',
        categoryBreakdown: {'Belanja dapur': 4000000},
        categoryFrequency: {'Belanja dapur': 15},
        capturedAt: DateTime(2026, 9, 3),
        healthScore: 85,
        healthStatusLabel: 'Sehat',
        savingsRate: 0.40,
        debtToIncomeRatio: 0.15,
        emergencyMonths: 4.5,
        netWorth: 50000000,
        healthWarnings: const ['Evaluasi belanja non-pokok'],
        healthRecommendations: const ['Tingkatkan alokasi tabungan darurat'],
        activeCycleProfileName: 'Musim Tanam Padi Ciherang',
        cycleCommodity: 'Padi',
        cycleRunwayDays: 75,
        cycleDaysRemaining: 60,
        cycleSafeToSpendDaily: 150000,
        cycleHealthStatus: 'Aman',
      );

      final llmContext = facts.toLLMContext();

      expect(llmContext, contains('Financial Health Diagnosis:'));
      expect(llmContext, contains('- Health Score: 85/100 (Sehat)'));
      expect(llmContext, contains('- Savings Rate: 40%'));
      expect(llmContext, contains('- Debt-to-Income (DSR): 15%'));
      expect(llmContext, contains('- Emergency Fund: 4.5 months coverage'));
      expect(llmContext, contains('- Net Worth: Rp50.000.000'));
      expect(llmContext, contains('- Health Warnings: Evaluasi belanja non-pokok'));
      expect(llmContext, contains('- Key Recommendations: Tingkatkan alokasi tabungan darurat'));

      expect(llmContext, contains('Active Cash Flow Cycle (AgroTrack/Business):'));
      expect(llmContext, contains('- Cycle: Musim Tanam Padi Ciherang (Padi)'));
      expect(llmContext, contains('- Days Remaining to Inflow/Harvest: 60 days'));
      expect(llmContext, contains('- Cash Runway: 75 days'));
      expect(llmContext, contains('- Safe Daily Living Spend: Rp150.000/day'));
      expect(llmContext, contains('- Cycle Health: Aman'));
    });
  });

  group('Interpreter Historical Lookback & Advisory Integration', () {
    test('Pertanyaan 3 bulan ke belakang & saran bulan depan memicu analisis 90 hari', () async {
      // Seed data transaksi selama 3 bulan
      final now = DateTime(2026, 9, 3);
      final d1 = DateTime(2026, 7, 5);
      final d2 = DateTime(2026, 7, 10);
      final d3 = DateTime(2026, 8, 5);
      final d4 = DateTime(2026, 8, 15);
      // Bulan 1 (Juli)
      await db.into(db.transactions).insert(
        TransactionsCompanion.insert(
          id: 'tx-1',
          householdId: 'local-household',
          amount: 10000000,
          type: 'income',
          date: d1,
          recordedAt: d1,
          createdAt: now,
        ),
      );
      await db.into(db.transactions).insert(
        TransactionsCompanion.insert(
          id: 'tx-2',
          householdId: 'local-household',
          amount: 4000000,
          type: 'expense',
          date: d2,
          recordedAt: d2,
          createdAt: now,
        ),
      );
      // Bulan 2 (Agustus)
      await db.into(db.transactions).insert(
        TransactionsCompanion.insert(
          id: 'tx-3',
          householdId: 'local-household',
          amount: 10000000,
          type: 'income',
          date: d3,
          recordedAt: d3,
          createdAt: now,
        ),
      );
      await db.into(db.transactions).insert(
        TransactionsCompanion.insert(
          id: 'tx-4',
          householdId: 'local-household',
          amount: 5000000,
          type: 'expense',
          date: d4,
          recordedAt: d4,
          createdAt: now,
        ),
      );

      final gemini = _SpyGeminiService(
        responseToReturn:
            'Berdasarkan evaluasi 3 bulan ke belakang, rata-rata pengeluaran Anda adalah Rp 3.000.000/bulan dengan pemasukan rata-rata Rp 6.666.666. Saran untuk bulan depan: batasi anggaran belanja dan sisihkan dana darurat.',
      );

      final interpreter = FfmAssistantInterpreter(
        db,
        config: _FakeConfig(),
        geminiService: gemini,
        clock: () => now,
      );

      final intent = await interpreter.interpret(
        'dari 3 bulan ke belakang apa yang harus saya lakukan di bulan depan?',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(gemini.calls, 1);
      expect(gemini.lastSystemInstruction, isNotNull);
      // Memastikan instruksi menyertakan aturan evaluasi historis & saran
      expect(
        gemini.lastSystemInstruction,
        contains('ATURAN EVALUASI HISTORIS & SARAN PERENCANAAN BULAN DEPAN'),
      );
      // Memastikan konteks Gemini mendapatkan fakta analisis 90 hari
      expect(
        gemini.lastSystemInstruction,
        contains('ANALYSIS FACTS (90 hari terakhir'),
      );
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
      expect(intent.response, isNotNull);
    });

    test('Pertanyaan laporan bulan lalu mengikutsertakan fakta agregat lastMonth', () async {
      final now = DateTime(2026, 9, 3);
      final d1 = DateTime(2026, 8, 1);
      final d2 = DateTime(2026, 8, 15);
      // Transaksi bulan Agustus (bulan lalu)
      await db.into(db.transactions).insert(
        TransactionsCompanion.insert(
          id: 'tx-last-month-1',
          householdId: 'local-household',
          amount: 8000000,
          type: 'income',
          date: d1,
          recordedAt: d1,
          createdAt: now,
        ),
      );
      await db.into(db.transactions).insert(
        TransactionsCompanion.insert(
          id: 'tx-last-month-2',
          householdId: 'local-household',
          amount: 3500000,
          type: 'expense',
          date: d2,
          recordedAt: d2,
          createdAt: now,
        ),
      );

      final gemini = _SpyGeminiService(
        responseToReturn:
            'Laporan bulan lalu menunjukkan pemasukan sebesar Rp 8.000.000 dan pengeluaran Rp 3.500.000 dengan surplus Rp 4.500.000.',
      );

      final interpreter = FfmAssistantInterpreter(
        db,
        config: _FakeConfig(),
        geminiService: gemini,
        clock: () => now,
      );

      final intent = await interpreter.interpret(
        'bagaimana laporan bulan lalu?',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(gemini.calls, 1);
      expect(gemini.lastSystemInstruction, isNotNull);
      // Memastikan fakta analisis bulan lalu disuplai ke konteks Gemini
      expect(
        gemini.lastSystemInstruction,
        contains('ANALYSIS FACTS (bulan lalu'),
      );
      expect(
        gemini.lastSystemInstruction,
        contains('Income: Rp8.000.000'),
      );
      expect(
        gemini.lastSystemInstruction,
        contains('Expense: Rp3.500.000'),
      );
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
    });

    test('Pertanyaan pupuk & kebun memicu konteks panen dan panduan holistik', () async {
      final now = DateTime(2026, 9, 3);
      final gemini = _SpyGeminiService(
        responseToReturn:
            'Biaya pembelian pupuk dan pestisida bulan ini tergolong investasi modal kebun. Pastikan dicatat bersama estimasi panen berikutnya.',
      );

      final interpreter = FfmAssistantInterpreter(
        db,
        config: _FakeConfig(),
        geminiService: gemini,
        clock: () => now,
      );

      final intent = await interpreter.interpret(
        'berapa total biaya pembelian pupuk dan bibit kebun bulan ini?',
        routingMode: FfmAssistantRoutingMode.geminiCloud,
      );

      expect(gemini.calls, 1);
      expect(gemini.lastSystemInstruction, isNotNull);
      expect(
        gemini.lastSystemInstruction,
        contains('CAKUPAN LENGKAP PENGELOLA FINANSIAL & OPERASIONAL KELUARGA'),
      );
      expect(intent.responseOrigin, FfmAssistantResponseOrigin.geminiCloud);
    });
  });
}
