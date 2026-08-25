import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_memory_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_user_model_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_personal_context_engine_impl.dart';
import 'package:ffm_manager/features/assistant/data/ffm_personal_memory_control_service.dart';

void main() {
  late AppDatabase database;
  late FfmAssistantMemoryRepository memories;
  late FfmPersonalMemoryControlService service;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    memories = FfmAssistantMemoryRepository(database);
    service = FfmPersonalMemoryControlService(memories);
  });

  tearDown(() => database.close());

  test('menampilkan hanya scope approved yang personal dan aman', () async {
    final userModel = FfmAssistantUserModelService(memories);
    await userModel.saveApproved(kind: 'name', key: 'panggilan', value: 'Budi');
    await memories.save(
      kind: 'personal_memory_preference',
      triggerText: 'gaya_jawaban',
      valueText: 'singkat',
      metadata: const {
        'scope': 'personal-memory',
        'approved': true,
        'humanLabel': 'Jawaban singkat',
      },
    );
    await memories.save(
      kind: 'personal_memory_preference',
      triggerText: 'preferensi_pending',
      valueText: 'belum disetujui',
      metadata: const {
        'scope': 'personal-memory',
        'approved': false,
        'humanLabel': 'Tidak boleh tampil',
      },
    );
    await memories.save(
      kind: 'alias',
      triggerText: 'catat cepat',
      valueText: 'catat singkat',
      source: 'chat_message_correction',
    );
    await memories.save(
      kind: 'user_identity',
      triggerText: 'pin',
      valueText: '1234',
      metadata: const {'scope': 'user-model', 'approved': true},
    );
    await memories.save(
      kind: 'answer',
      triggerText: 'apa itu FFM',
      valueText: 'Family Finance Manager',
    );

    final items = await service.readVisible();

    expect(
      items.map((item) => item.label),
      containsAll(['panggilan', 'Jawaban singkat', 'Koreksi: catat cepat']),
    );
    expect(items.map((item) => item.label), isNot(contains('pin')));
    expect(
      items.map((item) => item.label),
      isNot(contains('Tidak boleh tampil')),
    );
    expect(items.map((item) => item.label), isNot(contains('apa itu FFM')));
  });

  test('lupakan mengarsipkan item agar tidak lagi tampil atau dipakai context engine', () async {
    final userModel = FfmAssistantUserModelService(memories);
    final entry = await userModel.saveApproved(
      kind: 'name',
      key: 'panggilan',
      value: 'Budi',
    );
    expect(await service.readVisible(), hasLength(1));

    await service.forget(entry.id);

    expect(await service.readVisible(), isEmpty);
    final engine = FfmPersonalContextEngineImpl(
      database: database,
      memoryRepository: memories,
      userModelService: userModel,
    );
    final context = await engine.buildContext(query: 'siapa saya?');
    expect(context.personalFacts, isEmpty);
  });

  test('filter sensitif menolak nominal besar dan kredensial', () {
    expect(
      FfmPersonalMemorySafetyPolicy.isSafeForPersonalContext(
        key: 'panggilan',
        value: 'Budi',
      ),
      isTrue,
    );
    expect(
      FfmPersonalMemorySafetyPolicy.isSafeForPersonalContext(
        key: 'password',
        value: 'rahasia',
      ),
      isFalse,
    );
    expect(
      FfmPersonalMemorySafetyPolicy.isSafeForPersonalContext(
        key: 'catatan',
        value: '1250000',
      ),
      isFalse,
    );
  });
}
