import 'dart:convert';

import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_knowledge_pack_service.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_local_model_gateway.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_memory_repository.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:ffm_manager/features/backup/data/json_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late FfmAssistantInterpreter interpreter;
  late FfmAssistantMemoryRepository memories;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    interpreter = FfmAssistantInterpreter(database);
    memories = FfmAssistantMemoryRepository(database);
    await database
        .into(database.accounts)
        .insert(
          AccountsCompanion.insert(
            id: 'seabank-pribadi',
            householdId: AppContext.householdId,
            name: 'SeaBank Pribadi',
            type: 'bank',
            createdAt: DateTime(2026, 8, 22),
          ),
        );
  });

  tearDown(() => database.close());

  test('rekening belum terdaftar menanyakan jenis lalu jawaban pemasukan jadi draft', () async {
    final initial = await interpreter.interpret(
      'catat 1 juta ke rekening BRI baru',
    );

    expect(initial.type, FfmAssistantIntentType.unknown);
    expect(initial.needsClarification, isTrue);
    expect(initial.clarification, contains('pemasukan atau pengeluaran'));

    final resolved = await interpreter.resolvePendingDialog(
      'pemasukan',
      FfmAssistantPendingDialog(
        originalRequest: 'catat 1 juta ke rekening BRI baru',
        prompt: initial.clarification!,
        missingFields: const ['jenis transaksi'],
      ),
    );

    expect(resolved, hasLength(1));
    expect(resolved.single.type, FfmAssistantIntentType.createIncome);
    expect(resolved.single.draft?.kind, FfmAssistantDraftKind.income);
    expect(resolved.single.draft?.amount, 1000000);
    expect(resolved.single.draft?.toAccountName, isNull);
    expect(resolved.single.needsConfirmation, isTrue);
    expect(await database.select(database.transactions).get(), isEmpty);
  });

  test('alias memori ajar mengarahkan draft ke rekening yang benar', () async {
    await memories.save(
      kind: 'alias',
      triggerText: 'tabungan',
      valueText: 'SeaBank Pribadi',
    );

    final intent = await interpreter.interpret(
      'pemasukan 125 ribu ke tabungan',
    );

    expect(intent.type, FfmAssistantIntentType.createIncome);
    expect(intent.draft?.toAccountName, 'SeaBank Pribadi');
    expect(intent.needsConfirmation, isTrue);
  });

  test(
    'knowledge pack mengekspor JSON valid dan impor menambah memori',
    () async {
      final service = FfmAssistantKnowledgePackService(memories);
      await memories.save(
        kind: 'answer',
        triggerText: 'apa fungsi tag',
        valueText: 'Tag buat penanda tambahan biar catatan gampang dicari.',
      );

      final exported = await service.exportJson();
      final decoded = jsonDecode(exported) as Map<String, dynamic>;
      expect(
        decoded['formatVersion'],
        FfmAssistantKnowledgePackService.formatVersion,
      );
      expect(decoded['memories'], isA<List>());

      final imported = await service.importJson(
        jsonEncode({
          'formatVersion': FfmAssistantKnowledgePackService.formatVersion,
          'memories': [
            {
              'id': 'learned-flow-1',
              'kind': 'flow',
              'triggerText': 'catat belanja pasar',
              'valueText': 'Tanya nominal, kategori, dan rekening dulu.',
              'metadata': {'module': 'transactions'},
            },
          ],
        }),
      );

      expect(imported, 1);
      final records = await memories.readActive();
      expect(records.map((record) => record.id), contains('learned-flow-1'));
    },
  );

  test('backup penuh ikut membawa memori ajar Asisten', () async {
    await memories.save(
      kind: 'habit',
      triggerText: 'belanja sayur',
      valueText: 'Biasanya pakai SeaBank Pribadi.',
    );
    final backup = JsonBackupService(database);

    final exported = await backup.exportJson();
    final decoded = jsonDecode(exported) as Map<String, dynamic>;
    final modules = decoded['modules'] as Map<String, dynamic>;
    final saved = modules['assistant_memories'] as List<dynamic>;

    expect(saved, hasLength(1));
    expect(saved.single['trigger_text'], 'belanja sayur');
    expect(backup.previewJson(exported).counts['assistant_memories'], 1);
  });

  test(
    'gateway SLM nonaktif mengembalikan null dan parser lokal tetap berjalan',
    () async {
      const gateway = FfmAssistantDisabledLocalModelGateway();

      final proposal = await gateway.propose(
        input: 'pemasukan 30 ribu ke SeaBank Pribadi',
        knownAccountNames: const ['SeaBank Pribadi'],
      );
      final intent = await interpreter.interpret(
        'pemasukan 30 ribu ke SeaBank Pribadi',
      );

      expect(proposal, isNull);
      expect(intent.type, FfmAssistantIntentType.createIncome);
      expect(intent.draft?.amount, 30000);
    },
  );

  test(
    'reset chat tidak menghapus memori ajar yang tersimpan di database',
    () async {
      await memories.save(
        kind: 'alias',
        triggerText: 'uang simpanan',
        valueText: 'SeaBank Pribadi',
      );
      final session = FfmAssistantChatSession();
      session.entries.add(
        const FfmAssistantChatEntry(isUser: true, text: 'ingat uang simpanan'),
      );
      session.reset();

      final records = await memories.readActive(kind: 'alias');
      expect(records, hasLength(1));
      expect(records.single.triggerText, 'uang simpanan');
      expect(session.entries.single.text, contains('Chat sudah direset'));
    },
  );
}
