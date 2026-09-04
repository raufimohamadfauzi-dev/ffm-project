import 'package:flutter/material.dart';

import 'package:ffm_manager/core/database/app_database.dart';
import 'package:ffm_manager/core/di/injection.dart';
import 'package:ffm_manager/features/assistant/data/bill_reminder_repository.dart';
import 'package:ffm_manager/features/assistant/data/calendar_bridge.dart';

/// Halaman pengaturan integrasi kalender dan sinkronisasi smartwatch.
class CalendarSettingsPage extends StatefulWidget {
  const CalendarSettingsPage({super.key});

  @override
  State<CalendarSettingsPage> createState() => _CalendarSettingsPageState();
}

class _CalendarSettingsPageState extends State<CalendarSettingsPage> {
  final _calendarBridge = CalendarBridge();
  late final _billReminderRepository = BillReminderRepository(
    getIt<AppDatabase>(),
    _calendarBridge,
  );

  bool _isLoading = true;
  bool _isCalendarAvailable = false;
  int? _defaultCalendarId;
  bool _autoSyncEnabled = true;
  String _syncStatus = 'Checking...';
  int _unsyncedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCalendarStatus();
  }

  Future<void> _loadCalendarStatus() async {
    setState(() => _isLoading = true);

    try {
      final available = await _calendarBridge.isCalendarAvailable();
      final calendarId = await _calendarBridge.getDefaultCalendarId();
      
      // Check sync status
      final reminders = await _billReminderRepository.getBillReminders('local-household');
      final unsynced = reminders.where((r) => !r.isSyncedToCalendar).length;

      setState(() {
        _isCalendarAvailable = available;
        _defaultCalendarId = calendarId;
        _unsyncedCount = unsynced;
        _syncStatus = available 
            ? 'Terhubung ke Google Calendar ✅' 
            : 'Tidak terhubung ❌';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isCalendarAvailable = false;
        _syncStatus = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _retrySync() async {
    setState(() => _isLoading = true);

    try {
      await _billReminderRepository.retrySyncForUnsynced('local-household');
      await _loadCalendarStatus();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sinkronisasi ulang berhasil')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal sinkronisasi: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan Kalender & Smartwatch'),
        backgroundColor: colorScheme.surface,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusCard(colorScheme),
                  const SizedBox(height: 24),
                  _buildSettingsCard(colorScheme),
                  const SizedBox(height: 24),
                  _buildSyncActionsCard(colorScheme),
                  const SizedBox(height: 24),
                  _buildInfoCard(colorScheme),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard(ColorScheme colorScheme) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isCalendarAvailable ? Icons.check_circle : Icons.error,
                  color: _isCalendarAvailable 
                      ? colorScheme.primary 
                      : colorScheme.error,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status Sinkronisasi',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _syncStatus,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_defaultCalendarId != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
              Text(
                'Kalender Terhubung: Kalender Utama (ID: $_defaultCalendarId)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard(ColorScheme colorScheme) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pengaturan Sinkronisasi',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Otomatis sinkronkan pengingat baru'),
              subtitle: const Text(
                'Pengingat tagihan otomatis ditambahkan ke kalender',
              ),
              value: _autoSyncEnabled,
              onChanged: (value) {
                setState(() => _autoSyncEnabled = value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncActionsCard(ColorScheme colorScheme) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aksi Sinkronisasi',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(
                Icons.sync,
                color: colorScheme.primary,
              ),
              title: const Text('Sinkronisasi Ulang'),
              subtitle: Text(
                '$_unsyncedCount pengingat belum disinkronkan',
              ),
              trailing: ElevatedButton(
                onPressed: _unsyncedCount > 0 ? _retrySync : null,
                child: const Text('Mulai'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(ColorScheme colorScheme) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Informasi Sinkronisasi',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Sinkronisasi kalender memungkinkan pengingat tagihan FFM muncul di Google Calendar dan notifikasi tembus ke smartwatch (Galaxy Watch, Garmin, Mi Band, Apple Watch).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Notifikasi akan muncul 15 menit, 1 jam, dan 1 hari sebelum jatuh tempo tagihan.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}