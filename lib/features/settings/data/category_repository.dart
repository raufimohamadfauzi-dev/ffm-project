import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/audit_logger.dart';

/// Jalur persistence resmi Kategori Data Utama.
///
/// Agent hanya menerima [updateName] dan [archive]. Field kategori yang dapat
/// mengubah klasifikasi atau cakupan Anggaran tetap dipertahankan.
class CategoryRepository {
  CategoryRepository(
    this._database,
    this._auditLogger, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const maxNameLength = 160;

  final AppDatabase _database;
  final AuditLogger _auditLogger;
  final DateTime Function() _clock;

  Future<List<Category>> readActive(String householdId, {String? type}) =>
      (_database.select(_database.categories)
            ..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true) &
                  (type == null ? const Constant(true) : row.type.equals(type)),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.name)]))
          .get();

  Future<Category?> get(String householdId, String id) =>
      (_database.select(_database.categories)..where(
            (row) => row.householdId.equals(householdId) & row.id.equals(id),
          ))
          .getSingleOrNull();

  /// Dipakai UI Data Utama; bukan capability Agent.
  Future<Category> create({
    required String id,
    required String householdId,
    required String name,
    required String type,
    String? parentId,
    required String defaultBudgetPeriod,
  }) async {
    final normalizedName = _name(name);
    await _ensureUniqueName(householdId, normalizedName, type: type);
    final now = _clock();
    await _database
        .into(_database.categories)
        .insert(
          CategoriesCompanion.insert(
            id: id,
            householdId: householdId,
            name: normalizedName,
            type: type,
            parentId: Value(parentId),
            defaultBudgetPeriod: Value(defaultBudgetPeriod),
            createdAt: now,
          ),
        );
    final created = (await get(householdId, id))!;
    await _auditLogger.record(
      action: 'create',
      entity: 'category',
      householdId: householdId,
      newValue: _auditValue(created),
    );
    return created;
  }

  /// Dipakai UI Data Utama; tidak diekspos ke Agent.
  Future<Category?> updateFromUser({
    required String householdId,
    required String id,
    required String name,
    required String type,
    String? parentId,
    required String defaultBudgetPeriod,
  }) async {
    final before = await get(householdId, id);
    if (before == null || !before.isActive) return null;
    final normalizedName = _name(name);
    await _ensureUniqueName(
      householdId,
      normalizedName,
      type: type,
      excludeId: id,
    );
    await (_database.update(_database.categories)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(
          CategoriesCompanion(
            name: Value(normalizedName),
            type: Value(type),
            parentId: Value(parentId),
            defaultBudgetPeriod: Value(defaultBudgetPeriod),
          ),
        );
    final updated = (await get(householdId, id))!;
    await _auditLogger.record(
      action: 'update',
      entity: 'category',
      householdId: householdId,
      oldValue: _auditValue(before),
      newValue: _auditValue(updated),
    );
    return updated;
  }

  /// Satu-satunya update yang dapat dipakai Agent.
  Future<Category?> updateName({
    required String householdId,
    required String id,
    required String name,
  }) async {
    final before = await get(householdId, id);
    if (before == null || !before.isActive) return null;
    final normalizedName = _name(name);
    await _ensureUniqueName(
      householdId,
      normalizedName,
      type: before.type,
      excludeId: id,
    );
    if (before.name == normalizedName) return before;
    await (_database.update(_database.categories)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(CategoriesCompanion(name: Value(normalizedName)));
    final updated = (await get(householdId, id))!;
    await _auditLogger.record(
      action: 'update',
      entity: 'category',
      householdId: householdId,
      oldValue: _auditValue(before),
      newValue: _auditValue(updated),
    );
    return updated;
  }

  Future<String?> archiveBlockReason({
    required String householdId,
    required String id,
  }) async {
    final activeChild =
        await (_database.select(_database.categories)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.parentId.equals(id) &
                  row.isActive.equals(true),
            ))
            .getSingleOrNull();
    if (activeChild != null) {
      return 'Kategori masih menjadi induk bagi subkategori aktif “${activeChild.name}”.';
    }
    final recurring =
        await (_database.select(_database.recurringTransactions)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.categoryId.equals(id) &
                  row.isActive.equals(true),
            ))
            .getSingleOrNull();
    if (recurring != null) {
      return 'Kategori masih dipakai transaksi berkala aktif “${recurring.name}”.';
    }
    final goal =
        await (_database.select(_database.goals)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.categoryId.equals(id) &
                  row.isActive.equals(true),
            ))
            .getSingleOrNull();
    if (goal != null) {
      return 'Kategori masih dipakai Target Keuangan aktif “${goal.name}”.';
    }
    final activeBudgets =
        await (_database.select(_database.envelopeBudgets)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.isActive.equals(true),
            ))
            .get();
    for (final budget in activeBudgets) {
      if (budget.categoryId == id || _budgetCategoryIds(budget).contains(id)) {
        return 'Kategori masih dirujuk Anggaran aktif “${budget.name}”.';
      }
    }
    return null;
  }

  Future<Category?> archive({
    required String householdId,
    required String id,
  }) async {
    final before = await get(householdId, id);
    if (before == null || !before.isActive) return null;
    final block = await archiveBlockReason(householdId: householdId, id: id);
    if (block != null) throw StateError(block);
    await (_database.update(_database.categories)..where(
          (row) => row.householdId.equals(householdId) & row.id.equals(id),
        ))
        .write(const CategoriesCompanion(isActive: Value(false)));
    final archived = await get(householdId, id);
    await _auditLogger.record(
      action: 'archive',
      entity: 'category',
      householdId: householdId,
      oldValue: _auditValue(before),
      newValue: archived == null ? null : _auditValue(archived),
    );
    return archived;
  }

  Future<void> _ensureUniqueName(
    String householdId,
    String name, {
    required String type,
    String? excludeId,
  }) async {
    final rows = await readActive(householdId, type: type);
    final duplicate = rows.any(
      (row) =>
          row.id != excludeId &&
          row.type == type &&
          row.name.toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) {
      throw ArgumentError.value(
        name,
        'name',
        'Nama kategori aktif dengan tipe yang sama sudah dipakai.',
      );
    }
  }

  String _name(String value) {
    final normalized = value
        .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'name', 'Nama kategori wajib diisi.');
    }
    if (normalized.length > maxNameLength) {
      throw ArgumentError.value(
        value,
        'name',
        'Nama kategori terlalu panjang.',
      );
    }
    return normalized;
  }

  Set<String> _budgetCategoryIds(EnvelopeBudget budget) {
    try {
      final decoded = jsonDecode(budget.categoryIdsJson);
      if (decoded is! List) return const <String>{};
      return decoded.whereType<String>().toSet();
    } on FormatException {
      return const <String>{};
    }
  }

  Map<String, Object?> _auditValue(Category category) => {
    'id': category.id,
    'name': category.name,
    'type': category.type,
    'parentId': category.parentId,
    'defaultBudgetPeriod': category.defaultBudgetPeriod,
    'isActive': category.isActive,
  };
}
