import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../transaction/domain/usecases/transaction_crud_usecases.dart';
import '../domain/ffm_assistant_action_plan.dart';
import '../domain/ffm_assistant_capability_executor.dart';

class FfmAssistantCapabilityAdapterRegistry {
  FfmAssistantCapabilityAdapterRegistry({
    required AppDatabase database,
    required String householdId,
    DateTime Function()? clock,
  }) : _database = database,
       _householdId = householdId,
       _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final String _householdId;
  final DateTime Function() _clock;

  Map<String, FfmAssistantCapabilityHandler> get handlers => {
    'read.summary': _readSummary,
    'read.transactions': _readTransactions,
    'read.accounts': _readAccounts,
    'read.categories': _readCategories,
    'read.analysis': _readAnalysis,
    'draft.income': _prepareDraft,
    'draft.expense': _prepareDraft,
    'draft.transfer': _prepareDraft,
    'draft.profile': _prepareDraft,
    'draft.activity': _prepareDraft,
    'draft.reminder': _prepareDraft,
    'draft.master_data': _prepareDraft,
    'draft.goal': _prepareDraft,
    'draft.asset': _prepareDraft,
    'draft.liability': _prepareDraft,
    'draft.receivable': _prepareDraft,
    'draft.budget': _prepareDraft,
    'draft.goal_deposit': _prepareDraft,
    'draft.goal_usage': _prepareDraft,
    'mutate.save_draft': _saveDraft,
    'verify.saved_draft': _verifySavedDraft,
  };

