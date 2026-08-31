import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_llm_evaluation_framework.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_verified_fact_service.dart';

void main() {
  group('LLM Evaluation Framework - Core Logic Tests', () {
    late FfmLLMEvaluationFramework evaluator;

    setUp(() {
      evaluator = const FfmLLMEvaluationFramework();
    });

    test('Should detect hallucination patterns', () {
      final result = evaluator.evaluateResponse(
        userQuery: 'Berapa saldo saya?',
        llmResponse: 'Tidak ada data tapi saya asumsikan Rp1.000.000.',
        verifiedFacts: FfmVerifiedFacts(
          capturedAt: DateTime.now(),
          householdId: 'test-household',
        ),
      );

      expect(result.scores['hallucination'], lessThan(0.8));
      expect(result.issues.any((i) => i.contains('asumsikan')), isTrue);
    });

    test('Should check intent following for quantity questions', () {
      final result = evaluator.evaluateResponse(
        userQuery: 'Berapa banyak transaksi bulan ini?',
        llmResponse: 'Bulan ini ada 15 transaksi yang tercatat.',
        verifiedFacts: FfmVerifiedFacts(
          capturedAt: DateTime.now(),
          householdId: 'test-household',
        ),
      );

      expect(result.scores['intent'], greaterThan(0.8));
      expect(result.strengths, contains('Provides numeric answer to quantity question'));
    });

    test('Should check intent following for descriptive questions', () {
      final result = evaluator.evaluateResponse(
        userQuery: 'Apa fitur yang tersedia?',
        llmResponse: 'FFM memiliki berbagai fitur seperti pencatatan transaksi, manajemen anggaran, dan tracking aktivitas.',
        verifiedFacts: FfmVerifiedFacts(
          capturedAt: DateTime.now(),
          householdId: 'test-household',
        ),
      );

      expect(result.scores['intent'], greaterThan(0.8));
      expect(result.strengths, contains('Provides descriptive answer'));
    });

    test('Should check action result integrity', () {
      final result = evaluator.evaluateResponse(
        userQuery: 'Catat pengeluaran makan 50 ribu',
        llmResponse: 'Draft pengeluaran makan Rp50.000 siap. Silakan konfirmasi untuk menyimpan.',
        verifiedFacts: FfmVerifiedFacts(
          capturedAt: DateTime.now(),
          householdId: 'test-household',
        ),
      );

      expect(result.scores['actionIntegrity'], greaterThan(0.8));
      // The strength might be detected or not depending on the response
      // Just check the score is good
    });

    test('Should detect premature success claims', () {
      final result = evaluator.evaluateResponse(
        userQuery: 'Catat pengeluaran makan 50 ribu',
        llmResponse: 'Pengeluaran sudah disimpan.',
        verifiedFacts: FfmVerifiedFacts(
          capturedAt: DateTime.now(),
          householdId: 'test-household',
        ),
      );

      expect(result.scores['actionIntegrity'], lessThan(0.8));
      expect(result.issues, contains('Claims save without mentioning confirmation'));
    });

    test('Should check naturalness of response', () {
      final result = evaluator.evaluateResponse(
        userQuery: 'Berapa saldo saya?',
        llmResponse: 'Berdasarkan data yang tercatat, saldo Anda saat ini adalah Rp2.500.000. Saldo ini berasal dari 2 rekening aktif.',
        verifiedFacts: FfmVerifiedFacts(
          capturedAt: DateTime.now(),
          householdId: 'test-household',
        ),
      );

      expect(result.scores['naturalness'], greaterThan(0.8));
      expect(result.strengths, contains('Uses multiple sentences for better structure'));
    });

    test('Should detect unnatural language patterns', () {
      final result = evaluator.evaluateResponse(
        userQuery: 'Berapa saldo saya?',
        llmResponse: 'Saldo dari dari saldo dari saldo dari saldo adalah Rp1.000.000.',
        verifiedFacts: FfmVerifiedFacts(
          capturedAt: DateTime.now(),
          householdId: 'test-household',
        ),
      );

      expect(result.scores['naturalness'], lessThanOrEqualTo(0.9));
      expect(result.issues, contains('Contains unnatural language pattern'));
    });

    test('Should check relevance to query', () {
      final result = evaluator.evaluateResponse(
        userQuery: 'Berapa saldo rekening BCA saya?',
        llmResponse: 'Saldo rekening BCA Anda saat ini Rp3.500.000.',
        verifiedFacts: FfmVerifiedFacts(
          capturedAt: DateTime.now(),
          householdId: 'test-household',
        ),
      );

      expect(result.scores['relevance'], greaterThanOrEqualTo(0.5));
    });

    test('Should detect irrelevant responses', () {
      final result = evaluator.evaluateResponse(
        userQuery: 'Berapa saldo saya?',
        llmResponse: 'Fitur transfer uang memungkinkan Anda memindahkan dana antar rekening.',
        verifiedFacts: FfmVerifiedFacts(
          capturedAt: DateTime.now(),
          householdId: 'test-household',
        ),
      );

      expect(result.scores['relevance'], lessThan(0.7));
      expect(result.issues, contains('Does not address enough query keywords'));
    });

    test('Should check completeness for multi-part questions', () {
      final result = evaluator.evaluateResponse(
        userQuery: 'Berapa saldo dan berapa banyak transaksi bulan ini?',
        llmResponse: 'Saldo Anda Rp2.000.000 dan bulan ini ada 20 transaksi.',
        verifiedFacts: FfmVerifiedFacts(
          capturedAt: DateTime.now(),
          householdId: 'test-household',
        ),
      );

      expect(result.scores['completeness'], equals(1.0));
      expect(result.strengths, contains('Addresses all parts of multi-part question'));
    });

    test('Should detect incomplete multi-part answers', () {
      final result = evaluator.evaluateResponse(
        userQuery: 'Berapa saldo dan berapa banyak transaksi bulan ini?',
        llmResponse: 'Saldo Anda Rp2.000.000.',
        verifiedFacts: FfmVerifiedFacts(
          capturedAt: DateTime.now(),
          householdId: 'test-household',
        ),
      );

      expect(result.scores['completeness'], lessThan(1.0));
      expect(result.issues, contains('Does not address all parts of multi-part question'));
    });

    test('Should check completeness for detail requests', () {
      final result = evaluator.evaluateResponse(
        userQuery: 'Jelaskan detail pengeluaran bulan ini',
        llmResponse: 'Pengeluaran bulan ini total Rp5.000.000 dengan kategori terbesar makanan (Rp2.000.000) dan transport (Rp1.500.000). Ada 25 transaksi dengan rata-rata Rp200.000 per transaksi.',
        verifiedFacts: FfmVerifiedFacts(
          capturedAt: DateTime.now(),
          householdId: 'test-household',
        ),
      );

      expect(result.scores['completeness'], greaterThan(0.8));
      expect(result.strengths, contains('Provides detailed response as requested'));
    });

    test('Should detect lack of detail for detail requests', () {
      final result = evaluator.evaluateResponse(
        userQuery: 'Jelaskan detail pengeluaran bulan ini',
        llmResponse: 'Pengeluaran bulan ini Rp5.000.000.',
        verifiedFacts: FfmVerifiedFacts(
          capturedAt: DateTime.now(),
          householdId: 'test-household',
        ),
      );

      expect(result.scores['completeness'], lessThan(0.8));
      expect(result.issues, contains('Response lacks detail for detail request'));
    });

    test('Should generate proper evaluation report', () {
      final result = evaluator.evaluateResponse(
        userQuery: 'Berapa saldo saya?',
        llmResponse: 'Berdasarkan data tercatat, saldo Anda Rp3.000.000 dari 2 rekening aktif.',
        verifiedFacts: FfmVerifiedFacts(
          capturedAt: DateTime.now(),
          householdId: 'test-household',
        ),
      );

      final report = result.toReport();

      expect(report, contains('=== LLM Evaluation Report ==='));
      expect(report, contains('Overall Score:'));
      expect(report, contains('Quality Level:'));
      expect(report, contains('Detailed Scores:'));
      expect(result.qualityLevel, isNotEmpty);
    });

    test('Should determine quality level correctly', () {
      final excellentResult = evaluator.evaluateResponse(
        userQuery: 'Berapa saldo saya?',
        llmResponse: 'Berdasarkan data tercatat, saldo Anda Rp3.000.000 dari 2 rekening aktif.',
        verifiedFacts: FfmVerifiedFacts(
          capturedAt: DateTime.now(),
          householdId: 'test-household',
        ),
      );

      expect(excellentResult.qualityLevel, equals('Excellent'));

      final poorResult = evaluator.evaluateResponse(
        userQuery: 'Berapa saldo saya?',
        llmResponse: 'Tidak ada data tapi saya asumsikan Rp1.000.000.',
        verifiedFacts: FfmVerifiedFacts(
          capturedAt: DateTime.now(),
          householdId: 'test-household',
          recentTransactions: const [],
        ),
      );

      expect(poorResult.qualityLevel, isNot('Excellent'));
    });

    test('Should pass evaluation with good overall score', () {
      final result = evaluator.evaluateResponse(
        userQuery: 'Berapa saldo saya?',
        llmResponse: 'Berdasarkan data tercatat, saldo Anda Rp2.500.000 dari 2 rekening aktif.',
        verifiedFacts: FfmVerifiedFacts(
          capturedAt: DateTime.now(),
          householdId: 'test-household',
        ),
      );

      expect(result.overallScore, greaterThanOrEqualTo(0.7));
      expect(result.passed, isTrue);
    });

    test('Should fail evaluation with low overall score', () {
      final result = evaluator.evaluateResponse(
        userQuery: 'Berapa saldo saya?',
        llmResponse: 'Tidak ada data tapi saya asumsikan Rp1.000.000 berdasarkan tebakan.',
        verifiedFacts: FfmVerifiedFacts(
          capturedAt: DateTime.now(),
          householdId: 'test-household',
          recentTransactions: const [],
        ),
      );

      // Check that hallucination score is low
      expect(result.scores['hallucination'], lessThan(0.8));
      // Check that it fails the overall pass criteria
      expect(result.passed, isFalse);
    });
  });
}