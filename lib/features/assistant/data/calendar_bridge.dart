import 'package:flutter/services.dart';

/// Hasil operasi kalender (create/update/delete).
class CalendarOperationResult {
  const CalendarOperationResult({
    required this.success,
    required this.eventId,
    this.error,
    this.calendarId,
    this.rowsUpdated,
    this.rowsDeleted,
  });

  final bool success;
  final int? eventId;
  final String? error;
  final int? calendarId;
  final int? rowsUpdated;
  final int? rowsDeleted;

  factory CalendarOperationResult.fromMap(Map<dynamic, dynamic> map) {
    return CalendarOperationResult(
      success: map['success'] as bool? ?? false,
      eventId: map['eventId'] as int?,
      error: map['error'] as String?,
      calendarId: map['calendarId'] as int?,
      rowsUpdated: map['rowsUpdated'] as int?,
      rowsDeleted: map['rowsDeleted'] as int?,
    );
  }
}

/// Data pengingat tagihan untuk dibuat di kalender.
class BillReminderData {
  const BillReminderData({
    required this.title,
    required this.description,
    required this.dueDate,
    required this.amount,
    required this.category,
  });

  final String title;
  final String description;
  final DateTime dueDate;
  final double amount;
  final String category;

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'dueDate': dueDate.millisecondsSinceEpoch,
      'amount': amount,
      'category': category,
    };
  }
}

/// Informasi event pengingat dari kalender.
class CalendarReminder {
  const CalendarReminder({
    required this.eventId,
    required this.title,
    required this.description,
    required this.dtStart,
    required this.dtEnd,
  });

  final int eventId;
  final String title;
  final String description;
  final DateTime dtStart;
  final DateTime dtEnd;

  factory CalendarReminder.fromMap(Map<dynamic, dynamic> map) {
    return CalendarReminder(
      eventId: map['eventId'] as int,
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      dtStart: DateTime.fromMillisecondsSinceEpoch(map['dtStart'] as int),
      dtEnd: DateTime.fromMillisecondsSinceEpoch(map['dtEnd'] as int),
    );
  }
}

/// Jembatan antara Flutter dan Native Kotlin Calendar Service (`FfmCalendarService.kt`).
class CalendarBridge {
  CalendarBridge();

  static const _channel = MethodChannel('ffm/calendar_service');

  /// Memeriksa apakah kalender tersedia di perangkat.
  Future<bool> isCalendarAvailable() async {
    try {
      final res = await _channel.invokeMethod<bool>('isAvailable');
      return res ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Meminta izin kalender ke pengguna.
  Future<bool> requestCalendarPermissions() async {
    try {
      final res = await _channel.invokeMethod<bool>('requestCalendarPermissions');
      return res ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Mengambil ID kalender utama pengguna.
  Future<int?> getDefaultCalendarId() async {
    try {
      final res = await _channel.invokeMethod<int?>('getDefaultCalendarId');
      return res;
    } on PlatformException {
      return null;
    }
  }

  /// Membuat pengingat tagihan di kalender.
  Future<CalendarOperationResult> createBillReminder(BillReminderData data) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'createBillReminder',
        data.toMap(),
      );
      return CalendarOperationResult.fromMap(res ?? {});
    } on PlatformException catch (e) {
      return CalendarOperationResult(
        success: false,
        eventId: null,
        error: e.message ?? 'Gagal membuat pengingat kalender',
      );
    }
  }

  /// Mengupdate pengingat tagihan yang sudah ada.
  Future<CalendarOperationResult> updateBillReminder(
    int eventId,
    BillReminderData data,
  ) async {
    try {
      final params = {
        'eventId': eventId,
        ...data.toMap(),
      };
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'updateBillReminder',
        params,
      );
      return CalendarOperationResult.fromMap(res ?? {});
    } on PlatformException catch (e) {
      return CalendarOperationResult(
        success: false,
        eventId: eventId,
        error: e.message ?? 'Gagal mengupdate pengingat kalender',
      );
    }
  }

  /// Menghapus pengingat tagihan dari kalender.
  Future<CalendarOperationResult> deleteBillReminder(int eventId) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'deleteBillReminder',
        {'eventId': eventId},
      );
      return CalendarOperationResult.fromMap(res ?? {});
    } on PlatformException catch (e) {
      return CalendarOperationResult(
        success: false,
        eventId: eventId,
        error: e.message ?? 'Gagal menghapus pengingat kalender',
      );
    }
  }

  /// Mengambil daftar pengingat tagihan dalam rentang tanggal.
  Future<List<CalendarReminder>> getBillReminders(
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final res = await _channel.invokeMethod<List<dynamic>>(
        'getBillReminders',
        {
          'startDate': startDate.millisecondsSinceEpoch,
          'endDate': endDate.millisecondsSinceEpoch,
        },
      );

      if (res == null) return [];

      return res
          .map((e) => CalendarReminder.fromMap(e as Map<dynamic, dynamic>))
          .toList();
    } on PlatformException {
      return [];
    }
  }
}