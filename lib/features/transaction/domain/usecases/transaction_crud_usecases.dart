import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../activity/data/repositories/activity_repository.dart';
import '../../../activity/domain/entities/activity_entity.dart';
import '../../../assistant/data/ffm_assistant_autonomy_trigger_service.dart';
import '../../../assistant/data/telegram_config_repository.dart';
import '../../../assistant/data/telegram_delivery_processor.dart';
import '../../../assistant/data/telegram_delivery_repository.dart';
import '../../../assistant/data/telegram_message_formatter.dart';
import '../../../liability/domain/usecases/process_debt_payment.dart';
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

  TransactionEntity copyWith({
    String? id,
    String? householdId,
    DateTime? date,
    int? amount,
    String? owner,
    String? categoryId,
    String? note,
    String? source,
    String? sourceId,
    String? recurringTransactionId,
    String? accountId,
    String? merchantId,
    String? location,
    String? linkedActivityId,
    String? goalId,
    String? partyName,
    String? receiptRawText,
    String? receiptNumber,
    int? receiptPaidAmount,
    int? receiptChangeAmount,
    DateTime? recordedAt,
    DateTime? updatedAt,
  }) {
    return TransactionEntity(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      date: date ?? this.date,
      amount: amount ?? this.amount,
      owner: owner ?? this.owner,
      categoryId: categoryId ?? this.categoryId,
      note: note ?? this.note,
      source: source ?? this.source,
      sourceId: sourceId ?? this.sourceId,
      recurringTransactionId:
          recurringTransactionId ?? this.recurringTransactionId,
      accountId: accountId ?? this.accountId,
      merchantId: merchantId ?? this.merchantId,
      location: location ?? this.location,
      linkedActivityId: linkedActivityId ?? this.linkedActivityId,
      goalId: goalId ?? this.goalId,
      partyName: partyName ?? this.partyName,
      receiptRawText: receiptRawText ?? this.receiptRawText,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      receiptPaidAmount: receiptPaidAmount ?? this.receiptPaidAmount,
      receiptChangeAmount: receiptChangeAmount ?? this.receiptChangeAmount,
      recordedAt: recordedAt ?? this.recordedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
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
                    row.isArchived.equals(false) &
                    row.isDeleted.equals(false),
              )
              ..orderBy([
                (row) => OrderingTerm.desc(row.date),
                (row) => OrderingTerm.desc(row.id),
              ]))
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

class TransactionPageResult {
  const TransactionPageResult({
    required this.items,
    required this.hasMore,
    required this.totalCount,
  });

  final List<TransactionWithItems> items;
  final bool hasMore;
  final int totalCount;
}

class GetTransactionsPage {
  const GetTransactionsPage(this.database);
  final AppDatabase database;

