import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:ffm_manager/core/database/app_context.dart';
import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/activity/domain/activity_query_layer.dart';
import 'package:ffm_manager/features/transaction/domain/usecases/transaction_crud_usecases.dart';

void main() {
  group('Performance: riwayat 1.000 & 10.000 records', () {
    test('query halaman pertama, filter, dan scroll tetap cepat untuk 10.000 transaksi', () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);

      final insertWatch = Stopwatch()..start();
      await database.transaction(() async {
        for (var i = 0; i < 10000; i++) {
          await database.into(database.transactions).insert(
                TransactionsCompanion.insert(
                  id: 'perf-tx-$i',
                  householdId: AppContext.householdId,
                  type: i % 3 == 0 ? 'expense' : 'income',
                  date: DateTime(2020, 1, 1).add(Duration(days: i % 3000)),
                  amount: i.isEven ? -(1000 * ((i % 50) + 1)) : (1000 * ((i % 50) + 1)),
                  owner: const Value('Keluarga'),
                  recordedAt: DateTime.now(),
                  createdAt: DateTime.now(),
                ),
              );
        }
      });
      insertWatch.stop();
      // Insert 10k diharapkan selesai di bawah 30 detik (in-memory tanpa index).
      expect(insertWatch.elapsed.inSeconds, lessThan(30),
          reason: 'insert 10.000 transaksi terlalu lambat: ${insertWatch.elapsed}');

      final getPage = GetTransactionsPage(database);
      final sw = Stopwatch()..start();
      final first = await getPage(AppContext.householdId, limit: 50);
      sw.stop();
      expect(first.items, hasLength(50));
      expect(first.hasMore, isTrue);
      expect(first.totalCount, 10000);
      expect(sw.elapsed.inMilliseconds, lessThan(2000),
          reason: 'halaman pertama terlalu lambat: ${sw.elapsed}');

      final swFilter = Stopwatch()..start();
      final filtered = await getPage(
        AppContext.householdId,
        limit: 50,
        startDate: DateTime(2021, 1, 1),
        endDate: DateTime(2021, 6, 1),
      );
      swFilter.stop();
      expect(filtered.totalCount, greaterThan(0));
      expect(swFilter.elapsed.inMilliseconds, lessThan(2000),
          reason: 'filter tanggal terlalu lambat: ${swFilter.elapsed}');

      // Scroll: muat semua halaman (10.000 / 50 = 200 batch).
      final swScroll = Stopwatch()..start();
      var count = 0;
      var offset = 0;
      var hasMore = true;
      while (hasMore) {
        final page = await getPage(AppContext.householdId, limit: 50, offset: offset);
        count += page.items.length;
        hasMore = page.hasMore;
        offset += 50;
      }
      swScroll.stop();
      expect(count, 10000);
      expect(swScroll.elapsed.inMilliseconds, lessThan(15000),
          reason: 'scroll semua halaman terlalu lambat: ${swScroll.elapsed}');
    });

    test('querySessionsPage & queryDailyNotesPage stabil untuk 1.000 aktivitas', () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);

      await database.transaction(() async {
        for (var i = 0; i < 1000; i++) {
          await database.into(database.activitySessions).insert(
                ActivitySessionsCompanion.insert(
                  id: 'perf-sess-$i',
                  householdId: AppContext.householdId,
                  title: 'Aktivitas ke-$i',
                  category: const Value('Lainnya'),
                  kind: const Value('timer'),
                  startedAt: DateTime(2022, 1, 1).add(Duration(days: i % 365)),
                  endedAt: const Value(null),
                  status: const Value('completed'),
                  isArchived: const Value(false),
                  isCompleted: const Value(true),
                  createdAt: DateTime.now(),
                ),
              );
        }
      });

      final queryLayer = ActivityQueryLayer(database);
      final sw = Stopwatch()..start();
      final page = await queryLayer.querySessionsPage(
        householdId: AppContext.householdId,
        limit: 50,
      );
      sw.stop();
      expect(page.items, hasLength(50));
      expect(page.hasMore, isTrue);
      expect(page.totalCount, 1000);
      expect(sw.elapsed.inMilliseconds, lessThan(2000),
          reason: 'querySessionsPage terlalu lambat: ${sw.elapsed}');

      final swKeyword = Stopwatch()..start();
      final filtered = await queryLayer.querySessionsPage(
        householdId: AppContext.householdId,
        keyword: 'aktivitas ke-999',
        limit: 50,
      );
      swKeyword.stop();
      expect(filtered.items, isNotEmpty);
      expect(filtered.items.first.id, 'perf-sess-999');
      expect(swKeyword.elapsed.inMilliseconds, lessThan(2000),
          reason: 'keyword filter terlalu lambat: ${swKeyword.elapsed}');
    });

    test('GetTransfersPage stabil dengan filter tanggal', () async {
      final database = createInMemoryDatabaseForTests();
      addTearDown(database.close);

      await database.transaction(() async {
        for (var i = 0; i < 2000; i++) {
          await database.into(database.transfers).insert(
                TransfersCompanion.insert(
                  id: 'perf-tr-$i',
                  householdId: AppContext.householdId,
                  fromAccountId: 'acc-a',
                  toAccountId: 'acc-b',
                  amount: 50000 + (i * 1000),
                  adminFee: const Value(0),
                  feeTransactionId: const Value(null),
                  date: DateTime(2023, 1, 1).add(Duration(days: i % 500)),
                  recordedAt: DateTime.now(),
                  source: const Value('manual'),
                  isDeleted: const Value(false),
                  updatedAt: const Value(null),
                ),
              );
        }
      });

      final getTransfersPage = GetTransfersPage(database);
      final sw = Stopwatch()..start();
      final page = await getTransfersPage(
        AppContext.householdId,
        limit: 50,
        startDate: DateTime(2023, 1, 1),
        endDate: DateTime(2023, 3, 1),
      );
      sw.stop();
      expect(page.items, isNotEmpty);
      expect(page.hasMore, isTrue);
      expect(sw.elapsed.inMilliseconds, lessThan(2000),
          reason: 'GetTransfersPage terlalu lambat: ${sw.elapsed}');
    });

    test('query halaman pertama & filter tetap cepat di 100.000 transaksi', () async {
      final database = createInMemoryDatabaseForTests();
      final databaseRef = database;
      addTearDown(database.close);

      // Insert massal via raw multi-row statement agar benchmark fokus pada
      // kecepatan query, bukan kecepatan Drift insert per baris.
      final insertWatch = Stopwatch()..start();
      const batchSize = 500;
      const total = 100000;
      // Drift 2.34.3 menyimpan DateTime sebagai Unix seconds.
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await database.transaction(() async {
        var i = 0;
        while (i < total) {
          final count = (i + batchSize) <= total ? batchSize : total - i;
          final placeholders = <String>[];
          final args = <Object>[];
          for (var k = 0; k < count; k++) {
            placeholders.add('(?, ?, ?, ?, ?, ?, ?, 0, 0)');
            final date =
                DateTime(2018, 1, 1).add(Duration(days: i % 2900));
            args
              ..add('bench-tx-$i')
              ..add(AppContext.householdId)
              ..add(i % 3 == 0 ? 'expense' : 'income')
              ..add(i.isEven ? -(1000 * ((i % 50) + 1)) : (1000 * ((i % 50) + 1)))
              ..add(date.millisecondsSinceEpoch ~/ 1000)
              ..add(nowSec)
              ..add(nowSec);
            i++;
          }
          await database.customStatement(
            'INSERT INTO transactions '
            '(id, household_id, type, amount, date, recorded_at, created_at, '
            'is_archived, is_deleted) '
            'VALUES ${placeholders.join(', ')}',
            args,
          );
        }
      });
      insertWatch.stop();
      expect(insertWatch.elapsed.inSeconds, lessThan(60),
          reason: 'insert 100.000 transaksi terlalu lambat: ${insertWatch.elapsed}');

      final getPage = GetTransactionsPage(databaseRef);
      final sw = Stopwatch()..start();
      final first = await getPage(AppContext.householdId, limit: 50);
      sw.stop();
      expect(first.items, hasLength(50));
      expect(first.hasMore, isTrue);
      expect(first.totalCount, total);
      expect(sw.elapsed.inMilliseconds, lessThan(2000),
          reason: 'halaman pertama 100k terlalu lambat: ${sw.elapsed}');

      final swFilter = Stopwatch()..start();
      final filtered = await getPage(
        AppContext.householdId,
        limit: 50,
        startDate: DateTime(2020, 1, 1),
        endDate: DateTime(2021, 6, 1),
      );
      swFilter.stop();
      expect(filtered.totalCount, greaterThan(0));
      expect(swFilter.elapsed.inMilliseconds, lessThan(2000),
          reason: 'filter tanggal 100k terlalu lambat: ${swFilter.elapsed}');

      // Scroll steady-state: memuat 60 halaman (3.000 baris) dengan offset,
      // membuktikan navigasi halaman tetap stabil di volume besar.
      final swScroll = Stopwatch()..start();
      var count = 0;
      var offset = 0;
      for (var pageIndex = 0; pageIndex < 60; pageIndex++) {
        final page = await getPage(
          AppContext.householdId,
          limit: 50,
          offset: offset,
        );
        count += page.items.length;
        offset += 50;
      }
      swScroll.stop();
      expect(count, 3000);
      expect(swScroll.elapsed.inMilliseconds, lessThan(15000),
          reason: 'scroll 60 halaman 100k terlalu lambat: ${swScroll.elapsed}');
    });
  });
}