import 'dart:convert';

import 'receipt_import_models.dart';

class ReceiptImportException implements Exception {
  const ReceiptImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReceiptBatchEntry {
  const ReceiptBatchEntry({
    required this.type,
    required this.date,
    required this.amount,
    required this.items,
    this.time,
    this.merchant,
    this.categoryId,
    this.accountId,
    this.budgetId,
    this.budgetName,
    this.partyName,
    this.note,
    this.fromAccountId,
    this.toAccountId,
    this.adminFee,
  });

  final String type;
  final DateTime? date;
  final String? time;
  final int? amount;
  final String? merchant;
  final String? categoryId;
  final String? accountId;
  final String? budgetId;
  final String? budgetName;
  final String? partyName;
  final String? note;
  final String? fromAccountId;
  final String? toAccountId;
  final int? adminFee;
  final List<ReceiptOcrItem> items;
}

class ReceiptBatchImport {
  const ReceiptBatchImport({
    required this.entries,
    required this.warnings,
    this.isBankStatement = false,
    this.statementAccountId,
    this.statementAccountName,
    this.openingBalance,
    this.closingBalance,
    this.periodStart,
    this.periodEnd,
  });

  final List<ReceiptBatchEntry> entries;
  final List<String> warnings;
  final bool isBankStatement;
  final String? statementAccountId;
  final String? statementAccountName;
  final int? openingBalance;
  final int? closingBalance;
  final DateTime? periodStart;
  final DateTime? periodEnd;
}

class ReceiptImportService {
  const ReceiptImportService._();

  static const format = 'ffm-receipt-draft-v1';
  static const batchFormat = 'ffm-transaction-batch-v1';
  static const bankStatementFormat = 'ffm-bank-statement-v1';

  static ReceiptOcrResult parseJson(String rawJson, {String? imagePath}) {
    final decoded = _decodeJson(rawJson);
    if (decoded is! Map) {
      throw const ReceiptImportException('Format JSON harus berupa objek.');
    }
    final root = Map<String, dynamic>.from(decoded);
    final rawReceipt = root['receipt'];
    final data = rawReceipt is Map
        ? Map<String, dynamic>.from(rawReceipt)
        : root;
    final declaredFormat = root['format']?.toString();
    if (declaredFormat != null &&
        declaredFormat.isNotEmpty &&
        declaredFormat != format) {
      throw ReceiptImportException(
        'Format $declaredFormat belum didukung. Pakai $format.',
      );
    }

    final warnings = <String>[];
    final itemValue = data['items'] ?? data['lines'];
    final items = <ReceiptOcrItem>[];
    if (itemValue is List) {
      for (var index = 0; index < itemValue.length; index++) {
        final raw = itemValue[index];
        if (raw is! Map) {
          warnings.add(
            'Baris item ke-${index + 1} dilewati karena bukan objek.',
          );
          continue;
        }
        final item = _parseItem(
          Map<String, dynamic>.from(raw),
          index,
          warnings,
        );
        if (item != null) items.add(item);
      }
    } else if (itemValue != null) {
      warnings.add('Field items harus berupa array.');
    }

    final result = ReceiptOcrResult(
      merchant: _text(data['merchant'] ?? data['toko']),
      total: _money(data['total'] ?? data['grand_total']),
      date: _date(data['date'] ?? data['tanggal']),
      time: _text(data['time'] ?? data['waktu']),
      paidAmount: _money(data['paid_amount'] ?? data['bayar']),
      changeAmount: _money(data['change_amount'] ?? data['kembalian']),
      receiptNumber: _text(data['receipt_number'] ?? data['nomor_nota']),
      rawText: _text(data['raw_text'] ?? data['teks_asli']) ?? '',
      categoryId: _text(data['category_id']),
      imagePath: imagePath ?? _text(data['image_path']),
      items: items,
      warnings: warnings,
    );
    if (result.total == null && result.items.isEmpty) {
      throw const ReceiptImportException(
        'JSON belum memiliki total atau item nota yang bisa diimpor.',
      );
    }
    return result;
  }

