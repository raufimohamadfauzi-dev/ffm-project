import 'dart:async';
import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../assistant/data/ffm_assistant_autonomy_trigger_service.dart';
import '../../../assistant/data/telegram_bot_service.dart';
import '../../../assistant/data/telegram_config_repository.dart';
import '../../../assistant/data/telegram_message_formatter.dart';
import '../entities/transaction_entity.dart';

class TransactionEntity {
  const TransactionEntity({
    required this.id,
    required this.householdId,
    required this.date,
    required this.amount,
    required this.owner,
    required this.categoryId,
    this.note,
    this.source = 'manual',
    this.sourceId,
    this.recurringTransactionId,
    this.accountId,
    this.merchantId,
    this.location,
    this.linkedActivityId,
    this.goalId,
    this.partyName,
    this.receiptRawText,
    this.receiptNumber,
    this.receiptPaidAmount,
    this.receiptChangeAmount,
    required this.recordedAt,
    this.updatedAt,
  });

  final String id;
  final String householdId;
  final DateTime date;
  final int amount;
  final String owner;
  final String? categoryId;
  final String? note;
  final String source;
  final String? sourceId;
  final String? recurringTransactionId;
  final String? accountId;
  final String? merchantId;
  final String? location;
  final String? linkedActivityId;
  final String? goalId;
  final String? partyName;
  final String? receiptRawText;
  final String? receiptNumber;
  final int? receiptPaidAmount;
  final int? receiptChangeAmount;
  final DateTime recordedAt;
  final DateTime? updatedAt;

  bool get isExpense => source != 'income';
  bool get isInternalTransfer => source == 'transfer';
  String get category => categoryId ?? '';
}

class TransactionItemEntity {
  const TransactionItemEntity({
    required this.id,
    required this.transactionId,
    required this.itemName,
    required this.price,
    this.qty = 1,
  });

  final String id;
  final String transactionId;
  final String itemName;
  final int price;
  final double qty;
}

class GetTransactions {
  const GetTransactions(this.database);
  final AppDatabase database;

  Future<List<TransactionWithItems>> call(String householdId) async {
    final rows =
        await (database.select(database.transactions)
              ..where(
                (row) =>
                    row.householdId.equals(householdId) &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.date)]))
            .get();
    if (rows.isEmpty) return const [];
    final ids = rows.map((row) => row.id).toSet();
    final itemRows = await (database.select(
      database.transactionItems,
    )..where((row) => row.transactionId.isIn(ids))).get();
    final byTransaction = <String, List<TransactionItem>>{};
    for (final item in itemRows) {
      (byTransaction[item.transactionId] ??= <TransactionItem>[]).add(item);
    }
    return rows
        .map(
          (row) => TransactionWithItems(
            transaction: row,
            items: byTransaction[row.id] ?? const [],
          ),
        )
        .toList(growable: false);
  }
}

class GetTransaction {
  const GetTransaction(this.database);
  final AppDatabase database;

