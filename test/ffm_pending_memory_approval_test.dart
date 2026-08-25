import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_memory_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_user_model_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_memory_learning_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_personal_memory_control_service.dart';

void main() {
  late AppDatabase db;
  late FfmAssistantMemoryRepository repo;
  late FfmPersonalMemoryControlService control;
  late FfmMemoryLearningService learning;

  setUp(() {
    db = createInMemoryDatabaseForTests();
    repo = FfmAssistantMemoryRepository(db);
    control = FfmPersonalMemoryControlService(repo);
    learning = FfmMemoryLearningService(memoryRepository: repo);
  });

  tearDown(() async {
    await db.close();
  });

  Future<FfmPendingMemoryItem> learnPayday() async {
    final candidates = await learning.extractCandidates(
      userQuery: 'gajian tanggal 25 tiap bulan',
      assistantResponse: null,
      usedMemories: const [],
    );
    await learning.promoteCandidates(
      candidates: candidates,
      requireApproval: true,
    );
    final pending = await control.readPendingLearning();
    return pending.firstWhere(
      (item) => item.value.contains('gajian tanggal 25'),
    );
  }

  test(
    'usulan payday pending: tak tampil di daftar maupun konteks SLM',
    () async {
      final payday = await learnPayday();

      final visible = await control.readVisible();
      final pending = await control.readPendingLearning();
      final context = await FfmAssistantUserModelService(repo).buildContext();

      expect(visible, isEmpty);
      expect(pending, isNotEmpty);
      expect(payday.value, contains('gajian tanggal 25'));
      expect(context, isEmpty);
    },
  );

  test('setujui: masuk konteks SLM dan tampil di pusat kontrol', () async {
    final payday = await learnPayday();

    final ok = await control.approvePending(payday.id);
    expect(ok, isTrue);

    final context = await FfmAssistantUserModelService(repo).buildContext();
    expect(context, contains('payday'));

    // Baris payday kini approved dan mendapat scope user-model.
    final rows = await repo.readActive(kind: 'explicitfact');
    final paydayRow = rows.firstWhere(
      (record) => record.triggerText == 'payday',
    );
    expect(paydayRow.metadata['approved'], isTrue);
    expect(paydayRow.metadata['scope'], 'user-model');

    final visible = await control.readVisible();
    // Nilai aman (tanpa nominal/sensitive) wajib tampil di daftar memori.
    expect(
      visible.any((item) => item.value.contains('gajian')),
      isTrue,
      reason:
          'Memori disetujui dengan isi aman harus terlihat di Pusat Kontrol.',
    );
  });

  test('tolak: diarsipkan lunak, tidak pernah masuk konteks', () async {
    final payday = await learnPayday();

    await control.rejectPending(payday.id);

    final active = await repo.readActive(kind: 'explicitfact');
    expect(active, isEmpty);

    final context = await FfmAssistantUserModelService(repo).buildContext();
    expect(context, isEmpty);
  });

  test('setujui id asing atau arsip: dikembalikan false tanpa error',
      () async {
    expect(await control.approvePending('tidak-ada'), isFalse);

    final payday = await learnPayday();
    await control.rejectPending(payday.id);
    expect(await control.approvePending(payday.id), isFalse);
  });
}

