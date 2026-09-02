import 'package:flutter/material.dart';

class TransactionFilter {
  const TransactionFilter({
    required this.typeFilter,
    required this.currentMonthOnly,
  });

  final String typeFilter;
  final bool currentMonthOnly;
}

class TransactionFilterSheet extends StatefulWidget {
  const TransactionFilterSheet({
    super.key,
    required this.typeFilter,
    required this.currentMonthOnly,
  });

  final String typeFilter;
  final bool currentMonthOnly;

  @override
  State<TransactionFilterSheet> createState() =>
      _TransactionFilterSheetState();
}

class _TransactionFilterSheetState extends State<TransactionFilterSheet> {
  late String _typeFilter;
  late bool _currentMonthOnly;

  @override
  void initState() {
    super.initState();
    _typeFilter = widget.typeFilter;
    _currentMonthOnly = widget.currentMonthOnly;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Saring transaksi',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Text('Jenis', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Semua', label: Text('Semua')),
              ButtonSegment(value: 'Pemasukan', label: Text('Pemasukan')),
              ButtonSegment(value: 'Pengeluaran', label: Text('Pengeluaran')),
              ButtonSegment(value: 'Transfer', label: Text('Transfer')),
            ],
            selected: {_typeFilter},
            onSelectionChanged: (value) {
              setState(() => _typeFilter = value.first);
            },
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bulan berjalan saja'),
            value: _currentMonthOnly,
            onChanged: (value) => setState(() => _currentMonthOnly = value),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(
                    context,
                    const TransactionFilter(
                      typeFilter: 'Semua',
                      currentMonthOnly: false,
                    ),
                  ),
                  child: const Text('Reset'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    TransactionFilter(
                      typeFilter: _typeFilter,
                      currentMonthOnly: _currentMonthOnly,
                    ),
                  ),
                  child: const Text('Terapkan'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