  static ReceiptBatchImport parseBatchJson(String rawJson) {
    final decoded = _decodeJson(rawJson);
    if (decoded is! Map) {
      throw const ReceiptImportException('JSON batch harus berupa objek.');
    }
    final root = Map<String, dynamic>.from(decoded);
    final declaredFormat = root['format']?.toString();
    if (declaredFormat == bankStatementFormat ||
        root['mutations'] is List ||
        root['statement'] is Map) {
      return _parseBankStatement(root);
    }
    if (declaredFormat != null &&
        declaredFormat.isNotEmpty &&
        declaredFormat != batchFormat &&
        declaredFormat != format &&
        declaredFormat != bankStatementFormat) {
      throw ReceiptImportException(
        'Format $declaredFormat belum didukung. Pakai $batchFormat.',
      );
    }
    final rawTransactions = root['transactions'];
    if (rawTransactions is! List) {
      final receipt = parseJson(rawJson);
      return ReceiptBatchImport(
        entries: [
          ReceiptBatchEntry(
            type: 'expense',
            date: receipt.date,
            time: receipt.time,
            amount: receipt.total ?? receipt.itemsTotal,
            merchant: receipt.merchant,
            categoryId: receipt.categoryId,
            budgetName: _text(
              (root['budget_name'] ?? root['anggaran_nama'])?.toString(),
            ),
            note: receipt.rawText.trim().isEmpty ? null : receipt.rawText,
            items: receipt.items,
          ),
        ],
        warnings: receipt.validationWarnings,
      );
    }

    final warnings = <String>[];
    final entries = <ReceiptBatchEntry>[];
    for (var index = 0; index < rawTransactions.length; index++) {
      final raw = rawTransactions[index];
      if (raw is! Map) {
        warnings.add('Transaksi ke-${index + 1} dilewati karena bukan objek.');
        continue;
      }
      final data = Map<String, dynamic>.from(raw);
      final typeValue = _transactionType(data);
      if (typeValue != 'income' &&
          typeValue != 'expense' &&
          typeValue != 'transfer') {
        warnings.add(
          'Transaksi ke-${index + 1} harus memiliki type income atau expense.',
        );
        continue;
      }
      final items = <ReceiptOcrItem>[];
      final rawItems = data['items'] ?? data['lines'];
      if (rawItems is List) {
        for (var itemIndex = 0; itemIndex < rawItems.length; itemIndex++) {
          final item = rawItems[itemIndex];
          if (item is! Map) {
            warnings.add(
              'Transaksi ke-${index + 1}, item ke-${itemIndex + 1} dilewati karena bukan objek.',
            );
            continue;
          }
          final parsed = _parseItem(
            Map<String, dynamic>.from(item),
            itemIndex,
            warnings,
          );
          if (parsed != null) items.add(parsed);
        }
      } else if (data['name'] != null || data['nama'] != null) {
        final parsed = _parseItem(data, 0, warnings);
        if (parsed != null) items.add(parsed);
      }
      final amount =
          _money(data['amount'] ?? data['total']) ??
          (items.isEmpty
              ? null
              : items.fold<int>(0, (sum, item) => sum + item.calculatedTotal));
      if (amount == null || amount <= 0) {
        warnings.add('Transaksi ke-${index + 1} belum memiliki nominal valid.');
      }
      entries.add(
        ReceiptBatchEntry(
          type: typeValue!,
          date: _date(data['date'] ?? data['tanggal']),
          time: _text(data['time'] ?? data['waktu']),
          amount: amount,
          merchant: _text(data['merchant'] ?? data['toko']),
          categoryId: _text(data['category_id'] ?? data['kategori_id']),
          accountId: _text(data['account_id'] ?? data['rekening_id']),
          budgetId: _text(data['budget_id'] ?? data['anggaran_id']),
          budgetName: _text(
            data['budget_name'] ??
                data['anggaran_nama'] ??
                data['budget'] ??
                data['anggaran'],
          ),
          partyName: _text(
            data['party_name'] ?? data['sumber'] ?? data['dipakai_oleh'],
          ),
          note: _text(data['note'] ?? data['catatan']),
          fromAccountId: _text(
            data['from_account_id'] ?? data['rekening_asal'],
          ),
          toAccountId: _text(data['to_account_id'] ?? data['rekening_tujuan']),
          adminFee: _money(data['admin_fee'] ?? data['biaya_admin']),
          items: items,
        ),
      );
    }
    if (entries.isEmpty) {
      throw const ReceiptImportException(
        'Belum ada transaksi batch yang bisa diimpor.',
      );
    }
    return ReceiptBatchImport(entries: entries, warnings: warnings);
  }

