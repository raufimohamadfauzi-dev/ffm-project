import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_financial_education.dart';

void main() {
  const service = FfmAssistantFinancialEducationService();

  test('cara menabung diarahkan ke Goals dan tidak mengarang data pribadi', () {
    final answer = service.answer(
      'bagaimana cara menabung untuk dana darurat?',
    );

    expect(answer, isNotNull);
    expect(answer!.topic, FfmAssistantFinancialTopic.saving);
    expect(answer.destination, 'Goals');
    expect(answer.message, contains('data pemasukan dan pengeluaran'));
  });

  test('budgeting diarahkan ke Budget', () {
    final answer = service.answer('bagaimana cara membuat budgeting keluarga?');

    expect(answer, isNotNull);
    expect(answer!.topic, FfmAssistantFinancialTopic.budgeting);
    expect(answer.destination, 'Budget');
  });

  test('topik tidak terkait tidak dijawab oleh service edukasi', () {
    expect(service.answer('bagaimana cara budidaya ikan lele?'), isNull);
  });
}
