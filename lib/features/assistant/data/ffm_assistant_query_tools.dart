import '../../../core/database/app_database.dart';

import 'package:drift/drift.dart';

/// Kontrak baca data Asisten. Tidak ada tool di berkas ini yang memiliki
/// akses insert, update, delete, atau side effect lain pada database FFM.
class FfmAssistantQueryRequest {
  const FfmAssistantQueryRequest({
    required this.householdId,
    required this.normalizedText,
    required this.parameters,
    required this.now,
  });

  final String householdId;
  final String normalizedText;
  final Map<String, Object?> parameters;
  final DateTime now;
}

class FfmAssistantQueryAnswer {
  const FfmAssistantQueryAnswer({required this.title, required this.message});

  final String title;
  final String message;
}

abstract interface class FfmAssistantQueryTool {
  bool canHandle(String normalizedText);

  Future<FfmAssistantQueryAnswer?> answer(FfmAssistantQueryRequest request);
}

/// Registry tool baca lokal. Query lebih spesifik dikembalikan lebih awal agar
/// tidak jatuh ke fallback penjelasan fitur atau parser draft transaksi.
class FfmAssistantQueryRegistry {
  FfmAssistantQueryRegistry(AppDatabase database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      _tools = <FfmAssistantQueryTool>[
        _AccountBalanceQueryTool(database),
        _TransactionSummaryQueryTool(database),
        _ActiveActivityQueryTool(database),
        _GoalStatusQueryTool(database),
        _DebtStatusQueryTool(database),
        _AssetSummaryQueryTool(database),
      ];

  final DateTime Function() _clock;
  final List<FfmAssistantQueryTool> _tools;

  Future<FfmAssistantQueryAnswer?> tryAnswer(
    String normalizedText, {
    required String householdId,
  }) async {
    // Kalimat aksi harus selalu diteruskan ke parser draft. Tanpa pagar ini,
    // kata seperti "senilai" pada "tambah aset ... senilai ..." dapat keliru
    // terbaca sebagai pertanyaan nilai aset.
    if (RegExp(
      r'\b(tambah|buat|catat|mulai|selesai|ubah|hapus)\b',
      caseSensitive: false,
    ).hasMatch(normalizedText)) {
      return null;
    }
    final request = FfmAssistantQueryRequest(
      householdId: householdId,
      normalizedText: normalizedText,
      parameters: const <String, Object?>{},
      now: _clock(),
    );
    for (final tool in _tools) {
      if (!tool.canHandle(normalizedText)) continue;
      final answer = await tool.answer(request);
      if (answer != null) return answer;
    }
    return null;
  }
}

class _AccountBalanceQueryTool implements FfmAssistantQueryTool {
  const _AccountBalanceQueryTool(this._database);

  final AppDatabase _database;

  @override
  bool canHandle(String normalizedText) =>
      normalizedText.contains('saldo') &&
      !normalizedText.contains('saldo target') &&
      !normalizedText.contains('saldo tujuan');

  @override
  Future<FfmAssistantQueryAnswer?> answer(
    FfmAssistantQueryRequest request,
  ) async {
    final accounts =
        await (_database.select(_database.accounts)..where(
              (row) =>
                  row.householdId.equals(request.householdId) &
                  row.isActive.equals(true) &
                  row.isArchived.equals(false),
            ))
            .get();
    if (accounts.isEmpty) {
      return const FfmAssistantQueryAnswer(
        title: 'Saldo rekening',
        message: 'Belum ada rekening aktif. Tambah rekening dulu di Data Utama, lalu aku bisa cek saldo bukunya dari data lokal.',
      );
    }
    final matches = accounts
        .where(
          (account) => request.normalizedText.contains(_fold(account.name)),
        )
        .toList(growable: false);
    if (matches.length != 1) {
      final names = accounts.map((item) => item.name).join(', ');
      return FfmAssistantQueryAnswer(
        title: 'Saldo rekening',
        message:
            'Mau cek saldo rekening yang mana? Rekening aktif: $names. Sebutkan namanya supaya tidak salah.',
      );
    }
    final account = matches.single;
    final transactions =
        await (_database.select(_database.transactions)..where(
              (row) =>
                  row.householdId.equals(request.householdId) &
                  row.accountId.equals(account.id) &
                  row.isArchived.equals(false) &
                  row.isDeleted.equals(false),
            ))
            .get();
    final transfers =
        await (_database.select(_database.transfers)..where(
              (row) =>
                  row.householdId.equals(request.householdId) &
                  (row.fromAccountId.equals(account.id) |
                      row.toAccountId.equals(account.id)) &
                  row.isDeleted.equals(false),
            ))
            .get();
    var balance = account.openingBalance;
    for (final row in transactions) {
      if (row.type == 'income') balance += row.amount.abs();
      if (row.type == 'expense') balance -= row.amount.abs();
    }
    for (final transfer in transfers) {
      if (transfer.fromAccountId == account.id) balance -= transfer.amount;
      if (transfer.toAccountId == account.id) balance += transfer.amount;
    }
    return FfmAssistantQueryAnswer(
      title: 'Saldo ${account.name}',
      message:
          'Saldo buku ${account.name} saat ini ${_rupiah(balance)}. Ini dihitung dari saldo awal, transaksi yang tidak diarsipkan, dan perpindahan dana yang tercatat.',
    );
  }
}

class _TransactionSummaryQueryTool implements FfmAssistantQueryTool {
  const _TransactionSummaryQueryTool(this._database);

