import '../../../../core/database/app_database.dart';

class TransactionWithItems {
  const TransactionWithItems({
    required this.transaction,
    this.items = const [],
    this.tags = const [],
  });

  final Transaction transaction;
  final List<TransactionItem> items;
  final List<String> tags;
}
