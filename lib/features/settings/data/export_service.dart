import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../../transaction/domain/usecases/transaction_crud_usecases.dart';

class ExportFilterOptions {
  const ExportFilterOptions({
    required this.includeFinance,
    required this.includeMetadata,
    this.startDate,
    this.endDate,
  });

  final bool includeFinance;
  final bool includeMetadata;
  final DateTime? startDate;
  final DateTime? endDate;
}

class DataExportService {
  const DataExportService(this.database);

  final AppDatabase database;

  Future<String> exportFilteredJson(
    String householdId,
    ExportFilterOptions options,
  ) async {
    final records = await GetTransactions(database)(householdId);
    final filtered = records.where((entry) {
      final date = entry.transaction.date;
      if (options.startDate != null && date.isBefore(options.startDate!)) {
        return false;
      }
      if (options.endDate != null &&
          date.isAfter(options.endDate!.add(const Duration(days: 1)))) {
        return false;
      }
      return true;
    }).toList();

    final result = <String, Object?>{
      'formatVersion': 'ffm-v21-filtered',
      'scope': 'filtered_analysis',
      'isBackup': false,
      'canRestore': false,
      'householdId': householdId,
      'exportedAt': DateTime.now().toIso8601String(),
      'filter': {
        'includeFinance': options.includeFinance,
        'includeMetadata': options.includeMetadata,
        'startDate': options.startDate?.toIso8601String(),
        'endDate': options.endDate?.toIso8601String(),
      },
    };
    if (options.includeFinance) {
      result['transactions'] = filtered.map((entry) {
        final transaction = entry.transaction;
        return {
          'id': transaction.id,
          'type': transaction.type,
          'amount': transaction.amount,
          'date': transaction.date.toIso8601String(),
          'recordedAt': transaction.recordedAt.toIso8601String(),
          'categoryId': transaction.categoryId,
          'merchantId': transaction.merchantId,
          'accountId': transaction.accountId,
          'goalId': transaction.goalId,
          'partyName': transaction.partyName,
          'owner': transaction.owner,
          'note': transaction.note,
          'location': transaction.location,
          'source': transaction.source,
          'items': entry.items
              .map(
                (item) => {
                  'name': item.itemName,
                  'qty': item.qty,
                  'unit': item.unit,
                  'price': item.price,
                  'amount': item.amount,
                },
              )
              .toList(),
        };
      }).toList();
    }
    if (options.includeMetadata) {
      final categories = await (database.select(
        database.categories,
      )..where((item) => item.householdId.equals(householdId))).get();
      final merchants = await (database.select(
        database.merchants,
      )..where((item) => item.householdId.equals(householdId))).get();
      final tags = await (database.select(
        database.tags,
      )..where((item) => item.householdId.equals(householdId))).get();
      final accounts = await (database.select(
        database.accounts,
      )..where((item) => item.householdId.equals(householdId))).get();
      result['dataUtama'] = {
        'categories': categories
            .map(
              (item) => {
                'id': item.id,
                'name': item.name,
                'type': item.type,
                'isActive': item.isActive,
              },
            )
            .toList(),
        'merchants': merchants
            .map(
              (item) => {
                'id': item.id,
                'name': item.name,
                'details': item.details,
                'isActive': item.isActive,
              },
            )
            .toList(),
        'tags': tags
            .map(
              (item) => {
                'id': item.id,
                'name': item.name,
                'isArchived': item.isArchived,
              },
            )
            .toList(),
        'accounts': accounts
            .map(
              (item) => {
                'id': item.id,
                'name': item.name,
                'type': item.type,
                'isActive': item.isActive,
                'isArchived': item.isArchived,
              },
            )
            .toList(),
      };
    }
    result['includedModules'] = [
      if (options.includeFinance) 'transactions',
      if (options.includeMetadata) 'dataUtama',
    ];
    result['catatan'] = 'Berkas ini hanya untuk analisa eksternal, bukan cadangan pemulihan. Cek kembali privasi sebelum membagikannya.';
    return const JsonEncoder.withIndent('  ').convert(result);
  }
}
