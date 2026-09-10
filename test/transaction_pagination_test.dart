import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/transaction/domain/usecases/transaction_crud_usecases.dart';

void main() {
  late AppDatabase database;
  late GetTransactionsPage getPage;

  setUp(() async {
    database = createInMemoryDatabaseForTests();
    getPage = GetTransactionsPage(database);

    for (var i = 0; i < 150; i++) {
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: 'tx-$i',
              householdId: AppContext.householdId,
              type: i % 2 == 0 ? 'expense' : 'income',
              date: DateTime(2026, 1, 1).add(Duration(days: i)),
              amount: i % 2 == 0 ? -(1000 * (i + 1)) : (1000 * (i + 1)),
              owner: const Value('Keluarga'),
              recordedAt: DateTime.now(),
              createdAt: DateTime.now(),
            ),
          );
    }
  });

  tearDown(() async => database.close());

  test('page pertama mengembalikan batch pertama dengan hasMore true', () async {
    final result = await getPage(AppContext.householdId, limit: 50);

    expect(result.items, hasLength(50));
    expect(result.hasMore, isTrue);
    expect(result.totalCount, 150);
  });

  test('page terakhir mengembalikan sisa data dengan hasMore false', () async {
    final result = await getPage(
      AppContext.householdId,
      limit: 50,
      offset: 100,
    );

    expect(result.items, hasLength(50));
    expect(result.hasMore, isFalse);
  });

  test('page melebihi total mengembalikan kosong', () async {
    final result = await getPage(
      AppContext.householdId,
      limit: 50,
      offset: 200,
    );

    expect(result.items, isEmpty);
    expect(result.hasMore, isFalse);
  });

  test('filter date range membatasi jumlah data', () async {
    final result = await getPage(
      AppContext.householdId,
      limit: 200,
      startDate: DateTime(2026, 2, 1),
      endDate: DateTime(2026, 3, 1),
    );

    expect(result.totalCount, lessThan(150));
    for (final item in result.items) {
      expect(
        item.transaction.date.isAfter(DateTime(2026, 1, 31)) ||
            item.transaction.date.isAtSameMomentAs(DateTime(2026, 2, 1)),
        isTrue,
      );
    }
  });

  test('offset nol dengan limit besar mengambil semua data', () async {
    final result = await getPage(
      AppContext.householdId,
      limit: 200,
      offset: 0,
    );

    expect(result.items, hasLength(150));
    expect(result.hasMore, isFalse);
  });

  test('data diurutkan berdasarkan tanggal terbaru', () async {
    final result = await getPage(AppContext.householdId, limit: 10);

    for (var i = 0; i < result.items.length - 1; i++) {
      expect(
        result.items[i].transaction.date.isAfter(
              result.items[i + 1].transaction.date) ||
            result.items[i].transaction.date.isAtSameMomentAs(
              result.items[i + 1].transaction.date),
        isTrue,
      );
    }
  });
}
