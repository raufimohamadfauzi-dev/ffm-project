import 'package:flutter/material.dart';

import '../../../../shared/ffm_date_period.dart';

class ActivityFilterFilterState {
  const ActivityFilterFilterState({
    this.categoryId,
    this.dayFilter,
    this.startDateFilter,
    this.endDateFilter,
    this.modeFilter = 'Semua mode',
    this.includeArchived = false,
  });

  final String? categoryId;
  final DateTime? dayFilter;
  final DateTime? startDateFilter;
  final DateTime? endDateFilter;
  final String modeFilter;
  final bool includeArchived;

  int get activeFiltersCount {
    var count = 0;
    if (categoryId != null) count++;
    if (dayFilter != null || startDateFilter != null || endDateFilter != null) {
      count++;
    }
    if (modeFilter != 'Semua mode') count++;
    if (includeArchived) count++;
    return count;
  }

  bool get hasActiveFilters => activeFiltersCount > 0;
}

class ActivityFilterSheet extends StatefulWidget {
  const ActivityFilterSheet({
    super.key,
    required this.initialState,
    required this.categories,
    required this.categoryIds,
  });

  final ActivityFilterFilterState initialState;
  final List<String> categories;
  final Map<String, String> categoryIds;

  @override
  State<ActivityFilterSheet> createState() => _ActivityFilterSheetState();
}

class _ActivityFilterSheetState extends State<ActivityFilterSheet> {
  late String? _selectedCategoryId;
  late DateTime? _dayFilter;
  late DateTime? _startDateFilter;
  late DateTime? _endDateFilter;
  late String _modeFilter;
  late bool _includeArchived;

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.initialState.categoryId;
    _dayFilter = widget.initialState.dayFilter;
    _startDateFilter = widget.initialState.startDateFilter;
    _endDateFilter = widget.initialState.endDateFilter;
    _modeFilter = widget.initialState.modeFilter;
    _includeArchived = widget.initialState.includeArchived;
  }

  void _reset() {
    setState(() {
      _selectedCategoryId = null;
      _dayFilter = null;
      _startDateFilter = null;
      _endDateFilter = null;
      _modeFilter = 'Semua mode';
      _includeArchived = false;
    });
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _dayFilter ?? DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dayFilter = picked;
      _startDateFilter = null;
      _endDateFilter = null;
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _startDateFilter != null && _endDateFilter != null
          ? DateTimeRange(start: _startDateFilter!, end: _endDateFilter!)
          : null,
    );
    if (range == null || !mounted) return;
    setState(() {
      _dayFilter = null;
      _startDateFilter = range.start;
      _endDateFilter = range.end;
    });
  }

  void _applyPeriodPreset(FfmDatePeriodPreset preset) {
    final period = FfmDatePeriod.fromPreset(preset);
    setState(() {
      _dayFilter = null;
      _startDateFilter = period.start;
      _endDateFilter = period.endInclusive;
    });
  }

  String _dateLabel() {
    if (_dayFilter != null) {
      return '${_dayFilter!.day}/${_dayFilter!.month}/${_dayFilter!.year}';
    }
    if (_startDateFilter != null && _endDateFilter != null) {
      return '${_startDateFilter!.day}/${_startDateFilter!.month} - ${_endDateFilter!.day}/${_endDateFilter!.month}/${_endDateFilter!.year}';
    }
    return 'Semua waktu';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Filter Aktivitas & Catatan',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _reset,
                child: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Kategori', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ChoiceChip(
                label: const Text('Semua'),
                selected: _selectedCategoryId == null,
                onSelected: (_) => setState(() => _selectedCategoryId = null),
              ),
              ...widget.categories.map((name) {
                final id = widget.categoryIds[name];
                return ChoiceChip(
                  label: Text(name),
                  selected: _selectedCategoryId == id,
                  onSelected: (selected) {
                    setState(() => _selectedCategoryId = selected ? id : null);
                  },
                );
              }),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Periode Waktu', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDay,
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(_dateLabel(), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<FfmDatePeriodPreset>(
                tooltip: 'Preset periode',
                onSelected: _applyPeriodPreset,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: FfmDatePeriodPreset.allTime, child: Text('Semua periode')),
                  PopupMenuItem(value: FfmDatePeriodPreset.thisMonth, child: Text('Bulan ini')),
                  PopupMenuItem(value: FfmDatePeriodPreset.lastMonth, child: Text('Bulan lalu')),
                  PopupMenuItem(value: FfmDatePeriodPreset.last3Months, child: Text('3 bulan terakhir')),
                  PopupMenuItem(value: FfmDatePeriodPreset.thisYear, child: Text('Tahun ini')),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outline),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.tune, size: 18),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.date_range),
                tooltip: 'Rentang kustom',
                onPressed: _pickDateRange,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tipe Sesi', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: _modeFilter,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Semua mode', child: Text('Semua')),
                        DropdownMenuItem(value: 'Timer', child: Text('Timer')),
                        DropdownMenuItem(value: 'Catatan', child: Text('Catatan')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _modeFilter = val);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tampilkan Arsip', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    FilterChip(
                      label: const Text('Arsip'),
                      selected: _includeArchived,
                      onSelected: (val) => setState(() => _includeArchived = val),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  ActivityFilterFilterState(
                    categoryId: _selectedCategoryId,
                    dayFilter: _dayFilter,
                    startDateFilter: _startDateFilter,
                    endDateFilter: _endDateFilter,
                    modeFilter: _modeFilter,
                    includeArchived: _includeArchived,
                  ),
                );
              },
              child: const Text('Terapkan Filter'),
            ),
          ),
        ],
      ),
    );
  }
}
