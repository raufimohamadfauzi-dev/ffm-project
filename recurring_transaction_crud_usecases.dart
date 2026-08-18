import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';

class GetRecurringTransactions {
  const GetRecurringTransactions(this.database);
  final AppDatabase database;

  Future<List<RecurringTransaction>> call(String householdId) async {
    return (database.select(database.recurringTransactions)
          ..where((row) => row.householdId.equals(householdId) & row.isActive.equals(true))
          ..orderBy([(row) => OrderingTerm.asc(row.startDate)]))
        .get();
  }
}