  Future<FfmAssistantCapabilityExecutionResult> _readSummary(
    FfmAssistantActionStep step,
  ) async {
    final now = _clock();
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);
    final rows =
        await (_database.select(_database.transactions)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isArchived.equals(false) &
                  row.isDeleted.equals(false),
            ))
            .get();
    var income = 0;
    var expense = 0;
    var count = 0;
    for (final row in rows) {
      if (row.date.isBefore(start) || !row.date.isBefore(end)) continue;
      if (row.type == 'income') {
        income += row.amount.abs();
        count++;
      } else if (row.type == 'expense') {
        expense += row.amount.abs();
        count++;
      }
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Ringkasan bulan ini: $count transaksi, pemasukan ${_money(income)}, pengeluaran ${_money(expense)}. Transfer tidak dihitung sebagai pemasukan/pengeluaran.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _readTransactions(
    FfmAssistantActionStep step,
  ) async {
    final rows =
        await (_database.select(_database.transactions)
              ..where(
                (row) =>
                    row.householdId.equals(_householdId) &
                    row.isArchived.equals(false) &
                    row.isDeleted.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.date)]))
            .get();
    final filtered = rows
        .where(_matchesTransaction(step.parameters))
        .take(20)
        .toList();
    if (filtered.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Tidak ada transaksi yang cocok pada data lokal.',
      );
    }
    final lines = filtered.map((row) {
      final kind = row.type == 'income' ? 'Pemasukan' : 'Pengeluaran';
      return '$kind ${_money(row.amount.abs())} pada ${row.date.toIso8601String().substring(0, 10)}';
    });
    return FfmAssistantCapabilityExecutionResult.success(
      'Ditemukan ${filtered.length} transaksi (maksimal 20 ditampilkan): ${lines.join('; ')}',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _readAccounts(
    FfmAssistantActionStep step,
  ) async {
    final rows =
        await (_database.select(_database.accounts)
              ..where(
                (row) =>
                    row.householdId.equals(_householdId) &
                    row.isActive.equals(true) &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.name)]))
            .get();
    if (rows.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Belum ada rekening aktif.',
      );
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Rekening aktif (${rows.length}): ${rows.map((row) => row.name).join(', ')}.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _readCategories(
    FfmAssistantActionStep step,
  ) async {
    final rows =
        await (_database.select(_database.categories)
              ..where(
                (row) =>
                    row.householdId.equals(_householdId) &
                    row.isActive.equals(true),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.name)]))
            .get();
    if (rows.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Belum ada kategori aktif.',
      );
    }
    final grouped = <String, List<String>>{};
    for (final row in rows) {
      (grouped[row.type] ??= <String>[]).add(row.name);
    }
    final parts = grouped.entries
        .map((entry) => '${entry.key}: ${entry.value.join(', ')}')
        .join('; ');
    return FfmAssistantCapabilityExecutionResult.success(
      'Kategori aktif (${rows.length}): $parts.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _prepareDraft(
    FfmAssistantActionStep step,
  ) async {
    final kind = step.parameters['kind']?.toString();
    if (kind == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Draft mutation belum memiliki jenis.',
      );
    }
    final needsAmount = switch (kind) {
      'profile' || 'activity' || 'reminder' || 'master_data' => false,
      _ => true,
    };

    if (!needsAmount) {
      return FfmAssistantCapabilityExecutionResult.success(
        'Preview siap untuk $kind. Belum ada data yang disimpan.',
      );
    }

    final amount = _positiveInt(step.parameters['amount']);
    if (amount == null || amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Draft mutation belum memiliki nominal yang valid.',
      );
    }
    return FfmAssistantCapabilityExecutionResult.success(
      'Preview siap untuk $kind sebesar ${_money(amount)}. Belum ada data yang disimpan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveDraft(
    FfmAssistantActionStep step,
  ) async {
    final kind = step.parameters['kind']?.toString();
    final idempotencyKey = step.parameters['_idempotencyKey']?.toString();
    if (kind == null || idempotencyKey == null || idempotencyKey.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Payload mutation tidak memiliki kind atau idempotency key.',
      );
    }
    if (kind == 'transfer') return _saveTransfer(step, idempotencyKey);
    if (kind == 'profile') return _saveProfile(step, idempotencyKey);
    if (kind == 'activity') return _saveActivity(step, idempotencyKey);
    if (kind == 'reminder') return _saveReminder(step, idempotencyKey);
    if (kind == 'master_data') return _saveMasterData(step, idempotencyKey);
    if (kind == 'goal') return _saveGoal(step, idempotencyKey);
    if (kind == 'asset') return _saveAsset(step, idempotencyKey);
    if (kind == 'liability') return _saveLiability(step, idempotencyKey);
    if (kind == 'receivable') return _saveReceivable(step, idempotencyKey);
    if (kind == 'budget') return _saveBudget(step, idempotencyKey);
    if (kind == 'goal_deposit')
      return _saveGoalTransaction(step, idempotencyKey, isDeposit: true);
    if (kind == 'goal_usage')
      return _saveGoalTransaction(step, idempotencyKey, isDeposit: false);
    if (kind != 'income' && kind != 'expense') {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Mutation draft $kind belum memiliki adapter aman.',
      );
    }
    final amount = _positiveInt(step.parameters['amount']);
    if (amount == null || amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nominal harus lebih besar dari nol.',
      );
    }
    final accountName =
        (kind == 'income'
                ? step.parameters['toAccount']
                : step.parameters['fromAccount'])
            ?.toString()
            .trim();
    final account = await _findAccount(accountName);
    if (account == null) {
      return FfmAssistantCapabilityExecutionResult.failure(
        accountName == null || accountName.isEmpty
            ? 'Rekening untuk draft belum disebutkan.'
            : 'Rekening "$accountName" tidak ditemukan atau tidak unik.',
      );
    }
    final categoryName = step.parameters['category']?.toString().trim();
    final category = await _findCategory(categoryName, kind);
    if (categoryName != null && categoryName.isNotEmpty && category == null) {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Kategori "$categoryName" tidak ditemukan atau tidak unik.',
      );
    }
    final id = _stableId(idempotencyKey);
    final previous = await GetTransaction(_database)(_householdId, id);
    if (previous != null) {
      final expectedAmount = kind == 'income' ? amount : -amount;
      if (previous.transaction.amount == expectedAmount &&
          previous.transaction.accountId == account.id) {
        return FfmAssistantCapabilityExecutionResult.success(
          'alreadyApplied: transaksi ${kind == 'income' ? 'pemasukan' : 'pengeluaran'} sudah tersimpan.',
        );
      }
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Idempotency key sudah dipakai oleh transaksi dengan isi berbeda.',
      );
    }
    final date = _dateParameter(step.parameters['date']) ?? _clock();
    final note = step.parameters['note']?.toString().trim();
    final party = step.parameters['party']?.toString().trim();
    final entity = TransactionEntity(
      id: id,
      householdId: _householdId,
      date: date,
      amount: kind == 'income' ? amount : -amount,
      owner: 'Keluarga',
      categoryId: category?.id,
      note: note == null || note.isEmpty ? null : note,
      source: 'assistant_orchestrator',
      accountId: account.id,
      partyName: party == null || party.isEmpty ? null : party,
      recordedAt: _clock(),
      updatedAt: _clock(),
    );
    await SaveTransaction(_database)(entity);
    return FfmAssistantCapabilityExecutionResult.success(
      'Tersimpan satu kali: ${kind == 'income' ? 'pemasukan' : 'pengeluaran'} ${_money(amount)} pada ${date.toIso8601String().substring(0, 10)}.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveTransfer(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final amount = _positiveInt(step.parameters['amount']);
    final fromName = step.parameters['fromAccount']?.toString().trim();
    final toName = step.parameters['toAccount']?.toString().trim();
    if (amount == null || amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nominal transfer harus lebih besar dari nol.',
      );
    }
    final from = await _findAccount(fromName);
    final to = await _findAccount(toName);
    if (from == null || to == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Rekening asal dan tujuan harus ditemukan secara unik.',
      );
    }
    if (from.id == to.id) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Rekening asal dan tujuan tidak boleh sama.',
      );
    }
    final transferId = _stableId(idempotencyKey);
    final existing =
        await (_database.select(_database.transfers)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.id.equals(transferId),
            ))
            .getSingleOrNull();
    if (existing != null) {
      if (existing.amount == amount &&
          existing.fromAccountId == from.id &&
          existing.toAccountId == to.id) {
        return const FfmAssistantCapabilityExecutionResult.success(
          'alreadyApplied: transfer sudah tersimpan.',
        );
      }
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Idempotency key sudah dipakai oleh transfer dengan isi berbeda.',
      );
    }
    final fee = _positiveInt(step.parameters['adminFee']) ?? 0;
    final now = _clock();
    final feeId = fee > 0 ? '$transferId-fee' : null;
    final feeCategory = fee > 0
        ? await _findCategory('Biaya admin', 'expense')
        : null;
    if (fee > 0 && feeCategory == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Kategori Biaya admin belum tersedia.',
      );
    }
    final transfer = TransferEntity(
      id: transferId,
      householdId: _householdId,
      date: _dateParameter(step.parameters['date']) ?? now,
      recordedAt: now,
      amount: amount,
      adminFee: fee,
      feeTransactionId: feeId,
      fromAccountId: from.id,
      toAccountId: to.id,
      note: step.parameters['note']?.toString().trim(),
      source: 'assistant_orchestrator',
      updatedAt: now,
    );
    final entities = <TransactionEntity>[];
    if (fee > 0) {
      entities.add(
        TransactionEntity(
          id: feeId!,
          householdId: _householdId,
          date: transfer.date,
          amount: -fee,
          owner: 'Keluarga',
          categoryId: feeCategory!.id,
          note: 'Biaya admin transfer ${from.name} ke ${to.name}',
          source: 'transfer_fee',
          accountId: from.id,
          recordedAt: now,
          updatedAt: now,
        ),
      );
    }
    await SaveMixedTransactionBatch(_database)(
      entities,
      itemsByTransactionId: const {},
      transfers: [transfer],
    );
    return FfmAssistantCapabilityExecutionResult.success(
      'Tersimpan satu kali: transfer ${_money(amount)} dari ${from.name} ke ${to.name}.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _verifySavedDraft(
    FfmAssistantActionStep step,
  ) async {
    final kind = step.parameters['kind']?.toString();
    final key = step.parameters['_idempotencyKey']?.toString();
    if (kind == null || key == null || key.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Payload verifikasi tidak lengkap.',
      );
    }
    final id = _stableId(key);
    if (kind == 'transfer') {
      final transfer =
          await (_database.select(_database.transfers)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
      return transfer == null
          ? const FfmAssistantCapabilityExecutionResult.failure(
              'Transfer belum ditemukan saat verifikasi.',
            )
          : FfmAssistantCapabilityExecutionResult.success(
              'verified: transfer ${transfer.amount} berhasil dibaca kembali dari database lokal.',
            );
    }
    final transaction = await GetTransaction(_database)(_householdId, id);
    return transaction == null
        ? const FfmAssistantCapabilityExecutionResult.failure(
            'Transaksi belum ditemukan saat verifikasi.',
          )
        : FfmAssistantCapabilityExecutionResult.success(
            'verified: transaksi ${transaction.transaction.amount} berhasil dibaca kembali dari database lokal.',
          );
  }

  Future<dynamic> _findAccount(String? name) async {
    if (name == null || name.isEmpty) return null;
    final rows =
        await (_database.select(_database.accounts)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isActive.equals(true) &
                  row.isArchived.equals(false) &
                  row.name.equals(name),
            ))
            .get();
    return rows.length == 1 ? rows.single : null;
  }

  Future<dynamic> _findCategory(String? name, String type) async {
    if (name == null || name.isEmpty) return null;
    final rows =
        await (_database.select(_database.categories)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.isActive.equals(true) &
                  row.name.equals(name) &
                  row.type.equals(type),
            ))
            .get();
    return rows.length == 1 ? rows.single : null;
  }

  int? _positiveInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) {
      return int.tryParse(value.replaceAll(RegExp(r'[^0-9-]'), ''));
    }
    return null;
  }

  String _stableId(String key) {
    var hash = 2166136261;
    for (final codeUnit in key.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return 'assistant-${hash.toRadixString(16)}';
  }

  Future<FfmAssistantCapabilityExecutionResult> _readAnalysis(
    FfmAssistantActionStep step,
  ) async {
    final summary = await _readSummary(step);
    return FfmAssistantCapabilityExecutionResult.success(
      'Analisa lokal berdasarkan data yang tersedia. ${summary.message} Gunakan halaman Analisa untuk grafik dan rincian lengkap.',
    );
  }

  bool Function(dynamic) _matchesTransaction(Map<String, Object?> parameters) {
    final from = _dateParameter(parameters['dateFrom']);
    final to = _dateParameter(parameters['dateTo']);
    final query = parameters['query']?.toString().trim().toLowerCase();
    return (row) {
      if (from != null && row.date.isBefore(from)) return false;
      if (to != null && !row.date.isBefore(to)) return false;
      if (query == null || query.isEmpty) return true;
      final haystack = '${row.note ?? ''} ${row.partyName ?? ''}'.toLowerCase();
      return haystack.contains(query);
    };
  }

  DateTime? _dateParameter(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveProfile(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final note = step.parameters['note']?.toString() ?? '';
    final formValues = <String, String>{};
    final parts = note.split('\n');
    for (final part in parts) {
      final colon = part.indexOf(':');
      if (colon > 0) {
        final key = part.substring(0, colon).trim();
        final val = part.substring(colon + 1).trim();
        if (key.isNotEmpty && val.isNotEmpty) {
          formValues[key] = val;
        }
      }
    }

    final name = formValues['Nama'] ?? formValues['Panggilan'];
    final occupation = formValues['Pekerjaan'] ?? formValues['Peran'];
    final routine = formValues['Rutinitas'] ?? formValues['Kegiatan'];
    final goals = formValues['Tujuan'] ?? formValues['Prioritas'];

    if (name == null &&
        occupation == null &&
        routine == null &&
        goals == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Format profil tidak valid atau kosong. Harus berisi key: value seperti "Nama: Rudi".',
      );
    }

    await _database.transaction(() async {
      Future<void> save(String key, String? val) async {
        if (val != null && val.isNotEmpty) {
          await _database
              .into(_database.userPreferences)
              .insertOnConflictUpdate(
                UserPreferencesCompanion.insert(
                  id: 'pref-$key',
                  householdId: _householdId,
                  preferenceKey: key,
                  preferenceValue: val,
                  updatedAt: _clock(),
                ),
              );
        }
      }

      await save('profile_name', name);
      await save('profile_occupation', occupation);
      await save('profile_routine', routine);
      await save('profile_goals', goals);
    });

    return const FfmAssistantCapabilityExecutionResult.success(
      'Profil personalisasi berhasil disimpan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveActivity(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final title = step.parameters['title']?.toString();
    if (title == null || title.trim().isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nama aktivitas belum diisi.',
      );
    }
    final now = _clock();
    final id = _stableId(idempotencyKey);
    final previous =
        await (_database.select(_database.activitySessions)..where(
              (row) => row.householdId.equals(_householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    if (previous != null) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Aktivitas sudah tersimpan sebelumnya.',
      );
    }
    await _database
        .into(_database.activitySessions)
        .insert(
          ActivitySessionsCompanion.insert(
            id: id,
            householdId: _householdId,
            title: title.trim(),
            status: const Value('active'),
            startedAt: now,
            createdAt: now,
            updatedAt: Value(now),
          ),
        );
    return const FfmAssistantCapabilityExecutionResult.success(
      'Aktivitas berhasil dimulai.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveReminder(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final title = step.parameters['title']?.toString();
    final dateStr = step.parameters['date']?.toString();
    if (title == null || title.trim().isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Judul pengingat belum diisi.',
      );
    }
    final date = _dateParameter(dateStr);
    if (date == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Waktu pengingat tidak valid.',
      );
    }
    final now = _clock();
    final id = _stableId(idempotencyKey);
    final previous =
        await (_database.select(_database.reminders)..where(
              (row) => row.householdId.equals(_householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    if (previous != null) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Pengingat sudah tersimpan sebelumnya.',
      );
    }
    await _database
        .into(_database.reminders)
        .insert(
          RemindersCompanion.insert(
            id: id,
            householdId: _householdId,
            title: title.trim(),
            note: Value(step.parameters['note']?.toString()),
            scheduledAt: date,
            notificationId: id.hashCode.abs(),
            isActive: const Value(true),
            createdAt: now,
          ),
        );
    return const FfmAssistantCapabilityExecutionResult.success(
      'Pengingat berhasil disimpan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveMasterData(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final title = step.parameters['title']?.toString();
    final category = step.parameters['category']?.toString();
    if (title == null || title.trim().isEmpty || category == null) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nama atau jenis data utama belum diisi.',
      );
    }
    final now = _clock();
    final id = _stableId(idempotencyKey);

    if (category == 'rekening') {
      final previous =
          await (_database.select(_database.accounts)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
      if (previous != null) {
        return const FfmAssistantCapabilityExecutionResult.success(
          'Rekening sudah tersimpan.',
        );
      }
      await _database
          .into(_database.accounts)
          .insert(
            AccountsCompanion.insert(
              id: id,
              householdId: _householdId,
              name: title.trim(),
              type: 'tunai',
              createdAt: now,
            ),
          );
    } else if (category == 'toko') {
      final previous =
          await (_database.select(_database.merchants)..where(
                (row) =>
                    row.householdId.equals(_householdId) & row.id.equals(id),
              ))
              .getSingleOrNull();
      if (previous != null) {
        return const FfmAssistantCapabilityExecutionResult.success(
          'Toko sudah tersimpan.',
        );
      }
      await _database
          .into(_database.merchants)
          .insert(
            MerchantsCompanion.insert(
              id: id,
              householdId: _householdId,
              name: title.trim(),
              createdAt: now,
            ),
          );
    } else {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Pembuatan data utama jenis $category belum didukung.',
      );
    }

    return const FfmAssistantCapabilityExecutionResult.success(
      'Data utama berhasil disimpan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveGoal(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final title = step.parameters['title']?.toString();
    final amount = _positiveInt(step.parameters['amount']);
    final dateStr = step.parameters['date']?.toString();
    if (title == null ||
        title.trim().isEmpty ||
        amount == null ||
        amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nama atau nominal target belum diisi dengan benar.',
      );
    }
    final date =
        _dateParameter(dateStr) ?? _clock().add(const Duration(days: 30));
    final now = _clock();
    final id = _stableId(idempotencyKey);
    final previous =
        await (_database.select(_database.goals)..where(
              (row) => row.householdId.equals(_householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    if (previous != null) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Target sudah tersimpan.',
      );
    }
    await _database
        .into(_database.goals)
        .insert(
          GoalsCompanion.insert(
            id: id,
            householdId: _householdId,
            name: title.trim(),
            targetAmount: amount,
            targetDate: Value(date),
            createdAt: now,
          ),
        );
    return const FfmAssistantCapabilityExecutionResult.success(
      'Target berhasil disimpan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveAsset(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final title = step.parameters['title']?.toString();
    final amount = _positiveInt(step.parameters['amount']);
    if (title == null ||
        title.trim().isEmpty ||
        amount == null ||
        amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nama atau nilai aset belum diisi dengan benar.',
      );
    }
    final now = _clock();
    final id = _stableId(idempotencyKey);
    final previous =
        await (_database.select(_database.assets)..where(
              (row) => row.householdId.equals(_householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    if (previous != null) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Aset sudah tersimpan.',
      );
    }
    await _database
        .into(_database.assets)
        .insert(
          AssetsCompanion.insert(
            id: id,
            householdId: _householdId,
            name: title.trim(),
            assetType: 'Aset Lancar',
            value: Value(amount),
            createdAt: now,
            updatedAt: Value(now),
          ),
        );
    return const FfmAssistantCapabilityExecutionResult.success(
      'Aset berhasil disimpan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveLiability(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final title = step.parameters['title']?.toString() ?? 'Hutang';
    final party = step.parameters['party']?.toString();
    final amount = _positiveInt(step.parameters['amount']);
    if (party == null ||
        party.trim().isEmpty ||
        amount == null ||
        amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nama pihak atau nominal hutang belum diisi dengan benar.',
      );
    }
    final now = _clock();
    final id = _stableId(idempotencyKey);
    final previous =
        await (_database.select(_database.liabilities)..where(
              (row) => row.householdId.equals(_householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    if (previous != null) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Hutang sudah tersimpan.',
      );
    }
    await _database
        .into(_database.liabilities)
        .insert(
          LiabilitiesCompanion.insert(
            id: id,
            householdId: _householdId,
            name: '${title.trim()} - ${party.trim()}',
            originalAmount: amount,
            remainingBalance: amount,
            startDate: now,
            createdAt: now,
          ),
        );
    return const FfmAssistantCapabilityExecutionResult.success(
      'Hutang berhasil disimpan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveReceivable(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final title = step.parameters['title']?.toString() ?? 'Piutang';
    final party = step.parameters['party']?.toString();
    final amount = _positiveInt(step.parameters['amount']);
    if (party == null ||
        party.trim().isEmpty ||
        amount == null ||
        amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nama pihak atau nominal piutang belum diisi dengan benar.',
      );
    }
    final now = _clock();
    final id = _stableId(idempotencyKey);
    final previous =
        await (_database.select(_database.receivables)..where(
              (row) => row.householdId.equals(_householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    if (previous != null) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Piutang sudah tersimpan.',
      );
    }
    await _database
        .into(_database.receivables)
        .insert(
          ReceivablesCompanion.insert(
            id: id,
            householdId: _householdId,
            name: '${title.trim()} - ${party.trim()}',
            originalAmount: amount,
            remainingBalance: amount,
            startDate: now,
            createdAt: now,
          ),
        );
    return const FfmAssistantCapabilityExecutionResult.success(
      'Piutang berhasil disimpan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveBudget(
    FfmAssistantActionStep step,
    String idempotencyKey,
  ) async {
    final amount = _positiveInt(step.parameters['amount']);
    if (amount == null || amount <= 0) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nominal anggaran belum diisi dengan benar.',
      );
    }
    final now = _clock();
    final id = _stableId(idempotencyKey);
    final previous =
        await (_database.select(_database.envelopeBudgets)..where(
              (row) => row.householdId.equals(_householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    if (previous != null) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Anggaran sudah tersimpan.',
      );
    }
    await _database
        .into(_database.envelopeBudgets)
        .insert(
          EnvelopeBudgetsCompanion.insert(
            id: id,
            householdId: _householdId,
            name: 'Anggaran Asisten',
            periodType: const Value('monthly'),
            allocated: Value(amount),
            startDate: DateTime(now.year, now.month, 1),
            endDate: DateTime(now.year, now.month + 1, 0),
            createdAt: now,
            updatedAt: Value(now),
          ),
        );
    return const FfmAssistantCapabilityExecutionResult.success(
      'Anggaran berhasil disimpan.',
    );
  }

  Future<FfmAssistantCapabilityExecutionResult> _saveGoalTransaction(
    FfmAssistantActionStep step,
    String idempotencyKey, {
    required bool isDeposit,
  }) async {
    final amount = _positiveInt(step.parameters['amount']);
    final goalName = step.parameters['goal']?.toString();
    if (amount == null || amount <= 0 || goalName == null || goalName.isEmpty) {
      return const FfmAssistantCapabilityExecutionResult.failure(
        'Nominal atau nama target belum diisi.',
      );
    }
    final goal =
        await (_database.select(_database.goals)..where(
              (row) =>
                  row.householdId.equals(_householdId) &
                  row.name.equals(goalName),
            ))
            .getSingleOrNull();
    if (goal == null) {
      return FfmAssistantCapabilityExecutionResult.failure(
        'Target keuangan "$goalName" tidak ditemukan.',
      );
    }
    final now = _clock();
    final id = _stableId(idempotencyKey);
    final previous =
        await (_database.select(_database.transactions)..where(
              (row) => row.householdId.equals(_householdId) & row.id.equals(id),
            ))
            .getSingleOrNull();
    if (previous != null) {
      return const FfmAssistantCapabilityExecutionResult.success(
        'Transaksi target sudah tersimpan.',
      );
    }

    await _database.transaction(() async {
      await _database
          .into(_database.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: id,
              householdId: _householdId,
              type: isDeposit ? 'expense' : 'income',
              date: now,
              recordedAt: now,
              amount: amount,
              owner: const Value('Keluarga'),
              note: Value(step.parameters['note']?.toString()),
              source: const Value('manual'),
              goalId: Value(goal.id),
              createdAt: now,
              updatedAt: Value(now),
              isDeleted: const Value(false),
            ),
          );

      final newAmount = isDeposit
          ? goal.currentAmount + amount
          : goal.currentAmount - amount;

      await (_database.update(_database.goals)
            ..where((row) => row.id.equals(goal.id)))
          .write(GoalsCompanion(currentAmount: Value(newAmount)));
    });

    return const FfmAssistantCapabilityExecutionResult.success(
      'Transaksi target berhasil disimpan.',
    );
  }

  String _money(int value) {
    final digits = value.toString();
    final buffer = StringBuffer('Rp');
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }
}
