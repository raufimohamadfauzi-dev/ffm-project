import '../../../core/database/app_database.dart';

import 'package:drift/drift.dart';

import 'entities/activity_entity.dart';

/// Activity Query Layer untuk Activity Intelligence Upgrade
///
/// Layer ini menyediakan kemampuan query deterministik di atas data aktivitas
/// dengan filter yang kuat sebelum data masuk ke LLM.
///
/// Prinsip:
/// - Filter dilakukan di query/data layer, bukan hanya menyembunyikan hasil
/// - Semua hasil dapat ditelusuri ke data sumber
/// - Mendukung pencarian berdasarkan ID, group, subject, kategori, dll
class ActivityQueryLayer {
  const ActivityQueryLayer(this.database);

  final AppDatabase database;

  /// Query aktivitas dengan filter fleksibel
  Future<List<ActivitySessionEntity>> queryActivities({
    required String householdId,
    DateTime? startDate,
    DateTime? endDate,
    String? activityId,
    String? activityGroupId,
    String? categoryId,
    String? category,
    String? subjectType,
    String? subjectId,
    String? status,
    String? kind,
    String? keyword,
    bool includeArchived = false,
    int? limit,
    int? offset,
  }) async {
    var query = database.select(database.activitySessions)
      ..where((row) => row.householdId.equals(householdId));

    // Filter archive status
    if (!includeArchived) {
      query = query..where((row) => row.isArchived.equals(false));
    }

    // Filter tanggal
    if (startDate != null) {
      query = query
        ..where((row) => row.startedAt.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query = query
        ..where((row) => row.startedAt.isSmallerOrEqualValue(endDate));
    }

    // Filter ID spesifik
    if (activityId != null) {
      query = query..where((row) => row.id.equals(activityId));
    }

    // Filter group ID
    if (activityGroupId != null) {
      query = query
        ..where((row) => row.activityGroupId.equals(activityGroupId));
    }

    // Filter kategori
    if (categoryId != null) {
      query = query..where((row) => row.categoryId.equals(categoryId));
    }
    if (category != null) {
      query = query..where((row) => row.category.equals(category));
    }

    // Filter subject
    if (subjectType != null) {
      query = query..where((row) => row.subjectType.equals(subjectType));
    }
    if (subjectId != null) {
      query = query..where((row) => row.subjectId.equals(subjectId));
    }

    // Filter status
    if (status != null) {
      query = query..where((row) => row.status.equals(status));
    }

    // Filter kind
    if (kind != null) {
      query = query..where((row) => row.kind.equals(kind));
    }

    // Filter keyword di title
    if (keyword != null && keyword.isNotEmpty) {
      query = query..where((row) => row.title.contains(keyword));
    }

    // Ordering default: terbaru dulu
    query = query..orderBy([(row) => OrderingTerm.desc(row.startedAt)]);

    // Pagination
    if (limit != null) {
      query = query..limit(limit, offset: offset ?? 0);
    }

    final rows = await query.get();
    return rows.map(_fromRow).toList();
  }

  /// Query aktivitas berdasarkan ID spesifik
  Future<ActivitySessionEntity?> queryById(
    String householdId,
    String activityId,
  ) async {
    final row =
        await (database.select(database.activitySessions)..where(
              (row) =>
                  row.householdId.equals(householdId) &
                  row.id.equals(activityId),
            ))
            .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  /// Query aktivitas berdasarkan group ID
  Future<List<ActivitySessionEntity>> queryByGroup(
    String householdId,
    String activityGroupId, {
    bool includeArchived = false,
  }) async {
    return queryActivities(
      householdId: householdId,
      activityGroupId: activityGroupId,
      includeArchived: includeArchived,
    );
  }

  /// Query aktivitas berdasarkan subject
  Future<List<ActivitySessionEntity>> queryBySubject(
    String householdId,
    String subjectType,
    String subjectId, {
    bool includeArchived = false,
  }) async {
    return queryActivities(
      householdId: householdId,
      subjectType: subjectType,
      subjectId: subjectId,
      includeArchived: includeArchived,
    );
  }

  /// Query aktivitas berdasarkan kategori
  Future<List<ActivitySessionEntity>> queryByCategory(
    String householdId,
    String category, {
    DateTime? startDate,
    DateTime? endDate,
    bool includeArchived = false,
  }) async {
    return queryActivities(
      householdId: householdId,
      category: category,
      startDate: startDate,
      endDate: endDate,
      includeArchived: includeArchived,
    );
  }

  /// Query timeline aktivitas untuk visualisasi
  Future<List<ActivitySessionEntity>> queryTimeline({
    required String householdId,
    required DateTime startDate,
    required DateTime endDate,
    String? category,
    String? activityGroupId,
    bool includeArchived = false,
  }) async {
    return queryActivities(
      householdId: householdId,
      startDate: startDate,
      endDate: endDate,
      category: category,
      activityGroupId: activityGroupId,
      includeArchived: includeArchived,
    );
  }

  /// Query aktivitas dengan filter kompleks untuk analisis
  Future<ActivityQueryResult> queryForAnalysis({
    required String householdId,
    DateTime? startDate,
    DateTime? endDate,
    String? activityId,
    String? category,
    String? activityGroupId,
    String? subjectType,
    String? subjectId,
    String? status,
    String? kind,
  }) async {
    final activities = await queryActivities(
      householdId: householdId,
      startDate: startDate,
      endDate: endDate,
      activityId: activityId,
      category: category,
      activityGroupId: activityGroupId,
      subjectType: subjectType,
      subjectId: subjectId,
      status: status,
      kind: kind,
      includeArchived: false,
    );

    return ActivityQueryResult(
      activities: activities,
      count: activities.length,
      sourceRecordIds: activities.map((a) => a.id).toList(),
      filters: ActivityQueryFilters(
        householdId: householdId,
        startDate: startDate,
        endDate: endDate,
        activityId: activityId,
        category: category,
        activityGroupId: activityGroupId,
        subjectType: subjectType,
        subjectId: subjectId,
        status: status,
        kind: kind,
      ),
    );
  }

  ActivitySessionEntity _fromRow(ActivitySession row) => ActivitySessionEntity(
    id: row.id,
    householdId: row.householdId,
    title: row.title,
    category: row.category,
    categoryId: row.categoryId,
    kind: ActivityKind.fromValue(row.kind),
    parentSessionId: row.parentSessionId,
    activityGroupId: row.activityGroupId,
    subjectType: row.subjectType,
    subjectId: row.subjectId,
    startedAt: row.startedAt,
    endedAt: row.endedAt,
    scheduledAt: row.scheduledAt,
    dueDate: row.dueDate,
    isAllDay: row.isAllDay,
    isCompleted: row.isCompleted,
    priority: row.priority,
    status: ActivitySessionStatus.fromValue(row.status),
    notes: row.notes,
    isArchived: row.isArchived,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

/// Hasil query yang dapat digunakan untuk analisis dan verifikasi
class ActivityQueryResult {
  const ActivityQueryResult({
    required this.activities,
    required this.count,
    required this.sourceRecordIds,
    required this.filters,
  });

  final List<ActivitySessionEntity> activities;
  final int count;
  final List<String> sourceRecordIds;
  final ActivityQueryFilters filters;
}

/// Filter yang digunakan untuk query - dapat digunakan untuk logging dan debugging
class ActivityQueryFilters {
  const ActivityQueryFilters({
    required this.householdId,
    this.startDate,
    this.endDate,
    this.activityId,
    this.category,
    this.activityGroupId,
    this.subjectType,
    this.subjectId,
    this.status,
    this.kind,
  });

  final String householdId;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? activityId;
  final String? category;
  final String? activityGroupId;
  final String? subjectType;
  final String? subjectId;
  final String? status;
  final String? kind;

  Map<String, dynamic> toMap() => {
    'householdId': householdId,
    'startDate': startDate?.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
    'activityId': activityId,
    'category': category,
    'activityGroupId': activityGroupId,
    'subjectType': subjectType,
    'subjectId': subjectId,
    'status': status,
    'kind': kind,
  };
}