  Future<TransactionWithItems?> call(String householdId, String id) async {
    final row =
        await (database.select(database.transactions)..where(
              (item) =>
                  item.householdId.equals(householdId) & item.id.equals(id),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    final items = await (database.select(
      database.transactionItems,
    )..where((item) => item.transactionId.equals(id))).get();
    return TransactionWithItems(transaction: row, items: items);
  }
}

class SaveTransaction {
  const SaveTransaction(
    this.database, {
    this.autonomyTrigger,
    this.telegramBotService,
    this.telegramConfigRepository,
  });

  final AppDatabase database;
  final FfmAssistantAutonomyTriggerService? autonomyTrigger;
  final TelegramBotService? telegramBotService;
  final TelegramConfigRepository? telegramConfigRepository;

  Future<void> call(
    TransactionEntity entity, {
    List<TransactionItemEntity> items = const [],
  }) async {
    await database.transaction(() async {
      await database
          .into(database.transactions)
          .insertOnConflictUpdate(
            TransactionsCompanion.insert(
              id: entity.id,
              householdId: entity.householdId,
              type: entity.amount >= 0 ? 'income' : 'expense',
              categoryId: Value(entity.categoryId),
              merchantId: Value(entity.merchantId),
              accountId: Value(entity.accountId),
              goalId: Value(entity.goalId),
              amount: entity.amount,
              date: entity.date,
              recordedAt: entity.recordedAt,
              note: Value(entity.note),
              owner: Value(entity.owner),
              partyName: Value(entity.partyName),
              source: Value(entity.source),
              sourceId: Value(entity.sourceId),
              linkedActivityId: Value(entity.linkedActivityId),
              recurringTransactionId: Value(entity.recurringTransactionId),
              location: Value(entity.location),
              receiptRawText: Value(entity.receiptRawText),
              receiptNumber: Value(entity.receiptNumber),
              receiptPaidAmount: Value(entity.receiptPaidAmount),
              receiptChangeAmount: Value(entity.receiptChangeAmount),
              createdAt: entity.recordedAt,
              updatedAt: Value(entity.updatedAt ?? DateTime.now()),
            ),
          );
      await (database.delete(
        database.transactionItems,
      )..where((row) => row.transactionId.equals(entity.id))).go();
      for (final item in items) {
        await database
            .into(database.transactionItems)
            .insert(
              TransactionItemsCompanion.insert(
                id: item.id,
                transactionId: item.transactionId,
                itemName: item.itemName,
                qty: Value(item.qty),
                price: Value(item.price),
                amount: Value((item.price * item.qty).round()),
                createdAt: DateTime.now(),
              ),
            );
      }
    });
    await autonomyTrigger?.emitSafely(
      triggerId:
          'transaction:${entity.id}:${(entity.updatedAt ?? entity.recordedAt).microsecondsSinceEpoch}',
      type: 'database.changed',
      householdId: entity.householdId,
      occurredAt: entity.updatedAt ?? entity.recordedAt,
      entityId: entity.id,
      payload: const {'entityType': 'transaction', 'operation': 'save'},
    );

    _notifyTelegramIfEnabled(entity);
  }

  void _notifyTelegramIfEnabled(TransactionEntity entity) {
    if (telegramBotService == null || telegramConfigRepository == null) return;
    unawaited(() async {
      try {
        final config = await telegramConfigRepository!.loadConfig();
        if (!config.isReady || !config.notifyOnNewTransaction) return;
        if (entity.amount.abs() < config.notifyMinAmount) return;

        String? categoryName;
        if (entity.categoryId != null) {
          final cat = await (database.select(database.categories)
                ..where((c) => c.id.equals(entity.categoryId!)))
              .getSingleOrNull();
          categoryName = cat?.name;
        }

        String? accountName;
        if (entity.accountId != null) {
          final acc = await (database.select(database.accounts)
                ..where((a) => a.id.equals(entity.accountId!)))
              .getSingleOrNull();
          accountName = acc?.name;
        }

        final msg = TelegramMessageFormatter.formatNewTransactionMessage(
          type: entity.amount >= 0 ? 'income' : 'expense',
          amount: entity.amount.abs(),
          categoryOrDescription: entity.note?.trim().isNotEmpty == true
              ? entity.note!
              : (categoryName ?? 'Tanpa Kategori'),
          categoryName: categoryName,
          accountName: accountName,
          recordedBy: entity.owner,
          transactionDate: entity.date,
        );

        await telegramBotService!.sendMessage(
          botToken: config.botToken,
          chatId: config.chatId,
          text: msg,
        );
      } catch (_) {}
    }());
  }
}

class SaveTransactionBatch {
  const SaveTransactionBatch(this.database, {this.autonomyTrigger});
  final AppDatabase database;
  final FfmAssistantAutonomyTriggerService? autonomyTrigger;

  Future<void> call(
    List<TransactionEntity> entities, {
    required Map<String, List<TransactionItemEntity>> itemsByTransactionId,
  }) async {
    await database.transaction(() async {
      for (final entity in entities) {
        await database
            .into(database.transactions)
            .insertOnConflictUpdate(
              TransactionsCompanion.insert(
                id: entity.id,
                householdId: entity.householdId,
                type: entity.amount >= 0 ? 'income' : 'expense',
                categoryId: Value(entity.categoryId),
                merchantId: Value(entity.merchantId),
                accountId: Value(entity.accountId),
                goalId: Value(entity.goalId),
                amount: entity.amount,
                date: entity.date,
                recordedAt: entity.recordedAt,
                note: Value(entity.note),
                owner: Value(entity.owner),
                partyName: Value(entity.partyName),
                source: Value(entity.source),
                sourceId: Value(entity.sourceId),
                recurringTransactionId: Value(entity.recurringTransactionId),
                location: Value(entity.location),
                receiptRawText: Value(entity.receiptRawText),
                receiptNumber: Value(entity.receiptNumber),
                receiptPaidAmount: Value(entity.receiptPaidAmount),
                receiptChangeAmount: Value(entity.receiptChangeAmount),
                createdAt: entity.recordedAt,
                updatedAt: Value(entity.updatedAt ?? DateTime.now()),
              ),
            );
        await (database.delete(
          database.transactionItems,
        )..where((row) => row.transactionId.equals(entity.id))).go();
        for (final item in itemsByTransactionId[entity.id] ?? const []) {
          await database
              .into(database.transactionItems)
              .insert(
                TransactionItemsCompanion.insert(
                  id: item.id,
                  transactionId: entity.id,
                  itemName: item.itemName,
                  qty: Value(item.qty),
                  price: Value(item.price),
                  amount: Value((item.price * item.qty).round()),
                  createdAt: DateTime.now(),
                ),
              );
        }
      }
    });
    for (final entity in entities) {
      await autonomyTrigger?.emitSafely(
        triggerId:
            'transaction:${entity.id}:${(entity.updatedAt ?? entity.recordedAt).microsecondsSinceEpoch}',
        type: 'database.changed',
        householdId: entity.householdId,
        occurredAt: entity.updatedAt ?? entity.recordedAt,
        entityId: entity.id,
        payload: const {'entityType': 'transaction', 'operation': 'save'},
      );
    }
  }
}

class TransferEntity {
  const TransferEntity({
    required this.id,
    required this.householdId,
    required this.date,
    required this.recordedAt,
    required this.amount,
    required this.adminFee,
    required this.feeTransactionId,
    required this.fromAccountId,
    required this.toAccountId,
    required this.note,
    required this.source,
    required this.updatedAt,
  });

  final String id;
  final String householdId;
  final DateTime date;
  final DateTime recordedAt;
  final int amount;
  final int adminFee;
  final String? feeTransactionId;
  final String fromAccountId;
  final String toAccountId;
  final String? note;
  final String source;
  final DateTime updatedAt;
}

class SaveMixedTransactionBatch {
  const SaveMixedTransactionBatch(this.database, {this.autonomyTrigger});
  final AppDatabase database;
  final FfmAssistantAutonomyTriggerService? autonomyTrigger;

  Future<void> call(
    List<TransactionEntity> entities, {
    required Map<String, List<TransactionItemEntity>> itemsByTransactionId,
    required List<TransferEntity> transfers,
  }) async {
    await database.transaction(() async {
      for (final entity in entities) {
        await database
            .into(database.transactions)
            .insertOnConflictUpdate(
              TransactionsCompanion.insert(
                id: entity.id,
                householdId: entity.householdId,
                type: entity.amount >= 0 ? 'income' : 'expense',
                categoryId: Value(entity.categoryId),
                merchantId: Value(entity.merchantId),
                accountId: Value(entity.accountId),
                goalId: Value(entity.goalId),
                amount: entity.amount,
                date: entity.date,
                recordedAt: entity.recordedAt,
                note: Value(entity.note),
                owner: Value(entity.owner),
                partyName: Value(entity.partyName),
                source: Value(entity.source),
                sourceId: Value(entity.sourceId),
                recurringTransactionId: Value(entity.recurringTransactionId),
                location: Value(entity.location),
                receiptRawText: Value(entity.receiptRawText),
                receiptNumber: Value(entity.receiptNumber),
                receiptPaidAmount: Value(entity.receiptPaidAmount),
                receiptChangeAmount: Value(entity.receiptChangeAmount),
                createdAt: entity.recordedAt,
                updatedAt: Value(entity.updatedAt),
              ),
            );
        for (final item in itemsByTransactionId[entity.id] ?? const []) {
          await database
              .into(database.transactionItems)
              .insert(
                TransactionItemsCompanion.insert(
                  id: item.id,
                  transactionId: entity.id,
                  itemName: item.itemName,
                  qty: Value(item.qty),
                  price: Value(item.price),
                  amount: Value((item.price * item.qty).round()),
                  createdAt: DateTime.now(),
                ),
              );
        }
      }
      for (final transfer in transfers) {
        await database
            .into(database.transfers)
            .insertOnConflictUpdate(
              TransfersCompanion.insert(
                id: transfer.id,
                householdId: transfer.householdId,
                date: transfer.date,
                recordedAt: transfer.recordedAt,
                amount: transfer.amount,
                adminFee: Value(transfer.adminFee),
                feeTransactionId: Value(transfer.feeTransactionId),
                fromAccountId: transfer.fromAccountId,
                toAccountId: transfer.toAccountId,
                note: Value(transfer.note),
                source: Value(transfer.source),
                updatedAt: Value(transfer.updatedAt),
              ),
            );
      }
    });
    for (final entity in entities) {
      final occurredAt = entity.updatedAt ?? entity.recordedAt;
      await autonomyTrigger?.emitSafely(
        triggerId:
            'transaction:${entity.id}:${occurredAt.microsecondsSinceEpoch}',
        type: 'database.changed',
        householdId: entity.householdId,
        occurredAt: occurredAt,
        entityId: entity.id,
        payload: const {'entityType': 'transaction', 'operation': 'save'},
      );
    }
    for (final transfer in transfers) {
      await autonomyTrigger?.emitSafely(
        triggerId:
            'transfer:${transfer.id}:${transfer.updatedAt.microsecondsSinceEpoch}',
        type: 'database.changed',
        householdId: transfer.householdId,
        occurredAt: transfer.updatedAt,
        entityId: transfer.id,
        payload: const {'entityType': 'transfer', 'operation': 'save'},
      );
    }
  }
}

class ArchiveTransaction {
  const ArchiveTransaction(this.database);
  final AppDatabase database;

  Future<void> call(String householdId, String id) async {
    await (database.update(database.transactions)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(const TransactionsCompanion(isArchived: Value(true)));
  }
}

class DeleteTransaction {
  const DeleteTransaction(this.database);
  final AppDatabase database;

  /// Menghapus dari daftar aktif secara terkontrol, tanpa physical delete yang
  /// akan memutus jejak audit dan relasi data lokal.
  Future<void> call(String householdId, String id) async {
    await (database.update(database.transactions)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(
          const TransactionsCompanion(
            isArchived: Value(true),
            isDeleted: Value(true),
          ),
        );
  }
}
