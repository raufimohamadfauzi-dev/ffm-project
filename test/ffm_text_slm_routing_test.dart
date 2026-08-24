import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_interpreter.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_local_model_gateway.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGateway implements FfmAssistantLocalModelGateway {
  _FakeGateway(this.proposal);

  final FfmAssistantModelProposal? proposal;
  var calls = 0;
  String? lastInput;
  String? lastImagePath;
  String? lastPageContext;
  List<String> lastCapabilityIds = const [];

  @override
  Future<FfmAssistantModelProposal?> propose({
    required String input,
    String? imagePath,
  }) async {
    calls++;
    lastInput = input;
    lastImagePath = imagePath;
    return proposal;
  }

  @override
  Future<FfmAssistantModelProposal?> proposeWithContext({
    required String input,
    String? imagePath,
    String? pageContext,
    String? conversationHistory,
    List<String> capabilityIds = const <String>[],
  }) {
    lastPageContext = pageContext;
    lastCapabilityIds = capabilityIds;
    return propose(input: input, imagePath: imagePath);
  }
}

void main() {
  late AppDatabase database;

  setUp(() {
    database = createInMemoryDatabaseForTests();
  });

  tearDown(() => database.close());

  test('teks yang tidak dikenali diteruskan ke model lokal dan hasilnya menjadi draft', () async {
    final gateway = _FakeGateway(
      FfmAssistantModelProposal(
        intent: FfmAssistantIntentType.createIncome,
        confidence: .97,
        draft: FfmAssistantDraft(
          kind: FfmAssistantDraftKind.income,
          createdAt: DateTime(2026, 8, 22),
          date: DateTime(2026, 8, 22),
          amount: 5000000,
          title: 'Gaji',
          toAccountName: 'SeaBank Pribadi',
        ),
      ),
    );
    final interpreter = FfmAssistantInterpreter(
      database,
      modelGateway: gateway,
    );

    final intent = await interpreter.interpret(
      'tolong siapkan catatan gaji bulan ini',
    );

    expect(gateway.calls, 1);
    expect(gateway.lastInput, contains('gaji'));
    expect(intent.type, FfmAssistantIntentType.createIncome);
    expect(intent.draft?.amount, 5000000);
    expect(intent.draft?.toAccountName, 'SeaBank Pribadi');
    expect(intent.needsConfirmation, isTrue);
    expect(await database.select(database.transactions).get(), isEmpty);
  });

  test('proposal klarifikasi model menjadi pertanyaan tanpa auto-save', () async {
    final gateway = _FakeGateway(
      const FfmAssistantModelProposal(
        intent: FfmAssistantIntentType.unknown,
        confidence: .96,
        missingFields: ['jenis transaksi'],
        clarification: 'Ini pemasukan atau pengeluaran?',
      ),
    );
    final interpreter = FfmAssistantInterpreter(
      database,
      modelGateway: gateway,
    );

    final intent = await interpreter.interpret(
      'catat 1000000 ke rekening BRI baru',
    );

    expect(gateway.calls, 1);
    expect(intent.type, FfmAssistantIntentType.unknown);
    expect(intent.needsClarification, isTrue);
    expect(intent.clarification, 'Ini pemasukan atau pengeluaran?');
    expect(intent.needsConfirmation, isFalse);
    expect(await database.select(database.transactions).get(), isEmpty);
  });

  test(
    'perintah nama panggilan menjadi proposal user profile tanpa auto-save',
    () async {
      final interpreter = FfmAssistantInterpreter(database);

      final intent = await interpreter.interpret('panggil saya Budi');

      expect(intent.type, FfmAssistantIntentType.teachMemory);
      expect(intent.teachingProposal?.kind, 'user_profile');
      expect(intent.teachingProposal?.valueText, 'budi');
      expect(await database.select(database.assistantMemories).get(), isEmpty);
    },
  );

  test('page context dan capability diteruskan ke model lokal', () async {
    final gateway = _FakeGateway(
      const FfmAssistantModelProposal(
        intent: FfmAssistantIntentType.help,
        confidence: .99,
      ),
    );
    final interpreter = FfmAssistantInterpreter(
      database,
      modelGateway: gateway,
    );

    await interpreter.interpret(
      'tolong pahami permintaan baru ini',
      currentDestination: FfmAssistantDestination.transactions,
      pageContext: 'Daftar transaksi bulan berjalan',
      capabilityIds: const ['read.transactions', 'draft.expense'],
    );

    expect(
      gateway.lastPageContext,
      allOf(
        contains('Daftar transaksi bulan berjalan'),
        contains('Halaman aktif: Transaksi'),
        contains('mutation wajib preview dan konfirmasi'),
      ),
    );
    expect(gateway.lastCapabilityIds, ['read.transactions', 'draft.expense']);
  });

  test('guard PIN tidak pernah diserahkan ke model lokal', () async {
    final gateway = _FakeGateway(
      const FfmAssistantModelProposal(
        intent: FfmAssistantIntentType.createExpense,
        confidence: .99,
      ),
    );
    final interpreter = FfmAssistantInterpreter(
      database,
      modelGateway: gateway,
    );

    final intent = await interpreter.interpret('tolong ganti PIN aplikasi');

    expect(gateway.calls, 0);
    expect(intent.type, FfmAssistantIntentType.openPage);
    expect(intent.destination, FfmAssistantDestination.appSecurity);
  });

  test('target navigasi dari model harus cocok dengan katalog lokal', () async {
    final gateway = _FakeGateway(
      const FfmAssistantModelProposal(
        intent: FfmAssistantIntentType.openPage,
        confidence: .99,
        actionTarget: 'hapus_database_diam_diam',
      ),
    );
    final interpreter = FfmAssistantInterpreter(
      database,
      modelGateway: gateway,
    );

    final intent = await interpreter.interpret(
      'bantu aku dengan sesuatu yang belum jelas',
    );

    expect(gateway.calls, 1);
    expect(intent.type, FfmAssistantIntentType.unknown);
    expect(intent.destination, isNull);
  });
}
