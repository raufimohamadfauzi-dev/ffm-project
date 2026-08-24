import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_capability_adapters.dart';
import 'package:ffm_manager/features/assistant/data/ffm_assistant_reminder_mutation_service.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_action_plan.dart';
import 'package:ffm_manager/features/reminder/data/repositories/reminder_repository.dart';
import 'package:ffm_manager/features/reminder/data/services/reminder_notification_service.dart';
import 'package:ffm_manager/features/reminder/domain/entities/reminder_entity.dart';
import 'package:ffm_manager/features/reminder/domain/usecases/reminder_usecases.dart';

void main() {
  late AppDatabase database;
  late FfmAssistantCapabilityAdapterRegistry adapters;
  late _FakeReminderGateway reminderGateway;

  setUp(() {
    database = createInMemoryDatabaseForTests();
    reminderGateway = _FakeReminderGateway();
    adapters = FfmAssistantCapabilityAdapterRegistry(
      database: database,
      householdId: 'local-household',
      clock: () => DateTime(2026, 8, 23),
      reminderMutations: FfmAssistantReminderMutationService(
        repository: ReminderRepository(database),
        notificationGateway: reminderGateway,
        occurrenceCalculator: const ReminderOccurrenceCalculator(),
        clock: () => DateTime(2026, 8, 23),
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'read-only adapters mengembalikan hasil aman pada database kosong',
    () async {
      final planStep = const FfmAssistantActionStep(
        id: 'read',
        capabilityId: 'read.summary',
      );
      final summary = await adapters.handlers['read.summary']!(planStep);
      final accounts = await adapters.handlers['read.accounts']!(
        const FfmAssistantActionStep(
          id: 'accounts',
          capabilityId: 'read.accounts',
        ),
      );
      final categories = await adapters.handlers['read.categories']!(
        const FfmAssistantActionStep(
          id: 'categories',
          capabilityId: 'read.categories',
        ),
      );
      final transactions = await adapters.handlers['read.transactions']!(
        const FfmAssistantActionStep(
          id: 'transactions',
          capabilityId: 'read.transactions',
        ),
      );

      expect(summary.isSuccess, isTrue);
      expect(summary.message, contains('Ringkasan bulan ini'));
      expect(accounts.message, contains('Belum ada rekening'));
      expect(categories.message, contains('Kategori aktif'));
      expect(transactions.message, contains('Tidak ada transaksi'));
    },
  );

  test('hasil simpan aset dibaca kembali dari domain aset', () async {
    const saveStep = FfmAssistantActionStep(
      id: 'save-asset',
      capabilityId: 'mutate.save_draft',
      parameters: {
        'kind': 'asset',
        'title': 'Dana darurat',
        'amount': 500000,
        '_idempotencyKey': 'asset-regression',
      },
    );
    const verifyStep = FfmAssistantActionStep(
      id: 'verify-asset',
      capabilityId: 'verify.saved_draft',
      parameters: {'kind': 'asset', '_idempotencyKey': 'asset-regression'},
    );

    final saved = await adapters.handlers['mutate.save_draft']!(saveStep);
    final verified = await adapters.handlers['verify.saved_draft']!(verifyStep);

    expect(saved.isSuccess, isTrue);
    expect(verified.isSuccess, isTrue);
    expect(verified.message, contains('aset “Dana darurat”'));
  });

  test(
    'verifikasi pengingat gagal bila data belum benar-benar tersimpan',
    () async {
      const verifyStep = FfmAssistantActionStep(
        id: 'verify-reminder',
        capabilityId: 'verify.saved_draft',
        parameters: {
          'kind': 'reminder',
          '_idempotencyKey': 'reminder-belum-ada',
        },
      );

      final result = await adapters.handlers['verify.saved_draft']!(verifyStep);

      expect(result.isSuccess, isFalse);
      expect(result.message, contains('pengingat belum ditemukan'));
    },
  );

  test('izin notifikasi ditolak tidak menyimpan pengingat sebagian', () async {
    final deniedGateway = _FakeReminderGateway(
      permission: const ReminderPermissionState(
        notificationsEnabled: false,
        exactAlarmEnabled: false,
      ),
    );
    final protectedAdapters = FfmAssistantCapabilityAdapterRegistry(
      database: database,
      householdId: 'local-household',
      clock: () => DateTime(2026, 8, 23),
      reminderMutations: FfmAssistantReminderMutationService(
        repository: ReminderRepository(database),
        notificationGateway: deniedGateway,
        occurrenceCalculator: const ReminderOccurrenceCalculator(),
        clock: () => DateTime(2026, 8, 23),
      ),
    );
    final result = await protectedAdapters.handlers['mutate.save_draft']!(
      FfmAssistantActionStep(
        id: 'save-reminder-denied',
        capabilityId: 'mutate.save_draft',
        parameters: {
          'kind': 'reminder',
          'title': 'Bayar listrik',
          'date': DateTime(2026, 8, 30),
          '_idempotencyKey': 'reminder-denied',
        },
      ),
    );

    expect(result.isSuccess, isFalse);
    expect(await database.select(database.reminders).get(), isEmpty);
    expect(deniedGateway.scheduledNotificationIds, isEmpty);
  });

  test(
    'idempotency aset menolak draft berbeda dengan kunci yang sama',
    () async {
      const firstSave = FfmAssistantActionStep(
        id: 'save-asset-first',
        capabilityId: 'mutate.save_draft',
        parameters: {
          'kind': 'asset',
          'title': 'Dana darurat',
          'amount': 500000,
          '_idempotencyKey': 'asset-idempotency',
        },
      );
      const conflictingSave = FfmAssistantActionStep(
        id: 'save-asset-conflict',
        capabilityId: 'mutate.save_draft',
        parameters: {
          'kind': 'asset',
          'title': 'Dana darurat',
          'amount': 700000,
          '_idempotencyKey': 'asset-idempotency',
        },
      );

      final first = await adapters.handlers['mutate.save_draft']!(firstSave);
      final conflicting = await adapters.handlers['mutate.save_draft']!(
        conflictingSave,
      );

      expect(first.isSuccess, isTrue);
      expect(conflicting.isSuccess, isFalse);
      expect(conflicting.message, contains('Idempotency key'));
    },
  );

  test(
    'verifikasi simpan mencakup seluruh domain non-transaksi yang didukung',
    () async {
      final cases = <({String kind, Map<String, Object?> parameters})>[
        (
          kind: 'profile',
          parameters: const {'note': 'Nama: Rafi\nTujuan: Dana darurat'},
        ),
        (kind: 'activity', parameters: const {'title': 'Belajar Flutter'}),
        (
          kind: 'reminder',
          parameters: {'title': 'Bayar listrik', 'date': DateTime(2026, 8, 30)},
        ),
        (
          kind: 'master_data',
          parameters: const {
            'title': 'Tabungan keluarga',
            'category': 'rekening',
          },
        ),
        (
          kind: 'goal',
          parameters: const {'title': 'Dana pendidikan', 'amount': 1000000},
        ),
        (
          kind: 'asset',
          parameters: const {'title': 'Emas keluarga', 'amount': 1500000},
        ),
        (
          kind: 'liability',
          parameters: const {
            'title': 'Pinjaman',
            'party': 'Pihak A',
            'amount': 300000,
          },
        ),
        (
          kind: 'receivable',
          parameters: const {
            'title': 'Tagihan',
            'party': 'Pihak B',
            'amount': 250000,
          },
        ),
        (kind: 'budget', parameters: const {'amount': 400000}),
      ];

      for (final item in cases) {
        final key = 'verify-${item.kind}';
        final saved = await adapters.handlers['mutate.save_draft']!(
          FfmAssistantActionStep(
            id: 'save-${item.kind}',
            capabilityId: 'mutate.save_draft',
            parameters: {
              'kind': item.kind,
              ...item.parameters,
              '_idempotencyKey': key,
            },
          ),
        );
        final verified = await adapters.handlers['verify.saved_draft']!(
          FfmAssistantActionStep(
            id: 'verify-${item.kind}',
            capabilityId: 'verify.saved_draft',
            parameters: {
              'kind': item.kind,
              ...item.parameters,
              '_idempotencyKey': key,
            },
          ),
        );

        expect(
          saved.isSuccess,
          isTrue,
          reason: '${item.kind}: ${saved.message}',
        );
        expect(
          verified.isSuccess,
          isTrue,
          reason: '${item.kind}: ${verified.message}',
        );
        expect(
          verified.message,
          contains('verified:'),
          reason: '${item.kind}: ${verified.message}',
        );
      }
      expect(reminderGateway.scheduledNotificationIds, isNotEmpty);
    },
  );
}

class _FakeReminderGateway implements ReminderNotificationGateway {
  _FakeReminderGateway({
    this.permission = const ReminderPermissionState(
      notificationsEnabled: true,
      exactAlarmEnabled: true,
    ),
  });

  final ReminderPermissionState permission;
  final scheduledNotificationIds = <int>[];
  final cancelledNotificationIds = <int>[];

  @override
  Future<void> Function(String action, Map<String, dynamic> payload)? onAction;

  @override
  Future<void> cancel(int notificationId) async {
    cancelledNotificationIds.add(notificationId);
  }

  @override
  Future<void> cancelAll() async {}

  @override
  Future<List<ReminderNotificationAction>> consumePendingActions() async =>
      const [];

  @override
  Future<ReminderPermissionState> permissionState() async => permission;

  @override
  Future<ReminderPermissionState> requestPermissions() async => permission;

  @override
  Future<void> schedule({
    required ReminderEntity reminder,
    required ReminderOccurrence occurrence,
    String? historyId,
  }) async {
    scheduledNotificationIds.add(occurrence.notificationId);
  }
}
