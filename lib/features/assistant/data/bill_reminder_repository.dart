import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import 'calendar_bridge.dart';

/// Repository untuk mengelola pengingat tagihan dan sinkronisasi ke kalender.
class BillReminderRepository {
  BillReminderRepository(this._db, this._calendarBridge);

  final AppDatabase _db;
  final CalendarBridge _calendarBridge;

  /// Membuat pengingat tagihan baru dan menyinkronkan ke kalender.
  Future<BillReminder> createBillReminder({
    required String householdId,
    required String title,
    required String description,
    required DateTime dueDate,
    required double amount,
    required String category,
    required String recurrenceType,
    required String weekdaysJson,
    bool syncToCalendar = true,
  }) async {
    final reminderId = _generateId();
    final now = DateTime.now();

    final reminder = RemindersCompanion.insert(
      id: reminderId,
      householdId: householdId,
      title: title,
      scheduledAt: dueDate,
      notificationId: DateTime.now().millisecondsSinceEpoch % 1000000,
      createdAt: now,
      note: Value(description),
      recurrenceType: Value(recurrenceType),
      weekdaysJson: Value(weekdaysJson),
      isActive: const Value(true),
      defaultSnoozeMinutes: const Value(10),
      updatedAt: Value(now),
      calendarEventId: const Value(null),
      isSyncedToCalendar: const Value(false),
      syncedAt: const Value(null),
    );

    await _db.into(_db.reminders).insertOnConflictUpdate(reminder);

    if (syncToCalendar) {
      await _syncToCalendar(reminderId, title, description, dueDate, amount, category);
    }

    final inserted = await (_db.select(_db.reminders)
          ..where((row) => row.id.equals(reminderId)))
        .getSingle();

    return _toBillReminder(inserted);
  }

  /// Mengupdate pengingat tagihan dan menyinkronkan perubahan ke kalender.
  Future<BillReminder> updateBillReminder({
    required String reminderId,
    String? title,
    String? description,
    DateTime? dueDate,
    double? amount,
    String? category,
    String? recurrenceType,
    String? weekdaysJson,
    bool? isActive,
    bool syncToCalendar = true,
  }) async {
    final existing = await (_db.select(_db.reminders)
          ..where((row) => row.id.equals(reminderId)))
        .getSingleOrNull();

    if (existing == null) {
      throw Exception('Pengingat tidak ditemukan');
    }

    final updated = existing.copyWith(
      title: title ?? existing.title,
      note: description != null ? Value(description) : const Value.absent(),
      scheduledAt: dueDate ?? existing.scheduledAt,
      recurrenceType: recurrenceType ?? existing.recurrenceType,
      weekdaysJson: weekdaysJson ?? existing.weekdaysJson,
      isActive: isActive ?? existing.isActive,
      updatedAt: Value(DateTime.now()),
    );

    await _db.update(_db.reminders).replace(updated);

    if (syncToCalendar && existing.calendarEventId != null) {
      await _updateCalendarEvent(
        existing.calendarEventId!,
        updated.title,
        updated.note ?? '',
        updated.scheduledAt,
        amount ?? 0.0,
        category ?? '',
      );
    } else if (syncToCalendar && existing.calendarEventId == null) {
      await _syncToCalendar(
        reminderId,
        updated.title,
        updated.note ?? '',
        updated.scheduledAt,
        amount ?? 0.0,
        category ?? '',
      );
    }

    return _toBillReminder(updated);
  }

  /// Menghapus pengingat tagihan dan menghapus dari kalender jika disinkronkan.
  Future<void> deleteBillReminder(String reminderId) async {
    final existing = await (_db.select(_db.reminders)
          ..where((row) => row.id.equals(reminderId)))
        .getSingleOrNull();

    if (existing != null && existing.calendarEventId != null) {
      await _deleteFromCalendar(existing.calendarEventId!);
    }

    await (_db.delete(_db.reminders)..where((row) => row.id.equals(reminderId))).go();
  }

  /// Mengambil pengingat tagihan berdasarkan ID.
  Future<BillReminder?> getBillReminder(String reminderId) async {
    final reminder = await (_db.select(_db.reminders)
          ..where((row) => row.id.equals(reminderId)))
        .getSingleOrNull();
    return reminder != null ? _toBillReminder(reminder) : null;
  }

  /// Mengambil semua pengingat tagihan untuk household.
  Future<List<BillReminder>> getBillReminders(String householdId) async {
    final reminders = await (_db.select(_db.reminders)
          ..where((row) => row.householdId.equals(householdId))
          ..orderBy([(row) => OrderingTerm.asc(row.scheduledAt)]))
        .get();

    return reminders.map(_toBillReminder).toList();
  }

