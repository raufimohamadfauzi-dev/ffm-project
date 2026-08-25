import 'package:drift/drift.dart' hide Column, isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/database/audit_logger.dart';
import 'package:ffm_manager/features/activity/data/repositories/activity_repository.dart';
import 'package:ffm_manager/features/activity/domain/entities/activity_entity.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_memory_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_personalization_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_activity_habit_learner.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_user_model_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_category_suggestion_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_memory_learning_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_memory_candidate.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_memory_type.dart';

class _FakeAdvisor implements FfmAssistantCategoryAdvisor {
  _FakeAdvisor(this.result);
  final String? result;
  int callCount = 0;

  @override
  Future<String?> suggestCategory({
    required String description,
    required List<String> allowedCategories,
  }) async {
    callCount++;
    return result;
  }
}

class _StubSuggestionService extends FfmCategorySuggestionService {
  _StubSuggestionService(AppDatabase db, this.result)
    : super(database: db, personalization: FfmAssistantPersonalizationRepository(db));

  final FfmCategorySuggestion? result;
  int callCount = 0;

  @override
  Future<FfmCategorySuggestion?> suggestForDraft({
    required FfmAssistantDraftKind kind,
    required String queryText,
    String? merchantName,
  }) async {
    callCount++;
    return result;
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

  Future<void> seedExpenseCategory(String name) async {
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'cat-$name',
            householdId: 'local-household',
            name: name,
            type: 'expense',
            createdAt: DateTime(2026, 1, 1),
          ),
        );
  }

  group('FfmAssistantCategoryAdviceContract.parse', () {
    const allowed = ['Makanan', 'Transportasi', 'Belanja'];

    test('menerima JSON valid dengan kategori resmi', () {
      expect(
        FfmAssistantCategoryAdviceContract.parse(
          '{"category":"Makanan"}',
          allowed,
        ),
        'Makanan',
      );
    });

    test('menerima teks polos case-insensitive', () {
      expect(
        FfmAssistantCategoryAdviceContract.parse(' transportasi ', allowed),
        'Transportasi',
      );
    });

    test('menolak kategori di luar daftar', () {
      expect(
        FfmAssistantCategoryAdviceContract.parse('"Liburan"', allowed),
        isNull,
      );
    });
  });

  group('FfmCategorySuggestionService', () {
    test('pola historis merchant menang atas tebakan SLM', () async {
      await seedExpenseCategory('Kebutuhan Rumah');
      await seedExpenseCategory('Jajan');
      await db
          .into(db.interactionPatterns)
          .insert(
            InteractionPatternsCompanion.insert(
              id: 'pattern-1',
              householdId: 'local-household',
              merchantName: 'Indomaret',
              fieldName: 'category',
              mostCommonValue: 'Kebutuhan Rumah',
              confidenceScore: 0.9,
              sampleCount: 6,
              lastUpdated: DateTime(2026, 8, 1),
            ),
          );
      final advisor = _FakeAdvisor('Jajan');
      final service = FfmCategorySuggestionService(
        database: db,
        personalization: FfmAssistantPersonalizationRepository(db),
        advisor: advisor,
      );

      final suggestion = await service.suggestForDraft(
        kind: FfmAssistantDraftKind.expense,
        queryText: 'belanja di indomaret 50000',
        merchantName: 'Indomaret',
      );

      expect(advisor.callCount, 0);
      expect(suggestion?.categoryName, 'Kebutuhan Rumah');
      expect(suggestion?.sourceLabel, 'pola penggunaanmu');
    });

    test('tanpa pola kuat jatuh ke SLM dan hasilnya divalidasi', () async {
      await seedExpenseCategory('Transportasi');
      final advisor = _FakeAdvisor('TRANSPORTASI');
      final service = FfmCategorySuggestionService(
        database: db,
        personalization: FfmAssistantPersonalizationRepository(db),
        advisor: advisor,
      );

      final suggestion = await service.suggestForDraft(
        kind: FfmAssistantDraftKind.expense,
        queryText: 'bayar ojek online 15000',
      );

      expect(advisor.callCount, 1);
      expect(suggestion?.categoryName, 'Transportasi');
      expect(suggestion?.sourceLabel, 'AI lokal');
    });

    test('jawaban SLM di luar daftar resmi dibuang', () async {
      await seedExpenseCategory('Transportasi');
      final advisor = _FakeAdvisor('Ngopi');
      final service = FfmCategorySuggestionService(
        database: db,
        personalization: FfmAssistantPersonalizationRepository(db),
        advisor: advisor,
      );

      final suggestion = await service.suggestForDraft(
        kind: FfmAssistantDraftKind.expense,
        queryText: 'bayar parkir 2000',
      );

      expect(suggestion, isNull);
    });

    test('draft transfer tidak disarankan kategori', () async {
      final advisor = _FakeAdvisor('Transportasi');
      final service = FfmCategorySuggestionService(
        database: db,
        personalization: FfmAssistantPersonalizationRepository(db),
        advisor: advisor,
      );

      final suggestion = await service.suggestForDraft(
        kind: FfmAssistantDraftKind.transfer,
        queryText: 'transfer 100000',
      );

      expect(advisor.callCount, 0);
      expect(suggestion, isNull);
    });
  });

  group('Interpreter kategori otomatis', () {
    test(
      'draft pengeluaran tanpa kategori dilengkapi saran dari lapis hybrid',
      () async {
        await seedExpenseCategory('Minuman');
        final stub = _StubSuggestionService(
          db,
          const FfmCategorySuggestion(
            categoryName: 'Minuman',
            sourceLabel: 'AI lokal',
          ),
        );
        final interpreter = FfmAssistantInterpreter(db, categorySuggestion: stub);

        final intent = await interpreter.interpret('beli kopi 20000');

        expect(stub.callCount, 1);
        expect(intent.draft?.categoryName, 'Minuman');
        expect(intent.draft?.slmFieldValues['categorySource'], 'AI lokal');
      },
    );

    test(
      'draft yang sudah punya kategori eksplisit tidak ditebak ulang',
      () async {
        await seedExpenseCategory('Makanan');
        final stub = _StubSuggestionService(db, null);
        final interpreter = FfmAssistantInterpreter(db, categorySuggestion: stub);

        final intent = await interpreter.interpret('beli makanan 20000');

        expect(stub.callCount, 0);
        expect(intent.draft?.categoryName, 'Makanan');
      },
    );
  });

  group('FfmActivityHabitLearner', () {
    Future<void> insertSession(String id, String title, DateTime at) async {
      await db
          .into(db.activitySessions)
          .insert(
            ActivitySessionsCompanion.insert(
              id: id,
              householdId: 'local-household',
              title: title,
              status: const Value('active'),
              startedAt: at,
              createdAt: at,
            ),
          );
    }

    test('pola minimal tiga kali menjadi memori habit yang disetujui', () async {
      final base = DateTime(2026, 8, 20, 6);
      await insertSession('s1', 'Lari Pagi', base);
      await insertSession('s2', 'lari pagi', base.add(const Duration(days: 1)));
      await insertSession('s3', 'Lari Pagi ', base.add(const Duration(days: 2)));
      final learner = FfmActivityHabitLearner(
        db,
        FfmAssistantMemoryRepository(db),
      );

      await learner.recordActivityObservation(
        title: 'Lari Pagi',
        occurredAt: base.add(const Duration(days: 3)),
      );

      final memories = await FfmAssistantMemoryRepository(db).readActive(
        kind: 'habit',
      );
      expect(memories, hasLength(1));
      expect(memories.single.valueText, contains('3 kali'));
      expect(memories.single.valueText, contains('biasanya'));
      expect(memories.single.metadata['approved'], true);
      expect(memories.single.metadata['scope'], 'user-model');
    });

    test('di bawah ambang batas tidak menyimpan apa pun dan idempoten', () async {
      final base = DateTime(2026, 8, 18, 20);
      await insertSession('y1', 'Yoga Malam', base);
      await insertSession('y2', 'Yoga Malam', base.add(const Duration(days: 1)));
      final repo = FfmAssistantMemoryRepository(db);
      final learner = FfmActivityHabitLearner(db, repo);

      await learner.recordActivityObservation(
        title: 'Yoga Malam',
        occurredAt: base.add(const Duration(days: 2)),
      );
      expect(await repo.readActive(kind: 'habit'), isEmpty);

      // Capai ambang lalu jalankan dua kali: tetap satu baris.
      await insertSession('y3', 'Yoga Malam', base.add(const Duration(days: 2)));
      await learner.recordActivityObservation(
        title: 'Yoga Malam',
        occurredAt: base.add(const Duration(days: 2)),
      );
      await learner.recordActivityObservation(
        title: 'Yoga Malam',
        occurredAt: base.add(const Duration(days: 2)),
      );
      final memories = await repo.readActive(kind: 'habit');
      expect(memories, hasLength(1));
      expect(memories.single.valueText, contains('3 kali'));
    });
  });

  group('Tahap 3: memori belajar mengalir ke konteks SLM', () {
    test('memori approved ikut, yang pending tidak', () async {
      final repo = FfmAssistantMemoryRepository(db);
      await repo.save(
        kind: 'explicitfact',
        triggerText: 'payday',
        valueText: 'gajian tanggal 25',
        metadata: {'approved': true},
      );
      await repo.save(
        kind: 'explicitfact',
        triggerText: 'payday',
        valueText: 'gajian tanggal 1',
        metadata: {'approved': false},
      );
      final userModel = FfmAssistantUserModelService(repo);

      final context = await userModel.buildContext();

      expect(context, contains('gajian tanggal 25'));
      expect(context, isNot(contains('gajian tanggal 1')));
    });
  });

  group('Tahap 1: pipeline pembelajaran chat aktif dan anti duplikat', () {
    test('fakta gaji tersimpan sekali meski pesan berulang', () async {
      final repo = FfmAssistantMemoryRepository(db);
      final learning = FfmMemoryLearningService(memoryRepository: repo);
      const query = 'gajian tanggal 25 tiap bulan';

      Future<int> runTurn() async {
        final existing = await repo.readActive();
        final existingCandidates = existing
            .map(
              (record) => FfmMemoryCandidate(
                id: record.id,
                type: FfmMemoryType.values.firstWhere(
                  (type) =>
                      type.name.toLowerCase() == record.kind.toLowerCase(),
                  orElse: () => FfmMemoryType.working,
                ),
                key: record.triggerText,
                value: record.valueText,
                evidence: FfmMemoryEvidence(
                  source: FfmMemorySource.userExplicit,
                  createdAt: record.createdAt,
                  updatedAt: record.updatedAt ?? record.createdAt,
                  confidence: 0.8,
                ),
              ),
            )
            .toList();
        final candidates = await learning.extractCandidates(
          userQuery: query,
          assistantResponse: null,
          usedMemories: const [],
        );
        final validated = learning.validateCandidates(
          candidates,
          existingCandidates,
        );
        if (validated.isEmpty) return 0;
        final promoted = await learning.promoteCandidates(
          candidates: validated,
          requireApproval: true,
        );
        return promoted.length;
      }

      expect(await runTurn(), greaterThanOrEqualTo(1));
      expect(await runTurn(), 0);

      final memories = await repo.readActive(kind: 'explicitfact');
      expect(memories, hasLength(1));
      expect(memories.single.triggerText, 'payday');
    });
  });

  group('ActivityRepository memicu pengamat kebiasaan', () {
    test('saveSession meneruskan judul ke habit learner', () async {
      var observedTitle = '';
      var observedAt = DateTime.now();
      final repo = ActivityRepository(
        db,
        AuditLogger(db),
        habitLearner: _CapturingLearner((title, at) {
          observedTitle = title;
          observedAt = at;
        }),
      );

      await repo.saveSession(
        _sessionEntity(title: 'Lari Pagi', startedAt: DateTime(2026, 8, 20, 6)),
      );

      expect(observedTitle, 'Lari Pagi');
      expect(observedAt, DateTime(2026, 8, 20, 6));
    });
  });
}

class _CapturingLearner implements FfmActivityHabitLearner {
  _CapturingLearner(this.onObserve);

  final void Function(String title, DateTime occurredAt) onObserve;

  @override
  Future<void> recordActivityObservation({
    required String title,
    required DateTime occurredAt,
  }) async {
    onObserve(title, occurredAt);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ActivitySessionEntity _sessionEntity({
  required String title,
  required DateTime startedAt,
}) {
  return ActivitySessionEntity(
    id: 'session-1',
    householdId: 'local-household',
    title: title,
    category: 'olahraga',
    startedAt: startedAt,
    status: ActivitySessionStatus.active,
    createdAt: startedAt,
  );
}

