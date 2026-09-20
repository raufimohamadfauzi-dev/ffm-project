import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/di/injection.dart';
import '../../domain/entities/reminder_entity.dart';
import '../../data/services/reminder_tts_service.dart';

/// Dialog interaktif saat Alarm berdering dengan Pengingat Bersuara Cerdas (Talking Voice Assistant).
/// Menggabungkan animasi dering, siklus nada dering bergiliran dengan suara TTS, dan batas Auto-Silence 3 menit.
class AlarmRingingDialog extends StatefulWidget {
  const AlarmRingingDialog({
    super.key,
    required this.title,
    this.note,
    this.destinationRoute,
    this.mode = ReminderMode.alarm,
    this.snoozeCount = 0,
    this.autoSilenceDuration = const Duration(minutes: 3),
    this.maxSnoozeCount = 3,
    required this.onComplete,
    required this.onSnooze,
    this.onNavigateDestination,
  });

  final String title;
  final String? note;
  final String? destinationRoute;
  final ReminderMode mode;
  final int snoozeCount;
  final Duration autoSilenceDuration;
  final int maxSnoozeCount;
  final VoidCallback onComplete;
  final VoidCallback onSnooze;
  final void Function(String route)? onNavigateDestination;

  static Future<void> show(
    BuildContext context, {
    required String title,
    String? note,
    String? destinationRoute,
    ReminderMode mode = ReminderMode.alarm,
    int snoozeCount = 0,
    Duration autoSilenceDuration = const Duration(minutes: 3),
    int maxSnoozeCount = 3,
    required VoidCallback onComplete,
    required VoidCallback onSnooze,
    void Function(String route)? onNavigateDestination,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlarmRingingDialog(
        title: title,
        note: note,
        destinationRoute: destinationRoute,
        mode: mode,
        snoozeCount: snoozeCount,
        autoSilenceDuration: autoSilenceDuration,
        maxSnoozeCount: maxSnoozeCount,
        onComplete: onComplete,
        onSnooze: onSnooze,
        onNavigateDestination: onNavigateDestination,
      ),
    );
  }

  @override
  State<AlarmRingingDialog> createState() => _AlarmRingingDialogState();
}