  final AppDatabase _database;

  @override
  bool canHandle(String normalizedText) =>
      (normalizedText.contains('pemasukan') ||
          normalizedText.contains('pengeluaran') ||
          normalizedText.contains('transaksi')) &&
      (normalizedText.contains('berapa') ||
          normalizedText.contains('total') ||
          normalizedText.contains('bulan') ||
          normalizedText.contains('minggu'));

  @override
  Future<FfmAssistantQueryAnswer?> answer(
    FfmAssistantQueryRequest request,
  ) async {
    final isWeek = request.normalizedText.contains('minggu');
    final start = isWeek
        ? DateTime(
            request.now.year,
            request.now.month,
            request.now.day,
          ).subtract(Duration(days: request.now.weekday - 1))
        : DateTime(request.now.year, request.now.month);
    final end = isWeek
        ? start.add(const Duration(days: 7))
        : DateTime(start.year, start.month + 1);
    final rows =
        await (_database.select(_database.transactions)..where(
              (row) =>
                  row.householdId.equals(request.householdId) &
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
    final period = isWeek ? 'minggu ini' : 'bulan ini';
    return FfmAssistantQueryAnswer(
      title: 'Ringkasan $period',
      message:
          'Dari $count transaksi tercatat pada $period: pemasukan ${_rupiah(income)} dan pengeluaran ${_rupiah(expense)}. Transfer antar rekening tidak dihitung sebagai pemasukan atau pengeluaran.',
    );
  }
}

class _ActiveActivityQueryTool implements FfmAssistantQueryTool {
  const _ActiveActivityQueryTool(this._database);

  final AppDatabase _database;

  @override
  bool canHandle(String normalizedText) =>
      normalizedText.contains('aktivitas aktif') ||
      normalizedText.contains('lagi apa') ||
      normalizedText.contains('sedang apa') ||
      normalizedText.contains('aktivitas berjalan');

  @override
  Future<FfmAssistantQueryAnswer?> answer(
    FfmAssistantQueryRequest request,
  ) async {
    final rows =
        await (_database.select(_database.activitySessions)
              ..where(
                (row) =>
                    row.householdId.equals(request.householdId) &
                    row.status.equals('active') &
                    row.isArchived.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.startedAt)]))
            .get();
    if (rows.isEmpty) {
      return const FfmAssistantQueryAnswer(
        title: 'Aktivitas aktif',
        message: 'Tidak ada aktivitas aktif sekarang. Kamu bisa bilang “mulai aktivitas [nama]” kalau mau menyiapkan catatan aktivitas.',
      );
    }
    final lines = rows
        .map((row) {
          final duration = request.now.difference(row.startedAt);
          return '• ${row.title} — ${_duration(duration)}';
        })
        .join('\n');
    return FfmAssistantQueryAnswer(
      title: 'Aktivitas aktif',
      message: 'Ada ${rows.length} aktivitas yang masih berjalan:\n$lines',
    );
  }
}

class _GoalStatusQueryTool implements FfmAssistantQueryTool {
  const _GoalStatusQueryTool(this._database);

  final AppDatabase _database;

  @override
  bool canHandle(String normalizedText) =>
      (normalizedText.contains('target') ||
          normalizedText.contains('tujuan')) &&
      (normalizedText.contains('status') ||
          normalizedText.contains('progres') ||
          normalizedText.contains('sisa') ||
          normalizedText.contains('berapa'));

