import '../../../../core/database/app_database.dart';

enum VoiceTransactionType { income, expense }

class VoiceTransactionParseResult {
  const VoiceTransactionParseResult({
    required this.type,
    this.amount = 0,
    this.categoryId,
    this.merchantId,
    this.accountId,
    this.partyName,
    this.owner,
    this.note,
    this.tagNames = const [],
    this.hasExplicitType = false,
    this.hasAmount = false,
  });

  final VoiceTransactionType type;
  final int amount;
  final String? categoryId;
  final String? merchantId;
  final String? accountId;
  final String? partyName;
  final String? owner;
  final String? note;
  final List<String> tagNames;
  final bool hasExplicitType;
  final bool hasAmount;
}

abstract final class VoiceTransactionParser {
  static List<VoiceTransactionParseResult> parseMany(
    String transcript,
    List<Category> categories, {
    List<Merchant> merchants = const [],
    List<Account> accounts = const [],
    List<TransactionParty> parties = const [],
    List<Tag> tags = const [],
  }) {
    final chunks = transcript
        .split(RegExp(r'\s+(?:lalu|kemudian|dan juga|setelah itu)\s+|[;\n]+', caseSensitive: false))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty);
    return chunks.map((chunk) => parse(
      chunk,
      categories,
      merchants: merchants,
      accounts: accounts,
      parties: parties,
      tags: tags,
    )).toList(growable: false);
  }

  static VoiceTransactionParseResult parse(
    String transcript,
    List<Category> categories, {
    List<Merchant> merchants = const [],
    List<Account> accounts = const [],
    List<TransactionParty> parties = const [],
    List<Tag> tags = const [],
  }) {
    final lower = transcript.toLowerCase();
    final income = RegExp(r'\b(pemasukan|masuk|menerima|diterima|gaji|pendapatan|dapat)\b').hasMatch(lower);
    final expense = RegExp(r'\b(pengeluaran|keluar|bayar|beli|belanja|jajan|biaya)\b').hasMatch(lower);
    final type = income && !expense ? VoiceTransactionType.income : VoiceTransactionType.expense;
    final amount = _parseAmount(lower);
    final category = categories.where((item) {
      final name = item.name.toLowerCase();
      return name.isNotEmpty && lower.contains(name);
    }).firstOrNull;
    final merchant = merchants.where((item) => lower.contains(item.name.toLowerCase())).firstOrNull;
    final account = accounts.where((item) => lower.contains(item.name.toLowerCase())).firstOrNull;
    final party = parties.where((item) => lower.contains(item.name.toLowerCase())).firstOrNull;
    final selectedTags = tags
        .where((item) => lower.contains(item.name.toLowerCase()))
        .map((item) => item.name)
        .toList(growable: false);
    return VoiceTransactionParseResult(
      type: type,
      amount: amount,
      categoryId: category?.id,
      merchantId: merchant?.id,
      accountId: account?.id,
      partyName: party?.name,
      owner: party?.name,
      note: transcript.trim(),
      tagNames: selectedTags,
      hasExplicitType: income || expense,
      hasAmount: amount > 0,
    );
  }

  static int _parseAmount(String text) {
    final numeric = RegExp(r'(\d[\d.,]*)').allMatches(text).map((m) => m.group(1)!).toList();
    if (numeric.isNotEmpty) {
      final raw = numeric.last.replaceAll(RegExp(r'[^0-9]'), '');
      if (raw.isNotEmpty) return int.tryParse(raw) ?? 0;
    }
    const units = <String, int>{
      'nol': 0, 'satu': 1, 'dua': 2, 'tiga': 3, 'empat': 4, 'lima': 5,
      'enam': 6, 'tujuh': 7, 'delapan': 8, 'sembilan': 9, 'sepuluh': 10,
      'sebelas': 11,
    };
    final tokens = text
        .replaceAll(RegExp(r'[^a-z ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((item) => item.isNotEmpty)
        .toList();
    var total = 0;
    var current = 0;
    var found = false;
    for (final token in tokens) {
      if (units.containsKey(token)) {
        current += units[token]!;
        found = true;
      } else if (token == 'belas') {
        current += 10;
      } else if (token == 'puluh') {
        current = (current == 0 ? 1 : current) * 10;
      } else if (token == 'ratus') {
        current = (current == 0 ? 1 : current) * 100;
      } else if (token == 'ribu') {
        total += (current == 0 ? 1 : current) * 1000;
        current = 0;
      } else if (token == 'juta') {
        total += (current == 0 ? 1 : current) * 1000000;
        current = 0;
      } else if (token == 'miliar') {
        total += (current == 0 ? 1 : current) * 1000000000;
        current = 0;
      }
    }
    return found ? total + current : 0;
  }
}
