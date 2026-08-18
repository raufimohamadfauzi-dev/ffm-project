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

  Future<String> exportFilteredJson(String householdId, ExportFilterOptions options) async {
    final records = await GetTransactions(database)(householdId);
    final filtered = records.where((entry) {
      final date = entry.transaction.date;
      if (options.startDate != null && date.isBefore(options.startDate!)) return false;
      if (options.endDate != null && date.isAfter(options.endDate!.add(const Duration(days: 1)))) return false;
      return true;
    }).toList();

    final result = <String, Object?>{
      'formatVersion': 'ffm-v20-filtered',
      'householdId': householdId,
      'exportedAt': DateTime.now().toIso8601String(),
      'filter': {
        'includeFinance': options.includeFinance,
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
          'items': entry.items.map((item) => {
                'name': item.itemName,
                'qty': item.qty,
                'unit': item.unit,
                'price': item.price,
                'amount': item.amount,
              }).toList(),
        };
      }).toList();
    }
    if (options.includeMetadata) {
      final categories = await database.select(database.categories).get();
      final merchants = await database.select(database.merchants).get();
      final tags = await database.select(database.tags).get();
      final accounts = await database.select(database.accounts).get();
      result['dataUtama'] = {
        'categories': categories.map((item) => {'id': item.id, 'name': item.name, 'type': item.type}).toList(),
        'merchants': merchants.map((item) => {'id': item.id, 'name': item.name, 'details': item.details}).toList(),
        'tags': tags.map((item) => {'id': item.id, 'name': item.name}).toList(),
        'accounts': accounts.map((item) => {'id': item.id, 'name': item.name, 'type': item.type}).toList(),
      };
    }
    result['catatan'] = 'Berkas ini dibuat manual untuk analisa eksternal. Cek kembali privasi sebelum membagikannya.';
    return const JsonEncoder.withIndent('  ').convert(result);
  }
}