  @override
  Future<FfmAssistantQueryAnswer?> answer(
    FfmAssistantQueryRequest request,
  ) async {
    final rows =
        await (_database.select(_database.goals)..where(
              (row) =>
                  row.householdId.equals(request.householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    if (rows.isEmpty) {
      return const FfmAssistantQueryAnswer(
        title: 'Target keuangan',
        message: 'Belum ada target keuangan aktif. Kalau kamu mau, sebut nama target dan nominalnya supaya aku siapkan rancangan form.',
      );
    }
    final matched = rows
        .where((row) => request.normalizedText.contains(_fold(row.name)))
        .toList(growable: false);
    final goal = matched.length == 1 ? matched.single : rows.first;
    final remaining = (goal.targetAmount - goal.currentAmount).clamp(
      0,
      goal.targetAmount,
    );
    final percent = goal.targetAmount == 0
        ? 0
        : ((goal.currentAmount / goal.targetAmount) * 100).round();
    return FfmAssistantQueryAnswer(
      title: 'Target ${goal.name}',
      message:
          'Target ${goal.name}: terkumpul ${_rupiah(goal.currentAmount)} dari ${_rupiah(goal.targetAmount)} ($percent%). Sisa ${_rupiah(remaining)}. Ini hanya informasi, belum ada setoran atau perubahan data.',
    );
  }
}

class _DebtStatusQueryTool implements FfmAssistantQueryTool {
  const _DebtStatusQueryTool(this._database);

  final AppDatabase _database;

  @override
  bool canHandle(String normalizedText) =>
      (normalizedText.contains('hutang') ||
          normalizedText.contains('utang') ||
          normalizedText.contains('piutang')) &&
      (normalizedText.contains('status') ||
          normalizedText.contains('sisa') ||
          normalizedText.contains('total') ||
          normalizedText.contains('berapa'));

  @override
  Future<FfmAssistantQueryAnswer?> answer(
    FfmAssistantQueryRequest request,
  ) async {
    final asksReceivable = request.normalizedText.contains('piutang');
    if (asksReceivable) {
      final rows =
          await (_database.select(_database.receivables)..where(
                (row) =>
                    row.householdId.equals(request.householdId) &
                    row.isActive.equals(true),
              ))
              .get();
      final total = rows.fold<int>(0, (sum, row) => sum + row.remainingBalance);
      return FfmAssistantQueryAnswer(
        title: 'Piutang aktif',
        message: rows.isEmpty
            ? 'Belum ada piutang aktif yang tercatat.'
            : 'Ada ${rows.length} piutang aktif dengan sisa total ${_rupiah(total)}.',
      );
    }
    final rows =
        await (_database.select(_database.liabilities)..where(
              (row) =>
                  row.householdId.equals(request.householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    final total = rows.fold<int>(0, (sum, row) => sum + row.remainingBalance);
    return FfmAssistantQueryAnswer(
      title: 'Hutang aktif',
      message: rows.isEmpty
          ? 'Belum ada hutang aktif yang tercatat.'
          : 'Ada ${rows.length} hutang aktif dengan sisa total ${_rupiah(total)}.',
    );
  }
}

class _AssetSummaryQueryTool implements FfmAssistantQueryTool {
  const _AssetSummaryQueryTool(this._database);

  final AppDatabase _database;

  @override
  bool canHandle(String normalizedText) =>
      normalizedText.contains('aset') &&
      (normalizedText.contains('total') ||
          normalizedText.contains('nilai') ||
          normalizedText.contains('berapa'));

  @override
  Future<FfmAssistantQueryAnswer?> answer(
    FfmAssistantQueryRequest request,
  ) async {
    final rows =
        await (_database.select(_database.assets)..where(
              (row) =>
                  row.householdId.equals(request.householdId) &
                  row.isArchived.equals(false),
            ))
            .get();
    final total = rows.fold<int>(0, (sum, row) => sum + row.value);
    return FfmAssistantQueryAnswer(
      title: 'Aset tercatat',
      message: rows.isEmpty
          ? 'Belum ada aset tercatat.'
          : 'Ada ${rows.length} aset aktif dengan nilai tercatat total ${_rupiah(total)}.',
    );
  }
}

String _fold(String value) =>
    value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

String _rupiah(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
    buffer.write(digits[index]);
  }
  return '${amount < 0 ? '-' : ''}Rp$buffer';
}

String _duration(Duration value) {
  if (value.inHours > 0) {
    return '${value.inHours} jam ${value.inMinutes.remainder(60)} menit';
  }
  return '${value.inMinutes} menit';
}
