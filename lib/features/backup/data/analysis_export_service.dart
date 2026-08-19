import 'dart:convert';

import '../../transaction/domain/entities/transaction_entity.dart';

class AnalysisExportBundle {
  const AnalysisExportBundle({
    required this.periodLabel,
    required this.json,
    required this.csv,
    required this.html,
    required this.prompt,
  });

  final String periodLabel;
  final String json;
  final String csv;
  final String html;
  final String prompt;
}

class AnalysisExportService {
  const AnalysisExportService();

  AnalysisExportBundle build({
    required Iterable<TransactionWithItems> records,
    DateTime? from,
    DateTime? to,
    required String typeFilter,
    required String categoryFilter,
    required Map<String, String> categoryLabels,
    required Map<String, String> merchantLabels,
    required Map<String, String> merchantDetails,
    required Map<String, String> tagLabels,
    required Map<String, List<String>> tagsByTransaction,
    required bool includeNotes,
    required bool includeItems,
    required bool includeMerchantDetails,
  }) {
    final filtered = records.where((entry) {
      final transaction = entry.transaction;
      final date = transaction.date;
      if (from != null && date.isBefore(from)) return false;
      if (to != null && date.isAfter(to.add(const Duration(days: 1))))
        return false;
      if (typeFilter != 'all' && transaction.type != typeFilter) return false;
      if (categoryFilter != 'all' && transaction.categoryId != categoryFilter)
        return false;
      return true;
    }).toList();
    final rows = filtered
        .map(
          (entry) => _row(
            entry,
            categoryLabels: categoryLabels,
            merchantLabels: merchantLabels,
            merchantDetails: merchantDetails,
            tagLabels: tagLabels,
            tagsByTransaction: tagsByTransaction,
            includeNotes: includeNotes,
            includeItems: includeItems,
            includeMerchantDetails: includeMerchantDetails,
          ),
        )
        .toList();
    final periodLabel = _periodLabel(from, to);
    final json = const JsonEncoder.withIndent('  ').convert({
      'formatVersion': 'ffm-analysis-v1',
      'period': periodLabel,
      'filters': {'type': typeFilter, 'categoryId': categoryFilter},
      'count': rows.length,
      'records': rows,
    });
    final csv = _toCsv(rows);
    final html = _toHtml(rows, periodLabel);
    final prompt = _prompt(
      periodLabel,
      rows.length,
      includeNotes,
      includeItems,
    );
    return AnalysisExportBundle(
      periodLabel: periodLabel,
      json: json,
      csv: csv,
      html: html,
      prompt: prompt,
    );
  }

  Map<String, Object?> _row(
    TransactionWithItems entry, {
    required Map<String, String> categoryLabels,
    required Map<String, String> merchantLabels,
    required Map<String, String> merchantDetails,
    required Map<String, String> tagLabels,
    required Map<String, List<String>> tagsByTransaction,
    required bool includeNotes,
    required bool includeItems,
    required bool includeMerchantDetails,
  }) {
    final transaction = entry.transaction;
    final merchantId = transaction.merchantId;
    final linkedTags = tagsByTransaction[transaction.id] ?? const <String>[];
    return {
      'id': transaction.id,
      'tanggal': transaction.date.toIso8601String(),
      'waktuInput': transaction.recordedAt.toIso8601String(),
      'jenis': transaction.type == 'income' ? 'pemasukan' : 'pengeluaran',
      'nominal': transaction.amount,
      'kategori':
          categoryLabels[transaction.categoryId] ??
          transaction.categoryId ??
          'Belum diatur',
      'rekening': transaction.accountId,
      'toko': merchantLabels[merchantId] ?? merchantId,
      if (includeMerchantDetails && merchantId != null)
        'detailToko': merchantDetails[merchantId],
      'dipakaiOlehAtauSumber': transaction.partyName,
      'lokasi': transaction.location,
      if (includeNotes) 'catatan': transaction.note,
      if (linkedTags.isNotEmpty)
        'tag': linkedTags.map((id) => tagLabels[id] ?? id).toList(),
      if (includeItems)
        'rincian': entry.items
            .map(
              (item) => {
                'nama': item.itemName,
                'jumlah': item.qty,
                'satuan': item.unit,
                'harga': item.price,
                'total': item.amount,
              },
            )
            .toList(),
    };
  }

  String _toCsv(List<Map<String, Object?>> rows) {
    const headers = [
      'tanggal',
      'jenis',
      'nominal',
      'kategori',
      'rekening',
      'toko',
      'dipakaiOlehAtauSumber',
      'lokasi',
      'catatan',
    ];
    final lines = <String>[_csvLine(headers)];
    for (final row in rows) {
      lines.add(_csvLine(headers.map((key) => row[key]).toList()));
    }
    return lines.join('\n');
  }

  String _csvLine(Iterable<Object?> values) => values
      .map((value) {
        final text = value?.toString() ?? '';
        return '"${text.replaceAll('"', '""')}"';
      })
      .join(',');

  String _toHtml(List<Map<String, Object?>> rows, String periodLabel) {
    final body = rows
        .map(
          (row) =>
              '<tr><td>${_escape(row['tanggal'])}</td><td>${_escape(row['jenis'])}</td><td>${_escape(row['nominal'])}</td><td>${_escape(row['kategori'])}</td><td>${_escape(row['toko'])}</td></tr>',
        )
        .join();
    return '<!doctype html><html lang="id"><meta charset="utf-8"><title>Analisa FFM</title><body><h1>Analisa FFM</h1><p>Periode: ${_escape(periodLabel)}</p><table border="1" cellspacing="0" cellpadding="6"><thead><tr><th>Tanggal</th><th>Jenis</th><th>Nominal</th><th>Kategori</th><th>Toko</th></tr></thead><tbody>$body</tbody></table></body></html>';
  }

  String _escape(Object? value) =>
      const HtmlEscape().convert(value?.toString() ?? '');

  String _periodLabel(DateTime? from, DateTime? to) {
    if (from == null && to == null) return 'Semua periode';
    final start = from == null
        ? 'awal'
        : '${from.day}/${from.month}/${from.year}';
    final end = to == null ? 'sekarang' : '${to.day}/${to.month}/${to.year}';
    return '$start sampai $end';
  }

  String _prompt(
    String periodLabel,
    int count,
    bool includeNotes,
    bool includeItems,
  ) =>
      '''Kamu adalah pendamping analisa keuangan keluarga. Analisa data FFM berikut secara hati-hati dan jangan mengarang angka.

Periode: $periodLabel
Jumlah catatan: $count
Catatan disertakan: ${includeNotes ? 'ya' : 'tidak'}
Rincian item disertakan: ${includeItems ? 'ya' : 'tidak'}

Tolong jelaskan pola pemasukan, pengeluaran terbesar, kategori yang perlu diperhatikan, perubahan dibanding periode sebelumnya jika datanya tersedia, dan 3 saran praktis yang realistis. Bedakan fakta dari dugaan, serta ingat bahwa transfer antar rekening bukan pemasukan atau pengeluaran.''';
}