  static ReceiptBatchImport _parseBankStatement(Map<String, dynamic> root) {
    final statement = root['statement'] is Map
        ? Map<String, dynamic>.from(root['statement'] as Map)
        : root;
    final rawMutations = root['mutations'] ?? root['transactions'];
    if (rawMutations is! List) {
      throw const ReceiptImportException(
        'JSON mutasi harus memiliki array mutations atau transactions.',
      );
    }
    final warnings = <String>[];
    final entries = <ReceiptBatchEntry>[];
    for (var index = 0; index < rawMutations.length; index++) {
      final raw = rawMutations[index];
      if (raw is! Map) {
        warnings.add('Mutasi ke-${index + 1} dilewati karena bukan objek.');
        continue;
      }
      final data = Map<String, dynamic>.from(raw);
      final type = _transactionType(data);
      if (type == null) {
        warnings.add(
          'Mutasi ke-${index + 1} tidak punya jenis masuk, keluar, atau transfer.',
        );
        continue;
      }
      final amount = _money(
        data['amount'] ?? data['nominal'] ?? data['debit'] ?? data['credit'],
      );
      if (amount == null || amount <= 0) {
        warnings.add('Mutasi ke-${index + 1} belum memiliki nominal valid.');
      }
      final mutationDate = _date(
        data['date'] ?? data['tanggal'] ?? data['transaction_date'],
      );
      if (mutationDate == null) {
        warnings.add('Mutasi ke-${index + 1} belum memiliki tanggal valid.');
      }
      entries.add(
        ReceiptBatchEntry(
          type: type,
          date: mutationDate,
          time: _text(data['time'] ?? data['waktu']),
          amount: amount,
          merchant: _text(
            data['merchant'] ?? data['toko'] ?? data['description'],
          ),
          categoryId: _text(data['category_id'] ?? data['kategori_id']),
          budgetId: _text(data['budget_id'] ?? data['anggaran_id']),
          budgetName: _text(
            data['budget_name'] ??
                data['anggaran_nama'] ??
                data['budget'] ??
                data['anggaran'],
          ),
          accountId: _text(
            data['account_id'] ??
                data['rekening_id'] ??
                statement['account_id'] ??
                statement['rekening_id'],
          ),
          partyName: _text(
            data['party_name'] ?? data['sumber'] ?? data['dipakai_oleh'],
          ),
          note: _text(data['note'] ?? data['catatan'] ?? data['description']),
          fromAccountId: _text(
            data['from_account_id'] ?? data['rekening_asal'],
          ),
          toAccountId: _text(data['to_account_id'] ?? data['rekening_tujuan']),
          adminFee: _money(data['admin_fee'] ?? data['biaya_admin']),
          items: const [],
        ),
      );
    }
    if (entries.isEmpty) {
      throw const ReceiptImportException(
        'Belum ada mutasi rekening yang bisa diimpor.',
      );
    }
    return ReceiptBatchImport(
      entries: entries,
      warnings: warnings,
      isBankStatement: true,
      statementAccountId: _text(
        statement['account_id'] ?? statement['rekening_id'],
      ),
      statementAccountName: _text(
        statement['account_name'] ?? statement['nama_rekening'],
      ),
      openingBalance: _money(
        statement['opening_balance'] ?? statement['saldo_awal'],
      ),
      closingBalance: _money(
        statement['closing_balance'] ?? statement['saldo_akhir'],
      ),
      periodStart: _date(
        statement['period_start'] ?? statement['periode_mulai'],
      ),
      periodEnd: _date(statement['period_end'] ?? statement['periode_selesai']),
    );
  }

  static String? _transactionType(Map<String, dynamic> data) {
    final raw = _text(data['type'] ?? data['jenis'] ?? data['tipe'])
        ?.toLowerCase();
    if (raw == 'income' || raw == 'masuk' || raw == 'kredit') return 'income';
    if (raw == 'expense' || raw == 'keluar' || raw == 'debit') {
      return 'expense';
    }
    if (raw == 'transfer' || raw == 'pemindahan') return 'transfer';
    final direction = _text(data['direction'] ?? data['arah'])?.toLowerCase();
    if (direction == 'in' || direction == 'masuk' || direction == 'credit') {
      return 'income';
    }
    if (direction == 'out' || direction == 'keluar' || direction == 'debit') {
      return 'expense';
    }
    final credit = _money(data['credit'] ?? data['kredit']);
    final debit = _money(data['debit'] ?? data['debit_amount']);
    if (credit != null && credit > 0) return 'income';
    if (debit != null && debit > 0) return 'expense';
    return null;
  }

