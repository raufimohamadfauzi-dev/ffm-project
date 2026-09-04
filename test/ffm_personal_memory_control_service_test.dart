import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_memory_repository.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_user_model_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_personal_context_engine_impl.dart';
import 'package:ffm_manager/features/assistant/data/ffm_personal_memory_control_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_memory_candidate.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_memory_type.dart';

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

  test('engine tidak menyimpan kandidat yang masih menunggu persetujuan',
      () async {
    final engine = FfmPersonalContextEngineImpl(
      database: database,
      memoryRepository: memories,
    );

    final promoted = await engine.promoteCandidates(
      candidates: const [
        FfmMemoryPromotionCandidate(
          type: FfmMemoryType.preference,
          key: 'gaya_jawaban',
          value: 'ringkas',
          confidence: .9,
          requiresApproval: true,
        ),
      ],
      requireApproval: true,
    );

    expect(promoted, isEmpty);
    expect(await memories.readAll(), isEmpty);
  });

  test('engine memperbarui penggunaan memori yang benar-benar dipakai',
      () async {
    final memory = await memories.save(
      kind: 'answer',
      triggerText: 'ringkasan',
      valueText: 'Jawaban singkat',
      metadata: const {'useCount': 0},
    );
    final engine = FfmPersonalContextEngineImpl(
      database: database,
      memoryRepository: memories,
    );

    await engine.updateMemoryUsage(memoryIds: [memory.id, memory.id]);

    final updated = (await memories.readAll()).single;
    expect(updated.metadata['useCount'], 1);
    expect(updated.metadata['lastUsedAt'], isA<String>());
  });

  test('save beruntun cepat tetap menghasilkan id unik tanpa saling menimpa',
      () async {
    final records = await Future.wait(
      List.generate(64, (index) {
        return memories.save(
          kind: 'answer',
          triggerText: 'contoh-$index',
          valueText: 'nilai-$index',
        );
      }),
    );

    final distinctIds = records.map((record) => record.id).toSet();
    expect(distinctIds, hasLength(64));
    expect(await memories.readActive(), hasLength(64));
  });

  group('saveManualMemory', () {
    test('menyimpan profil (userModel) langsung aktif dan disetujui', () async {
      final item = await service.saveManualMemory(
        label: 'Nama panggilan',
        value: 'Naya',
        scope: FfmPersonalMemoryControlScope.userModel,
      );

      expect(item.label, 'Nama panggilan');
      expect(item.value, 'Naya');
      expect(item.scope, FfmPersonalMemoryControlScope.userModel);

      final visible = await service.readVisible();
      expect(visible.map((e) => e.label), contains('Nama panggilan'));
    });

    test('menyimpan preferensi (personalMemory) langsung aktif dan disetujui', () async {
      final item = await service.saveManualMemory(
        label: 'Gaya Bahasa',
        value: 'Santai dan ramah',
        scope: FfmPersonalMemoryControlScope.personalMemory,
      );

      expect(item.label, 'Gaya Bahasa');
      expect(item.value, 'Santai dan ramah');
      expect(item.scope, FfmPersonalMemoryControlScope.personalMemory);

      final visible = await service.readVisible();
      expect(visible.map((e) => e.label), contains('Gaya Bahasa'));
    });

    test('menyimpan koreksi (aliasCorrection) langsung aktif dan berlabel Koreksi', () async {
      final item = await service.saveManualMemory(
        label: 'mamam',
        value: 'makan siang',
        scope: FfmPersonalMemoryControlScope.aliasCorrection,
      );

      expect(item.label, 'Koreksi: mamam');
      expect(item.value, 'makan siang');
      expect(item.scope, FfmPersonalMemoryControlScope.aliasCorrection);

      final visible = await service.readVisible();
      expect(visible.map((e) => e.label), contains('Koreksi: mamam'));
    });

    test('menolak input kosong', () async {
      expect(
        () => service.saveManualMemory(
          label: '',
          value: 'value',
          scope: FfmPersonalMemoryControlScope.userModel,
        ),
        throwsArgumentError,
      );
      expect(
        () => service.saveManualMemory(
          label: 'label',
          value: '  ',
          scope: FfmPersonalMemoryControlScope.personalMemory,
        ),
        throwsArgumentError,
      );
    });

    test('menolak input yang mengandung data sensitif atau angka nominal besar', () async {
      expect(
        () => service.saveManualMemory(
          label: 'pin atm',
          value: '123456',
          scope: FfmPersonalMemoryControlScope.userModel,
        ),
        throwsArgumentError,
      );
      expect(
        () => service.saveManualMemory(
          label: 'catatan gaji',
          value: '5000000',
          scope: FfmPersonalMemoryControlScope.personalMemory,
        ),
        throwsArgumentError,
      );
    });
  });
}
