import 'package:ffm_manager/features/activity/domain/activity_mode_detector.dart';
import 'package:ffm_manager/features/activity/domain/entities/activity_entity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const detector = ActivityModeDetector();

  group('ActivityModeDetector', () {
    test('aktivitas yang sedang berjalan menggunakan timer', () {
      final result = detector.detect('Saya lagi berkebun');

      expect(result.mode, ActivityMode.timeTracking);
      expect(result.requiresClarification, isFalse);
    });

    test('kejadian menanam disimpan sebagai catatan riwayat', () {
      final result = detector.detect('Saya nanam timun hari ini');

      expect(result.mode, ActivityMode.history);
      expect(result.requiresClarification, isFalse);
    });

    test('pembayaran upah disimpan sebagai catatan riwayat', () {
      final result = detector.detect('Saya bayar upah karyawan');

      expect(result.mode, ActivityMode.history);
      expect(result.requiresClarification, isFalse);
    });

    test('aktivitas tanpa petunjuk mode meminta klarifikasi', () {
      final result = detector.detect('Belanja ke pasar');

      expect(result.mode, ActivityMode.history);
      expect(result.requiresClarification, isTrue);
    });
  });

  test('mode memakai ActivityKind yang sudah persisten', () {
    expect(ActivityMode.timeTracking.activityKind, ActivityKind.timer);
    expect(ActivityMode.history.activityKind, ActivityKind.note);
    expect(ActivityKind.timer.activityMode, ActivityMode.timeTracking);
    expect(ActivityKind.note.activityMode, ActivityMode.history);
  });
}