  static Map<String, dynamic> templateBankStatementMap() => {
    'format': bankStatementFormat,
    'statement': {
      'account_name': 'Nama rekening, misalnya SeaBank',
      'account_id': null,
      'period_start': null,
      'period_end': null,
      'opening_balance': null,
      'closing_balance': null,
    },
    'mutations': [
      {
        'type': 'income',
        'date': null,
        'time': null,
        'amount': 0,
        'description': 'Sumber uang masuk',
        'account_id': null,
        'category_id': null,
        'budget_id': null,
        'budget_name': null,
        'party_name': null,
        'note': null,
      },
      {
        'type': 'expense',
        'date': null,
        'time': null,
        'amount': 0,
        'description': 'Tujuan uang keluar',
        'account_id': null,
        'category_id': null,
        'budget_id': null,
        'budget_name': null,
        'party_name': null,
        'note': null,
      },
    ],
  };

  static String templateBankStatementJson() =>
      const JsonEncoder.withIndent('  ').convert(templateBankStatementMap());

  static String buildExternalLlmBankStatementPrompt() =>
      '''Kamu membantu membaca screenshot mutasi rekening untuk aplikasi Family Finance Manager (FFM).

Balas HANYA dengan JSON valid tanpa markdown atau komentar. Gunakan format persis:
${templateBankStatementJson()}

Aturan:
- Masukkan semua mutasi yang terlihat sebagai satu objek di dalam mutations.
- type hanya income untuk uang masuk, expense untuk uang keluar, atau transfer untuk perpindahan antar rekening.
- amount harus angka integer rupiah tanpa titik, koma, atau simbol Rp.
- Saldo akhir wajib masuk ke statement.closing_balance jika terlihat. Saldo akhir bukan transaksi pemasukan.
- Jangan membuat transaksi dari saldo awal atau saldo akhir.
- Jika rekening tujuan/asal transfer tidak terlihat, gunakan null dan beri catatan.
- Untuk pemasukan, budget_id dan budget_name biasanya null karena anggaran FFM hanya batas pengeluaran.
- Untuk pengeluaran, isi budget_name dengan pos/kategori anggaran yang paling cocok jika terlihat dari keterangan; jangan membuat nama pos baru.
- Jika tanggal, nominal, atau keterangan tidak terbaca, gunakan null; jangan menebak.
- Aplikasi akan menampilkan hasil sebagai draft untuk direvisi dan dikonfirmasi.''';

  static Map<String, dynamic> templateBatchMap() => {
    'format': batchFormat,
    'transactions': [
      {
        'type': 'expense',
        'date': null,
        'time': null,
        'merchant': null,
        'category_id': null,
        'account_id': null,
        'budget_id': null,
        'budget_name': null,
        'party_name': null,
        'from_account_id': null,
        'to_account_id': null,
        'admin_fee': 0,
        'note': '',
        'amount': 0,
        'items': [
          {
            'name': 'Nama barang atau rincian',
            'quantity': 1,
            'unit': 'PCS',
            'unit_price': 0,
            'amount': 0,
          },
        ],
      },
    ],
  };

  static String templateBatchJson() =>
      const JsonEncoder.withIndent('  ').convert(templateBatchMap());

  static String buildExternalLlmBatchPrompt() =>
      '''Kamu membantu menyiapkan data transaksi untuk aplikasi Family Finance Manager (FFM).

Baca informasi yang saya berikan setelah instruksi ini. Informasi dapat berupa foto nota, screenshot mutasi rekening, teks, atau beberapa transaksi sekaligus.

Balas HANYA dengan JSON valid tanpa markdown atau komentar. Gunakan format persis:
${templateBatchJson()}

Aturan:
- `transactions` berisi satu objek untuk setiap transaksi. Satu nota berarti satu transaksi dengan rincian barang di `items`.
- `type` hanya boleh `income`, `expense`, atau `transfer`.
- `amount`, `unit_price`, dan `items.amount` harus berupa angka integer rupiah tanpa titik, koma, atau simbol Rp.
- Satu transaksi boleh memiliki banyak item pada `items`.
- Untuk `transfer`, isi `from_account_id` dan `to_account_id` hanya jika ID rekening diberikan; jika tidak, gunakan null agar dipilih di FFM.
- Untuk pengeluaran, isi `budget_name` dengan nama pos anggaran yang paling cocok berdasarkan keterangan. Jika tidak yakin, gunakan null; jangan menebak.
- `budget_id` hanya diisi jika ID pos diberikan secara eksplisit oleh aplikasi; jangan membuat ID sendiri.
- Untuk pemasukan, `budget_id` dan `budget_name` biasanya null karena anggaran adalah batas pengeluaran.
- Jangan menggabungkan beberapa transaksi berbeda menjadi satu objek.
- Jika gambar atau teks tidak terbaca, gunakan null; jangan menebak.
- FFM akan menampilkan semua hasil sebagai draft yang wajib diperiksa dan dikonfirmasi.''';