  Future<TransactionPageResult> call(
    String householdId, {
    int limit = 80,
    int offset = 0,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final query = database.select(database.transactions)
      ..where(
        (row) =>
            row.householdId.equals(householdId) &
            row.isArchived.equals(false) &
            row.isDeleted.equals(false),
      );
    if (startDate != null) {
      query.where((row) => row.date.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where((row) => row.date.isSmallerThanValue(endDate));
    }
    final countQuery = database.selectOnly(database.transactions)
      ..addColumns([database.transactions.id.count()])
      ..where(
        database.transactions.householdId.equals(householdId) &
        database.transactions.isArchived.equals(false) &
        database.transactions.isDeleted.equals(false),
      );
    if (startDate != null) {
      countQuery.where(
        database.transactions.date.isBiggerOrEqualValue(startDate),
      );
    }
    if (endDate != null) {
      countQuery.where(
        database.transactions.date.isSmallerThanValue(endDate),
      );
    }
    final countResult = await countQuery.getSingle();
    final totalCount =
        countResult.read(database.transactions.id.count()) ?? 0;

    query
      ..orderBy([
        (row) => OrderingTerm.desc(row.date),
        (row) => OrderingTerm.desc(row.id),
      ])
      ..limit(limit, offset: offset);
    final rows = await query.get();
    if (rows.isEmpty) {
      return TransactionPageResult(
        items: const [],
        hasMore: false,
        totalCount: totalCount,
      );
    }
    final ids = rows.map((row) => row.id).toSet();
    final itemRows = await (database.select(
      database.transactionItems,
    )..where((row) => row.transactionId.isIn(ids))).get();
    final byTransaction = <String, List<TransactionItem>>{};
    for (final item in itemRows) {
      (byTransaction[item.transactionId] ??= <TransactionItem>[]).add(item);
    }
    return TransactionPageResult(
      items: rows
          .map(
            (row) => TransactionWithItems(
              transaction: row,
              items: byTransaction[row.id] ?? const [],
            ),
          )
          .toList(growable: false),
      hasMore: offset + limit < totalCount,
      totalCount: totalCount,
    );
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
  SaveTransaction(
    this.database, {
    this.autonomyTrigger,
    this.telegramConfigRepository,
    this.telegramDeliveryRepository,
    this.telegramDeliveryProcessor,
    this.activityRepository,
  });

  final AppDatabase database;
  final FfmAssistantAutonomyTriggerService? autonomyTrigger;
  final TelegramConfigRepository? telegramConfigRepository;
  final TelegramDeliveryRepository? telegramDeliveryRepository;
  final TelegramDeliveryProcessor? telegramDeliveryProcessor;
  final ActivityRepository? activityRepository;

  Future<void> call(
    TransactionEntity entity, {
    List<TransactionItemEntity> items = const [],
  }) async {
    var effectiveEntity = entity;
    // Only auto-link to active session for new transactions (not edits)
    if (effectiveEntity.linkedActivityId == null &&
        effectiveEntity.sourceId == null &&
        effectiveEntity.recurringTransactionId == null &&
        activityRepository != null) {
      try {
        final activeSessions = await activityRepository!.getActiveSessions(
          effectiveEntity.householdId,
        );
        final activeSession = activeSessions.lastOrNull;
        if (activeSession != null) {
          effectiveEntity = effectiveEntity.copyWith(
            linkedActivityId: activeSession.id,
          );
          final absAmount = effectiveEntity.amount.abs();
          final title = effectiveEntity.note?.trim().isNotEmpty == true
              ? effectiveEntity.note!.trim()
              : (effectiveEntity.isExpense ? 'Pengeluaran' : 'Pemasukan');
          final existingCps = await activityRepository!.getCheckpoints(
            activeSession.id,
          );
          await activityRepository!.saveCheckpoint(
            ActivityCheckpointEntity(
              id: const Uuid().v4(),
              sessionId: activeSession.id,
              label:
                  '[🤖 Otonom] $title (Rp ${formatRupiahInput(absAmount.toString())})',
              place: effectiveEntity.location,
              occurredAt: effectiveEntity.date,
              sequence: existingCps.length + 1,
              createdAt: DateTime.now(),
            ),
          );
        }
      } catch (_) {
        // Abaikan error korelasi otonom agar penyimpanan transaksi utama tidak terhambat
      }
    }

    final existingTx = await (database.select(
      database.transactions,
    )..where((t) => t.id.equals(effectiveEntity.id))).getSingleOrNull();
    final isNew = existingTx == null;

    // Susun rencana pengiriman Telegram (jika kebijakan mengizinkan) SEBELUM
    // commit. Baris antrean dimasukkan dalam transaksi yang sama sehingga
    // "pesan terdaftar" dan "transaksi tersimpan" selalu konsisten.
    final deliveryConfig = await _loadPermittedTelegramConfig(
      telegramConfigRepository,
    );
    final deliveryPlan = await _buildTransactionDeliveryPlan(
      deliveryRepository: telegramDeliveryRepository,
      config: deliveryConfig,
      entity: effectiveEntity,
      isNew: isNew,
      database: database,
    );

    await database.transaction(() async {
      await database
          .into(database.transactions)
          .insertOnConflictUpdate(
            TransactionsCompanion.insert(
              id: effectiveEntity.id,
              householdId: effectiveEntity.householdId,
              type: effectiveEntity.amount >= 0 ? 'income' : 'expense',
              categoryId: Value(effectiveEntity.categoryId),
              merchantId: Value(effectiveEntity.merchantId),
              accountId: Value(effectiveEntity.accountId),
              goalId: Value(effectiveEntity.goalId),
              amount: effectiveEntity.amount,
              date: effectiveEntity.date,
              recordedAt: effectiveEntity.recordedAt,
              note: Value(effectiveEntity.note),
              owner: Value(effectiveEntity.owner),
              partyName: Value(effectiveEntity.partyName),
              source: Value(effectiveEntity.source),
              sourceId: Value(effectiveEntity.sourceId),
              linkedActivityId: Value(effectiveEntity.linkedActivityId),
              recurringTransactionId: Value(
                effectiveEntity.recurringTransactionId,
              ),
              location: Value(effectiveEntity.location),
              receiptRawText: Value(effectiveEntity.receiptRawText),
              receiptNumber: Value(effectiveEntity.receiptNumber),
              receiptPaidAmount: Value(effectiveEntity.receiptPaidAmount),
              receiptChangeAmount: Value(effectiveEntity.receiptChangeAmount),
              createdAt: effectiveEntity.recordedAt,
              updatedAt: Value(effectiveEntity.updatedAt ?? DateTime.now()),
            ),
          );
      await (database.delete(
        database.transactionItems,
      )..where((row) => row.transactionId.equals(effectiveEntity.id))).go();
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
      if (deliveryPlan != null) {
        // Queue and transaction share the same commit boundary. If the queue
        // cannot be persisted, do not report a successful save that can never
        // produce the requested notification.
        await deliveryPlan.enqueue(DateTime.now());
      }
    });
    await _processTelegramAfterCommit(
      telegramDeliveryProcessor,
      deliveryPlan != null,
      telegramConfigRepository,
      householdId: effectiveEntity.householdId,
    );
    await autonomyTrigger?.emitSafely(
      triggerId:
          'transaction:${effectiveEntity.id}:${(effectiveEntity.updatedAt ?? effectiveEntity.recordedAt).microsecondsSinceEpoch}',
      type: 'database.changed',
      householdId: effectiveEntity.householdId,
      occurredAt: effectiveEntity.updatedAt ?? effectiveEntity.recordedAt,
      entityId: effectiveEntity.id,
      payload: const {'entityType': 'transaction', 'operation': 'save'},
    );
  }
}

/// Rencana pengiriman Telegram yang siap diantrekan setelah commit.
class TelegramDeliveryPlan {
  const TelegramDeliveryPlan({
    required this.repository,
    required this.deliveryId,
    required this.householdId,
    required this.operation,
    required this.messageText,
    this.entityId,
    this.dedupeKey,
    this.credentialFingerprint,
  });

  final TelegramDeliveryRepository repository;
  final String deliveryId;
  final String householdId;
  final String operation;
  final String messageText;
  final String? entityId;
  final String? dedupeKey;
  final String? credentialFingerprint;

  Future<bool> enqueue(DateTime now) => repository.enqueue(
    deliveryId: deliveryId,
    householdId: householdId,
    operation: operation,
    messageText: messageText,
    entityId: entityId,
    dedupeKey: dedupeKey,
    credentialFingerprint: credentialFingerprint,
    createdAt: now,
  );
}

/// Memuat konfigurasi Telegram bila integrasi aktif dan notifikasi transaksi
/// diizinkan. Gagal membaca storage tidak menghentikan penyimpanan transaksi.
Future<TelegramConfig?> _loadPermittedTelegramConfig(
  TelegramConfigRepository? repository,
) async {
  if (repository == null) return null;
  try {
    final config = await repository.loadConfig();
    if (!config.isReady || !config.notifyOnNewTransaction) return null;
    return config;
  } catch (_) {
    return null;
  }
}

/// Menyusun rencana pengiriman durabel untuk satu transaksi bila kebijakan
/// dan ambang nominal mengizinkan. Pesan diformat dari data domain yang baru
/// di-commit (bukan hasil imajinasi model) agar retry memakai salinan yang
/// persis sama.
Future<TelegramDeliveryPlan?> _buildTransactionDeliveryPlan({
  required TelegramDeliveryRepository? deliveryRepository,
  required TelegramConfig? config,
  required TransactionEntity entity,
  required bool isNew,
  required AppDatabase database,
}) async {
  if (deliveryRepository == null || config == null) return null;
  if (entity.amount.abs() < config.notifyMinAmount) return null;

  String? categoryName;
  if (entity.categoryId != null) {
    final cat = await (database.select(
      database.categories,
    )..where((c) => c.id.equals(entity.categoryId!))).getSingleOrNull();
    categoryName = cat?.name;
  }

  String? accountName;
  if (entity.accountId != null) {
    final acc = await (database.select(
      database.accounts,
    )..where((a) => a.id.equals(entity.accountId!))).getSingleOrNull();
    accountName = acc?.name;
  }

  final categoryOrDescription = entity.note?.trim().isNotEmpty == true
      ? entity.note!
      : (categoryName ?? 'Tanpa Kategori');
  final msg = isNew
      ? TelegramMessageFormatter.formatNewTransactionMessage(
          type: entity.amount >= 0 ? 'income' : 'expense',
          amount: entity.amount.abs(),
          categoryOrDescription: categoryOrDescription,
          categoryName: categoryName,
          accountName: accountName,
          recordedBy: entity.owner,
          transactionDate: entity.date,
        )
      : TelegramMessageFormatter.formatEditTransactionMessage(
          type: entity.amount >= 0 ? 'income' : 'expense',
          amount: entity.amount.abs(),
          categoryOrDescription: categoryOrDescription,
          categoryName: categoryName,
          accountName: accountName,
          recordedBy: entity.owner,
          transactionDate: entity.date,
        );

  final stamp = (entity.updatedAt ?? entity.recordedAt).microsecondsSinceEpoch;
  final id = 'telegram:transaction:${entity.id}:$stamp';
  return TelegramDeliveryPlan(
    repository: deliveryRepository,
    deliveryId: id,
    dedupeKey: id,
    operation: isNew ? 'transaction.new' : 'transaction.edit',
    entityId: entity.id,
    householdId: entity.householdId,
    messageText: msg,
    credentialFingerprint: TelegramConfigRepository.credentialFingerprintFor(
      config.botToken,
      config.chatId,
    ),
  );
}

class SaveTransactionBatch {
  const SaveTransactionBatch(
    this.database, {
    this.autonomyTrigger,
    this.telegramConfigRepository,
    this.telegramDeliveryRepository,
    this.telegramDeliveryProcessor,
  });
  final AppDatabase database;
  final FfmAssistantAutonomyTriggerService? autonomyTrigger;
  final TelegramConfigRepository? telegramConfigRepository;
  final TelegramDeliveryRepository? telegramDeliveryRepository;
  final TelegramDeliveryProcessor? telegramDeliveryProcessor;

  Future<void> call(
    List<TransactionEntity> entities, {
    required Map<String, List<TransactionItemEntity>> itemsByTransactionId,
  }) async {
    final deliveryConfig = await _loadPermittedTelegramConfig(
      telegramConfigRepository,
    );
    var hasTelegramDelivery = false;
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
        if (deliveryConfig != null) {
          final plan = await _buildTransactionDeliveryPlan(
            deliveryRepository: telegramDeliveryRepository,
            config: deliveryConfig,
            entity: entity,
            isNew: true,
            database: database,
          );
          if (plan != null) {
            await plan.enqueue(DateTime.now());
            hasTelegramDelivery = true;
          }
        }
      }
    });
    await _processTelegramAfterCommit(
      telegramDeliveryProcessor,
      hasTelegramDelivery,
      telegramConfigRepository,
      householdId: entities.isEmpty ? null : entities.first.householdId,
    );
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
  const SaveMixedTransactionBatch(
    this.database, {
    this.autonomyTrigger,
    this.telegramConfigRepository,
    this.telegramDeliveryRepository,
    this.telegramDeliveryProcessor,
  });
  final AppDatabase database;
  final FfmAssistantAutonomyTriggerService? autonomyTrigger;
  final TelegramConfigRepository? telegramConfigRepository;
  final TelegramDeliveryRepository? telegramDeliveryRepository;
  final TelegramDeliveryProcessor? telegramDeliveryProcessor;

  Future<void> call(
    List<TransactionEntity> entities, {
    required Map<String, List<TransactionItemEntity>> itemsByTransactionId,
    required List<TransferEntity> transfers,
  }) async {
    final deliveryConfig = await _loadPermittedTelegramConfig(
      telegramConfigRepository,
    );
    var hasTelegramDelivery = false;
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
        if (deliveryConfig != null) {
          final plan = await _buildTransactionDeliveryPlan(
            deliveryRepository: telegramDeliveryRepository,
            config: deliveryConfig,
            entity: entity,
            isNew: true,
            database: database,
          );
          if (plan != null) {
            await plan.enqueue(DateTime.now());
            hasTelegramDelivery = true;
          }
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
    await _processTelegramAfterCommit(
      telegramDeliveryProcessor,
      hasTelegramDelivery,
      telegramConfigRepository,
      householdId: entities.isEmpty ? null : entities.first.householdId,
    );
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

Future<void> _processTelegramAfterCommit(
  TelegramDeliveryProcessor? processor,
  bool hasDelivery,
  TelegramConfigRepository? configRepository, {
  String? householdId,
}) async {
  if (processor == null || !hasDelivery) return;
  try {
    await configRepository?.recordDeliveryStatus(
      status: TelegramDeliveryStatus.pending,
      message: 'Notifikasi transaksi sedang dikirim ke Telegram.',
    );
    await processor.processPending(
      householdId: householdId ?? 'local-household',
    );
  } catch (error) {
    try {
      await configRepository?.recordDeliveryStatus(
        status: TelegramDeliveryStatus.failed,
        message: 'Pengiriman Telegram tertunda: $error',
      );
    } catch (_) {}
  }
}

class ArchiveTransaction {
  ArchiveTransaction(this.database);
  final AppDatabase database;

  Future<void> call(String householdId, String id) async {
    final now = DateTime.now();

    // Rollback debt payment if this is a payment transaction
    try {
      await RollbackDebtPayment(database)
          .call(householdId: householdId, transactionId: id);
    } catch (_) {
      // Ignore rollback errors (not a payment transaction or other issues)
    }

    await (database.update(database.transactions)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(
          TransactionsCompanion(
            isArchived: const Value(true),
            updatedAt: Value(now),
          ),
        );
  }
}

class DeleteTransaction {
  DeleteTransaction(this.database);
  final AppDatabase database;

  /// Menghapus dari daftar aktif secara terkontrol, tanpa physical delete yang
  /// akan memutus jejak audit dan relasi data lokal.
  Future<void> call(String householdId, String id) async {
    final now = DateTime.now();

    // Rollback debt payment if this is a payment transaction
    try {
      await RollbackDebtPayment(database)
          .call(householdId: householdId, transactionId: id);
    } catch (_) {
      // Ignore rollback errors (not a payment transaction or other issues)
    }

    await (database.update(database.transactions)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(
          TransactionsCompanion(
            isArchived: const Value(true),
            isDeleted: const Value(true),
            updatedAt: Value(now),
          ),
        );
  }
}

class TransferPageResult {
  const TransferPageResult({
    required this.items,
    required this.hasMore,
    required this.totalCount,
  });

  final List<Transfer> items;
  final bool hasMore;
  final int totalCount;
}

class GetTransfersPage {
  const GetTransfersPage(this.database);
  final AppDatabase database;

  Future<TransferPageResult> call(
    String householdId, {
    int limit = 80,
    int offset = 0,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final query = database.select(database.transfers)
      ..where(
        (row) =>
            row.householdId.equals(householdId) &
            row.isDeleted.equals(false),
      );
    if (startDate != null) {
      query.where((row) => row.date.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where((row) => row.date.isSmallerThanValue(endDate));
    }
    final countQuery = database.selectOnly(database.transfers)
      ..addColumns([database.transfers.id.count()])
      ..where(
        database.transfers.householdId.equals(householdId) &
        database.transfers.isDeleted.equals(false),
      );
    if (startDate != null) {
      countQuery.where(
        database.transfers.date.isBiggerOrEqualValue(startDate),
      );
    }
    if (endDate != null) {
      countQuery.where(
        database.transfers.date.isSmallerThanValue(endDate),
      );
    }
    final countResult = await countQuery.getSingle();
    final totalCount = countResult.read(database.transfers.id.count()) ?? 0;

    query
      ..orderBy([
        (row) => OrderingTerm.desc(row.date),
        (row) => OrderingTerm.desc(row.id),
      ])
      ..limit(limit, offset: offset);
    final rows = await query.get();
    return TransferPageResult(
      items: rows,
      hasMore: offset + limit < totalCount,
      totalCount: totalCount,
    );
  }
}
