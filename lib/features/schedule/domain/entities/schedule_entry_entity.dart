/// Agenda lokal satu kali yang terpisah dari Rutinitas, Pengingat, Aktivitas,
/// dan transaksi berkala. Tidak membawa alarm atau tindakan otomatis.
class ScheduleEntryEntity {
  const ScheduleEntryEntity({
    required this.id,
    required this.householdId,
    required this.title,
    required this.scheduledDate,
    required this.isAllDay,
    required this.isArchived,
    required this.createdAt,
    this.note,
    this.startMinutes,
    this.endMinutes,
    this.updatedAt,
  });

  final String id;
  final String householdId;
  final String title;
  final String? note;
  final DateTime scheduledDate;
  final bool isAllDay;
  final int? startMinutes;
  final int? endMinutes;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime? updatedAt;

  String? get timeRangeLabel {
    if (isAllDay || startMinutes == null) return null;
    final start = _time(startMinutes!);
    return endMinutes == null ? start : '$start–${_time(endMinutes!)}';
  }

  static String _time(int minutes) {
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }
}