  static Map<String, dynamic> toMap(ReceiptOcrResult result) => {
    'format': format,
    'receipt': {
      'merchant': result.merchant,
      'receipt_number': result.receiptNumber,
      'date': result.date?.toIso8601String(),
      'time': result.time,
      'total': result.total,
      'paid_amount': result.paidAmount,
      'change_amount': result.changeAmount,
      'raw_text': result.rawText,
      'items': result.items
          .map(
            (item) => {
              'name': item.name,
              'quantity': item.quantity,
              'unit': item.unit,
              'unit_price': item.price,
              'amount': item.calculatedTotal,
            },
          )
          .toList(),
    },
  };

  static String toJson(ReceiptOcrResult result) =>
      const JsonEncoder.withIndent('  ').convert(toMap(result));

  static Map<String, dynamic> templateMap() => {
    'format': format,
    'receipt': {
      'merchant': null,
      'receipt_number': null,
      'date': null,
      'time': null,
      'total': 0,
      'paid_amount': null,
      'change_amount': null,
      'raw_text': '',
      'items': [
        {
          'name': 'Nama barang',
          'quantity': 1,
          'unit': 'PCS',
          'unit_price': 0,
          'amount': 0,
        },
      ],
    },
  };

  static String templateJson() =>
      const JsonEncoder.withIndent('  ').convert(templateMap());

  static dynamic _decodeJson(String rawJson) {
    var source = rawJson.trim();
    final fenced = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(source);
    if (fenced != null) source = fenced.group(1)!.trim();
    try {
      return jsonDecode(source);
    } on FormatException catch (error) {
      throw ReceiptImportException('JSON tidak valid: ${error.message}');
    }
  }

  static ReceiptOcrItem? _parseItem(
    Map<String, dynamic> data,
    int index,
    List<String> warnings,
  ) {
    final name = _text(data['name'] ?? data['item'] ?? data['nama']);
    final quantity = _number(data['quantity'] ?? data['qty'] ?? data['jumlah']);
    final amount = _money(
      data['amount'] ?? data['line_total'] ?? data['total'],
    );
    final unitPrice = _money(
      data['unit_price'] ?? data['price'] ?? data['harga_satuan'],
    );
    if (name == null || name.trim().isEmpty) {
      warnings.add('Baris item ke-${index + 1} tidak memiliki nama.');
      return null;
    }
    final double safeQuantity = quantity == null || quantity <= 0
        ? 1.0
        : quantity;
    final safeAmount =
        amount ??
        (unitPrice == null ? null : (unitPrice * safeQuantity).round());
    if (safeAmount == null) {
      warnings.add('Nominal item "$name" belum terbaca.');
      return ReceiptOcrItem(
        name: name,
        price: unitPrice ?? 0,
        quantity: safeQuantity,
        unit: _text(data['unit'] ?? data['satuan']),
      );
    }
    final safePrice = unitPrice ?? (safeAmount / safeQuantity).round();
    return ReceiptOcrItem(
      name: name,
      price: safePrice,
      quantity: safeQuantity,
      unit: _text(data['unit'] ?? data['satuan']),
      lineTotal: safeAmount,
    );
  }

  static String? _text(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  static int? _money(dynamic value) {
    if (value == null || value is bool) return null;
    if (value is num) return value.round();
    var text = value.toString().trim();
    if (text.isEmpty) return null;
    text = text.replaceAll(RegExp(r'[^0-9,.]'), '');
    if (text.isEmpty) return null;
    if (text.contains('.') && text.contains(',')) {
      text = text.replaceAll('.', '').replaceAll(',', '');
    } else if (text.contains('.') || text.contains(',')) {
      final separator = text.contains('.') ? '.' : ',';
      final parts = text.split(separator);
      text = parts.length == 2 && parts.last.length < 3
          ? '${parts.first}.${parts.last}'
          : parts.join();
    }
    return double.tryParse(text)?.round();
  }

  static double? _number(dynamic value) {
    if (value == null || value is bool) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.'));
  }

  static DateTime? _date(dynamic value) {
    final text = _text(value);
    if (text == null) return null;
    return DateTime.tryParse(text);
  }
}
