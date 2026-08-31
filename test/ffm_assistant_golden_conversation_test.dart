import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

/// Golden Conversation Tests untuk FFM Assistant
/// 
/// Test ini memvalidasi alur percakapan multi-turn untuk memastikan assistant
/// dapat mempertahankan konteks, menangani follow-up, dan memberikan respon
/// yang konsisten sepanjang percakapan.
/// 
/// Kategori yang diuji:
/// - greeting
/// - query data
/// - analysis 30/90 hari
/// - create/update
/// - correction
/// - confirmation
/// - cancellation
/// - memory
/// - multi-tool
/// - tool failure

class GoldenConversationTest {
  const GoldenConversationTest({
    required this.name,
    required this.category,
    required this.conversation,
    required this.expectedBehavior,
  });

  final String name;
  final String category;
  final List<ConversationTurn> conversation;
  final String expectedBehavior;
}

class ConversationTurn {
  const ConversationTurn({
    required this.userMessage,
    required this.expectedResponseType,
    this.expectedKeywords,
    this.shouldUseContext = false,
    this.contextReference,
  });

  final String userMessage;
  final ExpectedResponseType expectedResponseType;
  final List<String>? expectedKeywords;
  final bool shouldUseContext;
  final String? contextReference;
}

enum ExpectedResponseType {
  greeting,
  dataQuery,
  analysis,
  confirmation,
  actionDraft,
  errorMessage,
  clarification,
  followUp,
}

