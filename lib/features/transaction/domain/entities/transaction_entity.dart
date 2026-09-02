import '../../../../core/database/app_database.dart';

enum TransactionType { income, expense }

class ReceiptItemDraft {
  const ReceiptItemDraft({
    required this.name,
    required this.price,
    this.qty = 1,
  });

  final String name;
  final int price;
  final double qty;
}

class TransactionDraft {
  const TransactionDraft({
    required this.type,
    this.categoryId,
    required this.owner,
    required this.date,
    required this.amount,
    required this.note,
    this.location,
    this.source = 'manual',
    this.merchantId,
    this.accountId,
    this.goalId,
    this.partyName,
    this.receiptRawText,
    this.receiptNumber,
    this.receiptPaidAmount,
    this.receiptChangeAmount,
    required this.items,
    this.tags = const [],
    this.attachmentPaths = const [],
    this.assistantMerchantName,
    this.assistantSlmFieldValues = const <String, String>{},
  });

  final TransactionType type;
  final String? categoryId;
  final String owner;
  final DateTime date;
  final int amount;
  final String note;
  final String? location;
  final String source;
  final String? merchantId;
  final String? accountId;
  final String? goalId;
  final String? partyName;
  final String? receiptRawText;
  final String? receiptNumber;
  final int? receiptPaidAmount;
  final int? receiptChangeAmount;
  final List<ReceiptItemDraft> items;
  final List<String> tags;
  final List<String> attachmentPaths;
  final String? assistantMerchantName;
  final Map<String, String> assistantSlmFieldValues;
}

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