class _AlarmRingingDialogState extends State<AlarmRingingDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final ReminderTtsService _ttsService;
  Timer? _autoSilenceTimer;
  Timer? _cycleTimer;
  bool _isSpeaking = false;
  bool _isRinging = true;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _ttsService = getIt<ReminderTtsService>();
    _ttsService.setOnCompletionHandler(_handleSpeechCompleted);

    // Auto-Silence Timer (Batas waktu 3 menit)
    _autoSilenceTimer = Timer(widget.autoSilenceDuration, _handleAutoSilence);

    _startAlertCycle();
  }

  void _startAlertCycle() {
    if (!mounted) return;
    setState(() {
      _isRinging = true;
      _isSpeaking = false;
    });

    // Simulasi dering/haptic ringtone awal
    HapticFeedback.heavyImpact();

    final ringDuration = widget.mode == ReminderMode.alarm
        ? const Duration(seconds: 3)
        : const Duration(milliseconds: 1200);

    _cycleTimer?.cancel();
    _cycleTimer = Timer(ringDuration, () {
      if (!mounted) return;
      setState(() => _isRinging = false);
      _startSpeech();
    });
  }

  Future<void> _startSpeech() async {
    if (!mounted) return;
    setState(() => _isSpeaking = true);
    await _ttsService.speakReminder(
      title: widget.title,
      note: widget.note,
      isUrgentAlarm: widget.mode == ReminderMode.alarm,
    );
  }

  void _handleSpeechCompleted() {
    if (!mounted) return;
    setState(() => _isSpeaking = false);

    // Khusus mode alarm, dering dan suara berulang secara berselang-seling
    if (widget.mode == ReminderMode.alarm) {
      _cycleTimer?.cancel();
      _cycleTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) _startAlertCycle();
      });
    }
  }

  Future<void> _handleAutoSilence() async {
    if (!mounted) return;
    await _stopSpeech();
    if (!mounted) return;
    Navigator.of(context).pop();

    if (widget.snoozeCount < widget.maxSnoozeCount) {
      // Auto-snooze jika masih di bawah 3 kali
      widget.onSnooze();
    } else {
      // Sudah mencapai batas tunda 3x, senyap total
      widget.onComplete();
    }
  }

  Future<void> _stopSpeech() async {
    _autoSilenceTimer?.cancel();
    _cycleTimer?.cancel();
    _ttsService.setOnCompletionHandler(null);
    await _ttsService.stop();
    if (mounted) {
      setState(() {
        _isSpeaking = false;
        _isRinging = false;
      });
    }
  }

  @override
  void dispose() {
    _autoSilenceTimer?.cancel();
    _cycleTimer?.cancel();
    _animController.dispose();
    _ttsService.setOnCompletionHandler(null);
    _ttsService.stop();
    super.dispose();
  }

  static String _friendlyRouteName(String? route) {
    if (route == null || route.trim().isEmpty) return 'Halaman Pengingat';
    return switch (route.trim().toLowerCase()) {
      'reminders' || 'reminder' => 'Halaman Pengingat',
      'transactions' => 'Daftar Transaksi',
      'liabilities' => 'Hutang & Piutang',
      'budget' => 'Anggaran',
      'goals' => 'Target Keuangan',
      'assets' => 'Daftar Aset',
      'activity' => 'Catatan Harian',
      'monthlyreport' => 'Laporan Bulanan',
      'familyprofile' => 'Profil Keluarga',
      'summary' => 'Ringkasan Finansial',
      _ => route.trim(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _stopSpeech();
      },
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.12).animate(
                CurvedAnimation(
                  parent: _animController,
                  curve: Curves.easeInOut,
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withAlpha(120),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.alarm_on_rounded,
                  size: 48,
                  color: colorScheme.error,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Alarm Berdering',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colorScheme.error,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (widget.note != null && widget.note!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withAlpha(140),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.note!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            if (widget.snoozeCount > 0) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withAlpha(140),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Tunda ke-${widget.snoozeCount} (maks ${widget.maxSnoozeCount})',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_isRinging)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_active_rounded,
                    size: 16,
                    color: colorScheme.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.mode == ReminderMode.alarm
                        ? 'Membunyikan nada dering...'
                        : 'Membunyikan notifikasi...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            else if (_isSpeaking)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.record_voice_over_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Asisten sedang berbicara...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            else
              TextButton.icon(
                onPressed: _startSpeech,
                icon: const Icon(Icons.volume_up_rounded, size: 16),
                label: const Text('Ulangi suara asisten'),
              ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowButtonSpacing: 8,
        actions: [
          FilledButton.tonalIcon(
            onPressed: () {
              _stopSpeech();
              Navigator.of(context).pop();
              final targetRoute =
                  (widget.destinationRoute != null &&
                      widget.destinationRoute!.trim().isNotEmpty)
                  ? widget.destinationRoute!
                  : 'reminders';
              widget.onNavigateDestination?.call(targetRoute);
            },
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text('Buka ${_friendlyRouteName(widget.destinationRoute)}'),
          ),
          if (widget.snoozeCount < widget.maxSnoozeCount)
            OutlinedButton.icon(
              onPressed: () {
                _stopSpeech();
                Navigator.of(context).pop();
                widget.onSnooze();
              },
              icon: const Icon(Icons.snooze_rounded),
              label: const Text('Tunda 10 Menit'),
            ),
          FilledButton.icon(
            onPressed: () {
              _stopSpeech();
              Navigator.of(context).pop();
              widget.onComplete();
            },
            icon: const Icon(Icons.check_rounded),
            label: const Text('Selesai'),
          ),
        ],
      ),
    );
  }
}
