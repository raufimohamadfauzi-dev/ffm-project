import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_financial_snapshot_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_correction_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_memory_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_gemini_read_capability_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_proposal_json_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = createInMemoryDatabaseForTests();
  });

  tearDown(() async {
    await database.close();
  });

  group('read.schema Capability (Hybrid)', () {
    test('buildSchemaContext mengembalikan daftar tabel hybrid beserta deskripsi dan jumlah baris', () async {
      final now = DateTime(2026, 9, 11);

      // Insert data transaksi dan rekening
      await database.into(database.accounts).insert(
            AccountsCompanion.insert(
              id: 'acc-schema-test',
              householdId: AppContext.householdId,
              name: 'SeaBank Test',
              type: 'bank',
              openingBalance: const Value(500000),
              createdAt: now,
            ),
          );

      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-schema-test',
              householdId: AppContext.householdId,
              type: 'expense',
              amount: -50000,
              date: now,
              recordedAt: now,
              createdAt: now,
            ),
          );

      final snapshotService = FfmAssistantFinancialSnapshotService(database);
      final schema = await snapshotService.buildSchemaContext(
        householdId: AppContext.householdId,
      );

      // Verifikasi format hybrid: nama teknis sqlite + deskripsi fitur + jumlah baris
      expect(schema, contains('Fakta Skema Database FFM'));
      expect(schema, contains('transactions (Riwayat Transaksi Finansial'));
      expect(schema, contains('accounts (Rekening Bank, Dompet Digital & Kas Tunai'));
      expect(schema, contains('1 baris'));
      // Verifikasi keamanan: tidak ada data sensitif saldo atau nomor rekening
      expect(schema, isNot(contains('500000')));
      expect(schema, isNot(contains('SeaBank Test')));
    });

    test('read.schema diizinkan di allowlist Gemini Cloud dan dieksekusi oleh read capability service', () async {
      expect(FfmGeminiReadCapabilityPolicy.isAllowed('read.schema'), isTrue);
      expect(FfmGeminiReadCapabilityPolicy.isAllowed('read.tables'), isTrue);

      final snapshotService = FfmAssistantFinancialSnapshotService(database);
      final readService = FfmGeminiReadCapabilityService(snapshotService);

      final result = await readService.execute(
        const FfmAssistantReadCapabilityRequest(
          capabilityId: 'read.schema',
          period: 'current_month',
        ),
        householdId: AppContext.householdId,
        now: DateTime(2026, 9, 11),
      );

      expect(result, contains('Fakta Skema Database FFM'));
      expect(result, contains('transactions'));
    });

    test('read.schema adapter lokal dapat dieksekusi langsung secara deterministik', () async {
      final registry = FfmAssistantCapabilityAdapterRegistry(
        database: database,
        householdId: AppContext.householdId,
      );

      final handler = registry.handlers['read.schema'];
      expect(handler, isNotNull);

      const step = FfmAssistantActionStep(
        id: 'step-schema',
        capabilityId: 'read.schema',
      );

      final result = await handler!(step);
      expect(result.isSuccess, isTrue);
      expect(result.message, contains('Fakta Skema Database FFM'));
      expect(result.message, contains('transactions'));
    });
  });

  group('Self-Correction Loop Permanen', () {
    test('saveCorrection menyimpan koreksi ke assistant_memories secara permanen', () async {
      final memoryRepo = FfmAssistantMemoryRepository(database);
      final correctionService = FfmAssistantCorrectionService(memoryRepo);

      final record = await correctionService.saveCorrection(
        userQuestion: 'Apakah ada menu ekspor data?',
        correctedText: 'Fitur ekspor data tersedia di Pengaturan > Cadangan & Ekspor.',
        originalResponse: 'Maaf, saya tidak tahu apakah ada menu ekspor.',
        topic: 'ekspor_data',
      );

      expect(record.kind, equals('correction'));
      expect(record.triggerText, equals('Apakah ada menu ekspor data?'));
      expect(record.valueText, contains('Pengaturan > Cadangan & Ekspor'));
      expect(record.metadata['scope'], equals('user-correction'));
      expect(record.metadata['approved'], isTrue);

      // Verifikasi di database
      final active = await correctionService.getActiveCorrections();
      expect(active.length, equals(1));
      expect(active.first.triggerText, equals('Apakah ada menu ekspor data?'));
    });

    test('buildCorrectionsContext menyusun prompt aturan pengguna', () async {
      final memoryRepo = FfmAssistantMemoryRepository(database);
      final correctionService = FfmAssistantCorrectionService(memoryRepo);

      await correctionService.saveCorrection(
        userQuestion: 'Kategori galon air masuk ke mana?',
        correctedText: 'Kategori galon air masuk ke Kebutuhan Pokok, bukan Hiburan.',
      );

      final contextForQuery = await correctionService.buildCorrectionsContext(
        query: 'galon air',
      );

      expect(contextForQuery, contains('KOREKSI & ATURAN PENGGUNA TERVERIFIKASI'));
      expect(contextForQuery, contains('Kategori galon air'));
      expect(contextForQuery, contains('Kebutuhan Pokok, bukan Hiburan'));
    });
  });
}
