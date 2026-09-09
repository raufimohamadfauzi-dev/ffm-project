import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/transaction/data/services/voice_transaction_parser.dart';

Category _category(String id, String name) => Category(
  id: id,
  householdId: 'home-a',
  name: name,
  type: 'expense',
  defaultBudgetPeriod: 'monthly',
  isActive: true,
  createdAt: DateTime(2026, 9, 1),
);

void main() {
  test('memilih frasa kategori paling spesifik', () {
    final result = VoiceTransactionParser.parse(
      'beli kebutuhan di Shopee untuk belanja dapur',
      [_category('general', 'Belanja'), _category('kitchen', 'Belanja dapur')],
    );

    expect(result.categoryId, 'kitchen');
  });

  test('tidak mencocokkan kategori sebagai substring kata lain', () {
    final result = VoiceTransactionParser.parse('bayar di Shopee', [
      _category('farm', 'Pertanian'),
    ]);

    expect(result.categoryId, isNull);
  });
}