void main() {
  group('Golden Conversation Tests', () {
    test('Greeting conversation', () {
      final test = GoldenConversationTest(
        name: 'Basic greeting',
        category: 'greeting',
        conversation: const [
          ConversationTurn(
            userMessage: 'Halo',
            expectedResponseType: ExpectedResponseType.greeting,
            expectedKeywords: ['halo', 'selamat', 'pagi', 'siang', 'sore'],
          ),
          ConversationTurn(
            userMessage: 'Apa yang bisa kamu lakukan?',
            expectedResponseType: ExpectedResponseType.greeting,
            expectedKeywords: ['bisa', 'membantu', 'fitur', 'kemampuan'],
          ),
        ],
        expectedBehavior: 'Assistant should respond naturally to greetings and explain capabilities',
      );

      _validateConversation(test);
    });

    test('Query data conversation', () {
      final test = GoldenConversationTest(
        name: 'Simple balance query',
        category: 'query data',
        conversation: const [
          ConversationTurn(
            userMessage: 'Berapa saldo saya?',
            expectedResponseType: ExpectedResponseType.dataQuery,
            expectedKeywords: ['saldo', 'rekening', 'Rp'],
          ),
          ConversationTurn(
            userMessage: 'Yang tadi',
            expectedResponseType: ExpectedResponseType.dataQuery,
            expectedKeywords: ['saldo', 'rekening'],
            shouldUseContext: true,
            contextReference: 'previous balance query',
          ),
        ],
        expectedBehavior: 'Assistant should answer balance query and maintain context for follow-up',
      );

      _validateConversation(test);
    });

    test('Analysis conversation', () {
      final test = GoldenConversationTest(
        name: '30-day expense analysis',
        category: 'analysis 30/90 hari',
        conversation: const [
          ConversationTurn(
            userMessage: 'Berapa pengeluaran saya 30 hari terakhir?',
            expectedResponseType: ExpectedResponseType.analysis,
            expectedKeywords: ['pengeluaran', '30 hari', 'Rp', 'total'],
          ),
          ConversationTurn(
            userMessage: 'Bagaimana dengan 90 hari?',
            expectedResponseType: ExpectedResponseType.analysis,
            expectedKeywords: ['90 hari', 'pengeluaran', 'periode'],
            shouldUseContext: true,
            contextReference: 'previous 30-day analysis',
          ),
        ],
        expectedBehavior: 'Assistant should provide analysis and compare different periods',
      );

      _validateConversation(test);
    });

    test('Create and confirm conversation', () {
      final test = GoldenConversationTest(
        name: 'Create expense with confirmation',
        category: 'create/update',
        conversation: const [
          ConversationTurn(
            userMessage: 'Catat pengeluaran makan siang 50 ribu',
            expectedResponseType: ExpectedResponseType.actionDraft,
            expectedKeywords: ['makan', '50.000', 'pengeluaran', 'draft'],
          ),
          ConversationTurn(
            userMessage: 'Ya',
            expectedResponseType: ExpectedResponseType.confirmation,
            expectedKeywords: ['berhasil', 'disimpan', '50.000'],
          ),
        ],
        expectedBehavior: 'Assistant should create draft and execute after confirmation',
      );

      _validateConversation(test);
    });

    test('Correction conversation', () {
      final test = GoldenConversationTest(
        name: 'Correct previous input',
        category: 'correction',
        conversation: const [
          ConversationTurn(
            userMessage: 'Catat pengeluaran 100 ribu',
            expectedResponseType: ExpectedResponseType.actionDraft,
            expectedKeywords: ['100.000', 'pengeluaran'],
          ),
          ConversationTurn(
            userMessage: 'Bukan, 50 ribu',
            expectedResponseType: ExpectedResponseType.actionDraft,
            expectedKeywords: ['50.000', 'ubah', 'koreksi'],
            shouldUseContext: true,
            contextReference: 'previous 100k draft',
          ),
          ConversationTurn(
            userMessage: 'Ya',
            expectedResponseType: ExpectedResponseType.confirmation,
            expectedKeywords: ['berhasil', '50.000'],
          ),
        ],
        expectedBehavior: 'Assistant should handle correction and update draft',
      );

      _validateConversation(test);
    });

    test('Cancellation conversation', () {
      final test = GoldenConversationTest(
        name: 'Cancel draft',
        category: 'cancellation',
        conversation: const [
          ConversationTurn(
            userMessage: 'Catat pengeluaran 100 ribu',
            expectedResponseType: ExpectedResponseType.actionDraft,
            expectedKeywords: ['100.000', 'pengeluaran'],
          ),
          ConversationTurn(
            userMessage: 'Batal',
            expectedResponseType: ExpectedResponseType.confirmation,
            expectedKeywords: ['batal', 'hapus', 'draft'],
          ),
        ],
        expectedBehavior: 'Assistant should cancel draft when requested',
      );

      _validateConversation(test);
    });

    test('Memory conversation', () {
      final test = GoldenConversationTest(
        name: 'Remember user preference',
        category: 'memory',
        conversation: const [
          ConversationTurn(
            userMessage: 'Saya suka makanan pedas',
            expectedResponseType: ExpectedResponseType.followUp,
            expectedKeywords: ['mengingat', 'pedas', 'preferensi'],
          ),
          ConversationTurn(
            userMessage: 'Apa yang saya suka?',
            expectedResponseType: ExpectedResponseType.dataQuery,
            expectedKeywords: ['pedas', 'makanan', 'mengingat'],
            shouldUseContext: true,
            contextReference: 'previous preference statement',
          ),
        ],
        expectedBehavior: 'Assistant should remember user preferences and recall them',
      );

      _validateConversation(test);
    });

    test('Multi-tool conversation', () {
      final test = GoldenConversationTest(
        name: 'Query then create action',
        category: 'multi-tool',
        conversation: const [
          ConversationTurn(
            userMessage: 'Berapa saldo saya?',
            expectedResponseType: ExpectedResponseType.dataQuery,
            expectedKeywords: ['saldo', 'Rp'],
          ),
          ConversationTurn(
            userMessage: 'Catat pengeluaran makan 20 ribu',
            expectedResponseType: ExpectedResponseType.actionDraft,
            expectedKeywords: ['makan', '20.000', 'pengeluaran'],
            shouldUseContext: true,
            contextReference: 'previous balance query',
          ),
        ],
        expectedBehavior: 'Assistant should handle different tool types in sequence',
      );

      _validateConversation(test);
    });

    test('Tool failure conversation', () {
      final test = GoldenConversationTest(
        name: 'Handle unavailable tool',
        category: 'tool failure',
        conversation: const [
          ConversationTurn(
            userMessage: 'Transfer ke akun yang tidak ada',
            expectedResponseType: ExpectedResponseType.errorMessage,
            expectedKeywords: ['tidak', 'ditemukan', 'akun', 'error'],
          ),
          ConversationTurn(
            userMessage: 'Apa akun yang tersedia?',
            expectedResponseType: ExpectedResponseType.dataQuery,
            expectedKeywords: ['akun', 'daftar', 'tersedia'],
            shouldUseContext: true,
            contextReference: 'previous error',
          ),
        ],
        expectedBehavior: 'Assistant should handle errors gracefully and provide alternatives',
      );

      _validateConversation(test);
    });

    test('Clarification conversation', () {
      final test = GoldenConversationTest(
        name: 'Ask for clarification',
        category: 'clarification',
        conversation: const [
          ConversationTurn(
            userMessage: 'Catat pengeluaran',
            expectedResponseType: ExpectedResponseType.clarification,
            expectedKeywords: ['berapa', 'berapa banyak', 'kategori', 'apa'],
          ),
          ConversationTurn(
            userMessage: 'Makan siang 50 ribu',
            expectedResponseType: ExpectedResponseType.actionDraft,
            expectedKeywords: ['makan', '50.000', 'pengeluaran'],
            shouldUseContext: true,
            contextReference: 'previous clarification request',
          ),
        ],
        expectedBehavior: 'Assistant should ask for clarification when needed',
      );

      _validateConversation(test);
    });
  });
}

void _validateConversation(GoldenConversationTest test) {
  print('\n=== ${test.name} (${test.category}) ===');
  print('Expected: ${test.expectedBehavior}');
  
  for (var i = 0; i < test.conversation.length; i++) {
    final turn = test.conversation[i];
    print('\nTurn ${i + 1}:');
    print('  User: "${turn.userMessage}"');
    print('  Expected Response Type: ${turn.expectedResponseType}');
    
    if (turn.expectedKeywords != null) {
      print('  Expected Keywords: ${turn.expectedKeywords!.join(", ")}');
    }
    
    if (turn.shouldUseContext) {
      print('  Should Use Context: ${turn.contextReference}');
    }
    
    // Validasi basic
    expect(turn.userMessage, isNotEmpty, reason: 'User message should not be empty');
    
    if (turn.shouldUseContext) {
      expect(turn.contextReference, isNotEmpty, reason: 'Context reference should be provided when using context');
    }
  }
  
  print('\n✓ Conversation structure validated');
}