  /// Mengambil pengingat tagihan yang aktif dalam rentang tanggal.
  Future<List<BillReminder>> getActiveBillRemindersInRange(
    String householdId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final reminders = await (_db.select(_db.reminders)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isActive.equals(true) &
              row.scheduledAt.isBiggerOrEqualValue(startDate) &
              row.scheduledAt.isSmallerOrEqualValue(endDate))
          ..orderBy([(row) => OrderingTerm.asc(row.scheduledAt)]))
        .get();

    return reminders.map(_toBillReminder).toList();
  }

  /// Menyinkronkan pengingat ke kalender Android.
  Future<void> _syncToCalendar(
    String reminderId,
    String title,
    String description,
    DateTime dueDate,
    double amount,
    String category,
  ) async {
    try {
      final data = BillReminderData(
        title: title,
        description: description,
        dueDate: dueDate,
        amount: amount,
        category: category,
      );

      final result = await _calendarBridge.createBillReminder(data);

      if (result.success && result.eventId != null) {
        await (_db.update(_db.reminders)
              ..where((row) => row.id.equals(reminderId)))
            .write(RemindersCompanion(
          calendarEventId: Value(result.eventId),
          isSyncedToCalendar: const Value(true),
          syncedAt: Value(DateTime.now()),
        ));
      }
    } catch (e) {
      debugPrint('Gagal menyinkronkan ke kalender: $e');
    }
  }

  /// Mengupdate event yang sudah ada di kalender.
  Future<void> _updateCalendarEvent(
    int eventId,
    String title,
    String description,
    DateTime dueDate,
    double amount,
    String category,
  ) async {
    try {
      final data = BillReminderData(
        title: title,
        description: description,
        dueDate: dueDate,
        amount: amount,
        category: category,
      );

      await _calendarBridge.updateBillReminder(eventId, data);
    } catch (e) {
      debugPrint('Gagal mengupdate event kalender: $e');
    }
  }

  /// Menghapus event dari kalender.
  Future<void> _deleteFromCalendar(int eventId) async {
    try {
      await _calendarBridge.deleteBillReminder(eventId);
    } catch (e) {
      debugPrint('Gagal menghapus event kalender: $e');
    }
  }

  /// Retry sinkronisasi untuk pengingat yang belum disinkronkan.
  Future<void> retrySyncForUnsynced(String householdId) async {
    final unsynced = await (_db.select(_db.reminders)
          ..where((row) =>
              row.householdId.equals(householdId) &
              row.isSyncedToCalendar.equals(false) &
              row.isActive.equals(true)))
        .get();

    for (final reminder in unsynced) {
      await _syncToCalendar(
        reminder.id,
        reminder.title,
        reminder.note ?? '',
        reminder.scheduledAt,
        0.0, // Amount tidak tersimpan di Reminder table
        '', // Category tidak tersimpan di Reminder table
      );
    }
  }

  /// Mengubah Reminder entity ke BillReminder model.
  BillReminder _toBillReminder(Reminder reminder) {
    return BillReminder(
      id: reminder.id,
      calendarEventId: reminder.calendarEventId,
      billName: reminder.title,
      description: reminder.note,
      dueDate: reminder.scheduledAt,
      amount: 0.0, // Amount tidak tersimpan di Reminder table
      category: '', // Category tidak tersimpan di Reminder table
      reminderSettings: ReminderSettings(
        recurrenceType: reminder.recurrenceType,
        weekdaysJson: reminder.weekdaysJson,
        defaultSnoozeMinutes: reminder.defaultSnoozeMinutes,
      ),
      isSyncedToCalendar: reminder.isSyncedToCalendar,
      syncedAt: reminder.syncedAt,
    );
  }

  String _generateId() {
    return 'bill-${DateTime.now().millisecondsSinceEpoch}-${_randomId()}';
  }

  String _randomId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    final buffer = StringBuffer();
    for (int i = 0; i < 8; i++) {
      buffer.write(chars[(random + i) % chars.length]);
    }
    return buffer.toString();
  }
}

/// Model pengingat tagihan untuk digunakan di aplikasi.
class BillReminder {
  const BillReminder({
    required this.id,
    required this.calendarEventId,
    required this.billName,
    required this.description,
    required this.dueDate,
    required this.amount,
    required this.category,
    required this.reminderSettings,
    required this.isSyncedToCalendar,
    required this.syncedAt,
  });

  final String id;
  final int? calendarEventId;
  final String billName;
  final String? description;
  final DateTime dueDate;
  final double amount;
  final String category;
  final ReminderSettings reminderSettings;
  final bool isSyncedToCalendar;
  final DateTime? syncedAt;
}

/// Pengaturan pengingat untuk tagihan.
class ReminderSettings {
  const ReminderSettings({
    required this.recurrenceType,
    required this.weekdaysJson,
    required this.defaultSnoozeMinutes,
  });

  final String recurrenceType;
  final String weekdaysJson;
  final int defaultSnoozeMinutes;
}