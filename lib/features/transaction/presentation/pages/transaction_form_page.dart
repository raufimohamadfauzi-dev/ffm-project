import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../../core/database/app_context.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../core/ownership/owner_labels.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_components.dart';
import '../../../../shared/widgets/date_time_components.dart';
import '../../../../shared/widgets/hijri_date_components.dart';
import '../../data/services/offline_ai_engine_service.dart';
import '../../data/services/receipt_import_models.dart';
import '../../data/services/voice_transaction_parser.dart';
import '../../domain/entities/transaction_entity.dart';
import '../../../recurring_transaction/domain/usecases/recurring_transaction_crud_usecases.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/domain/ffm_assistant_form_prefill.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';
import '../../../liability/presentation/pages/liability_pages.dart';
import '../../../settings/presentation/pages/master_data_page.dart';
import '../widgets/voice_review_widgets.dart';
import '../widgets/transaction_components.dart';

class TransactionFormPage extends StatefulWidget {
  const TransactionFormPage({
    super.key,
    this.initialScan,
    this.existingTransaction,
    this.initialType,
    this.initialNote,
    this.initialAmount,
    this.initialAccountName,
    this.initialCategoryName,
    this.initialDate,
    this.initialPartyName,
    this.assistantMerchantName,
    this.assistantSlmFieldValues = const <String, String>{},
    this.assistantPrefill,
    this.onReturnToAssistant,
    this.showFirstTransactionGuide = false,
  });

  final ReceiptOcrResult? initialScan;
  final TransactionWithItems? existingTransaction;
  final TransactionType? initialType;
  final String? initialNote;
  final int? initialAmount;
  final String? initialAccountName;
  final String? initialCategoryName;
  final DateTime? initialDate;
  final String? initialPartyName;
  final String? assistantMerchantName;
  final Map<String, String> assistantSlmFieldValues;
  final FfmAssistantFormPrefill? assistantPrefill;
  final Future<void> Function()? onReturnToAssistant;
  final bool showFirstTransactionGuide;

  @override
  State<TransactionFormPage> createState() => _TransactionFormPageState();
}

class _TransactionFormPageState extends State<TransactionFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _locationController = TextEditingController();
  final _itemNameController = TextEditingController();
  final _itemPriceController = TextEditingController();
  final _tagController = TextEditingController();
  final _speech = SpeechToText();
  final _offlineAi = getIt<OfflineAiEngineService>();

  var _type = TransactionType.expense;
  var _categories = <Category>[];
  var _merchants = <Merchant>[];
  var _masterTags = <Tag>[];
  var _accounts = <Account>[];
  var _parties = <TransactionParty>[];
  String? _categoryId;
  String? _merchantId;
  String? _accountId;
  var _categoriesLoading = true;
  var _partiesLoading = true;
  var _partyName = '';
  var _source = 'manual';
  String? _receiptRawText;
  String? _receiptNumber;
  int? _receiptPaidAmount;
  int? _receiptChangeAmount;
  var _date = DateTime.now();
  var _items = <ReceiptItemDraft>[];
  var _tags = <String>[];
  var _attachmentPaths = <String>[];
  var _listening = false;
  String? _voiceText;
  VoiceTransactionParseResult? _voiceResult;
  int? _selectedAccountBalance;
  var _accountBalanceLoading = false;
  FfmAssistantFormCheck? _prefillCheck;

  @override
  void initState() {
    super.initState();

    // Store prefill check if provided
    if (widget.assistantPrefill != null) {
      _prefillCheck = widget.assistantPrefill!.check;
    }

    final existing = widget.existingTransaction;
    _type = widget.initialType ?? TransactionType.expense;
    if (existing != null) {
      _type = existing.transaction.amount >= 0
          ? TransactionType.income
          : TransactionType.expense;
      _categoryId = existing.transaction.categoryId;
      _merchantId = existing.transaction.merchantId;
      _accountId = existing.transaction.accountId;
      _partyName = existing.transaction.partyName ?? '';
      _source = existing.transaction.source ?? 'manual';
      _receiptRawText = existing.transaction.receiptRawText;
      _receiptNumber = existing.transaction.receiptNumber;
      _receiptPaidAmount = existing.transaction.receiptPaidAmount;
      _receiptChangeAmount = existing.transaction.receiptChangeAmount;
      _date = existing.transaction.date;
      _amountController.text = formatRupiahInput(
        existing.transaction.amount.abs().toString(),
      );
      _noteController.text = existing.transaction.note ?? '';
      _locationController.text = existing.transaction.location ?? '';
      _items = existing.items
          .map(
            (item) => ReceiptItemDraft(
              name: item.itemName,
              price: item.price,
              qty: item.qty,
            ),
          )
          .toList();
    }
    if (existing == null && widget.initialNote != null) {
      _noteController.text = widget.initialNote!;
    }
    if (existing == null && widget.initialAmount != null) {
      _amountController.text = formatRupiahInput(
        widget.initialAmount.toString(),
      );
    }
    if (existing == null && widget.initialDate != null) {
      _date = widget.initialDate!;
    }
    if (existing == null && (widget.initialPartyName != null || widget.assistantPrefill?.values['partyName'] != null || widget.assistantPrefill?.values['incomeSource'] != null || widget.assistantPrefill?.values['party'] != null)) {
      _partyName = widget.initialPartyName ?? widget.assistantPrefill?.values['partyName'] ?? widget.assistantPrefill?.values['party'] ?? widget.assistantPrefill?.values['incomeSource'] ?? '';
    }
    if (existing == null && widget.assistantPrefill != null) {
      final prefillValues = widget.assistantPrefill!.values;
      if (_locationController.text.trim().isEmpty && prefillValues['location']?.isNotEmpty == true) {
        _locationController.text = prefillValues['location']!;
      }
      if (_receiptNumber == null && prefillValues['receiptNumber']?.isNotEmpty == true) {
        _receiptNumber = prefillValues['receiptNumber'];
      }
      if (_receiptPaidAmount == null && prefillValues['receiptPaidAmount'] != null) {
        _receiptPaidAmount = int.tryParse(prefillValues['receiptPaidAmount']!);
      }
      if (_receiptChangeAmount == null && prefillValues['receiptChangeAmount'] != null) {
        _receiptChangeAmount = int.tryParse(prefillValues['receiptChangeAmount']!);
      }
      if (_receiptRawText == null && prefillValues['receiptRawText']?.isNotEmpty == true) {
        _receiptRawText = prefillValues['receiptRawText'];
      }
      if (_items.isEmpty && prefillValues['itemsJson']?.isNotEmpty == true) {
        try {
          final decoded = jsonDecode(prefillValues['itemsJson']!);
          if (decoded is List) {
            _items = decoded
                .map((item) {
                  if (item is Map) {
                    final name = item['name']?.toString() ??
                        item['itemName']?.toString() ??
                        '';
                    final price =
                        int.tryParse(item['price']?.toString() ?? '0') ?? 0;
                    final qty =
                        double.tryParse(item['qty']?.toString() ??
                            item['quantity']?.toString() ??
                            '1') ??
                        1.0;
                    return ReceiptItemDraft(name: name, price: price, qty: qty);
                  }
                  return null;
                })
                .whereType<ReceiptItemDraft>()
                .where((item) => item.name.isNotEmpty)
                .toList();
          }
        } catch (_) {}
      }
    }
    _loadCategories();
    _loadMerchants();
    _loadMasterTags();
    _loadAccounts();
    _loadParties();
    if (existing != null) _loadMetadata(existing.transaction.id);
    final scan = widget.initialScan;
    if (scan == null || existing != null) return;

    final total = scan.total ?? scan.itemsTotal;
    if (total > 0) _amountController.text = total.toString();
    if (scan.merchant != null) {
      _noteController.text = 'Toko: ${scan.merchant}';
      _merchantId = _matchMerchant(scan.merchant!);
    }
    _date = scan.date ?? _date;
    _categoryId = scan.categoryId ?? _categoryId;
    if (scan.imagePath != null && scan.imagePath!.isNotEmpty) {
      _attachmentPaths = [scan.imagePath!];
    }
    _partyName = '';
    _source = 'ocr';
    _receiptRawText = scan.rawText.isEmpty ? null : scan.rawText;
    _receiptNumber = scan.receiptNumber;
    _receiptPaidAmount = scan.paidAmount;
    _receiptChangeAmount = scan.changeAmount;

    _items = scan.items
        .map(
          (item) => ReceiptItemDraft(
            name: item.name,
            price: item.price,
            qty: item.quantity,
          ),
        )
        .toList();
  }

  Future<void> _loadParties() async {
    final parties =
        await (getIt<AppDatabase>().select(
                getIt<AppDatabase>().transactionParties,
              )
              ..where(
                (table) =>
                    table.householdId.equals(AppContext.householdId) &
                    table.isArchived.equals(false),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.name)]))
            .get();
    if (!mounted) return;
    setState(() {
      _parties = parties;
      _partiesLoading = false;
    });
  }

  Future<void> _loadAccounts() async {
    final accounts =
        await (getIt<AppDatabase>().select(getIt<AppDatabase>().accounts)
              ..where(
                (table) =>
                    table.householdId.equals(AppContext.householdId) &
                    table.isArchived.equals(false),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.name)]))
            .get();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      final targetName = widget.initialAccountName?.toLowerCase();
      if (_accountId == null && targetName != null) {
        final matches = accounts.where(
          (account) => account.name.toLowerCase() == targetName,
        );
        if (matches.isNotEmpty) _accountId = matches.first.id;
      }
    });
    if (_accountId != null) await _loadSelectedAccountBalance(_accountId);
  }

  Future<void> _loadSelectedAccountBalance(String? accountId) async {
    if (accountId == null) {
      if (mounted) setState(() => _selectedAccountBalance = null);
      return;
    }
    setState(() => _accountBalanceLoading = true);
    var balance = await getIt<GetAccountBookBalance>()(
      AppContext.householdId,
      accountId,
    );
    final existing = widget.existingTransaction;
    if (existing != null && existing.transaction.accountId == accountId) {
      balance -= existing.transaction.amount;
    }
    if (!mounted) return;
    setState(() {
      _selectedAccountBalance = balance;
      _accountBalanceLoading = false;
    });
  }

  Future<void> _loadMerchants() async {
    final merchants =
        await (getIt<AppDatabase>().select(getIt<AppDatabase>().merchants)
              ..where(
                (table) =>
                    table.householdId.equals(AppContext.householdId) &
                    table.isActive.equals(true),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.name)]))
            .get();
    if (!mounted) return;
    setState(() {
      _merchants = merchants;
      final rawMerchant = widget.initialScan?.merchant;
      if (rawMerchant != null && widget.existingTransaction == null) {
        _merchantId = _matchMerchant(rawMerchant);
      }
      // Prefill draft asisten: samakan kolom Toko dengan database + preview.
      if (_merchantId == null && widget.existingTransaction == null) {
        final draftMerchant =
            widget.assistantMerchantName ??
            widget.assistantPrefill?.values['merchant'] ??
            widget.assistantPrefill?.values['merchantName'];
        if (draftMerchant?.trim().isNotEmpty == true) {
          _merchantId = _matchMerchant(draftMerchant!.trim());
        }
      }
    });
  }

  Future<void> _loadMasterTags() async {
    final tags =
        await (getIt<AppDatabase>().select(getIt<AppDatabase>().tags)
              ..where(
                (table) =>
                    table.householdId.equals(AppContext.householdId) &
                    table.isArchived.equals(false),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.name)]))
            .get();
    if (!mounted) return;
    setState(() => _masterTags = tags);
    // Prefill tag draft asisten: samakan dengan kolom tag form + database.
    if (widget.existingTransaction == null &&
        widget.assistantPrefill != null &&
        _tags.isEmpty) {
      final rawTags =
          widget.assistantPrefill!.values['tags'] ??
          widget.assistantPrefill!.values['newTags'];
      if (rawTags?.trim().isNotEmpty == true) {
        for (final part in rawTags!.split(',')) {
          _addTag(part);
        }
      }
    }
  }

  String? _matchMerchant(String rawName) {
    final normalized = rawName.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
    if (normalized.isEmpty) return null;
    for (final merchant in _merchants) {
      final candidate = merchant.name.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]'),
        '',
      );
      if (candidate.isNotEmpty &&
          (normalized.contains(candidate) || candidate.contains(normalized))) {
        return merchant.id;
      }
    }
    return null;
  }

  Future<void> _openMasterData() async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => const MasterDataPage()));
    if (!mounted) return;
    await Future.wait([
      _loadCategories(),
      _loadMerchants(),
      _loadMasterTags(),
      _loadAccounts(),
      _loadParties(),
    ]);
  }

  String _categoryDisplayName(Category category) =>
      transactionCategoryLabel(_categories, category);

  Future<void> _loadCategories() async {
    final categories =
        await (getIt<AppDatabase>().select(getIt<AppDatabase>().categories)
              ..where(
                (table) =>
                    table.householdId.equals(AppContext.householdId) &
                    table.isActive.equals(true),
              )
              ..orderBy([(table) => OrderingTerm.asc(table.name)]))
            .get();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      final targetName = widget.initialCategoryName?.toLowerCase();
      if (_categoryId == null && targetName != null) {
        final matches = categories.where(
          (category) =>
              category.type ==
                  (_type == TransactionType.income ? 'income' : 'expense') &&
              category.name.toLowerCase() == targetName,
        );
        if (matches.length == 1) _categoryId = matches.single.id;
      }
      _categoriesLoading = false;
    });
  }

  Future<void> _loadMetadata(String transactionId) async {
    final database = getIt<AppDatabase>();
    final tagRows = await database
        .customSelect(
          'SELECT tags.name FROM tags INNER JOIN transaction_tags '
          'ON tags.id = transaction_tags.tag_id WHERE transaction_tags.transaction_id = ?',
          variables: [Variable.withString(transactionId)],
        )
        .get();
    final attachmentRows = await database
        .customSelect(
          'SELECT file_path FROM attachments WHERE transaction_id = ?',
          variables: [Variable.withString(transactionId)],
        )
        .get();
    if (!mounted) return;
    setState(() {
      _tags = tagRows
          .map((row) => row.data['name']?.toString() ?? '')
          .where((value) => value.isNotEmpty)
          .toList();
      _attachmentPaths = attachmentRows
          .map((row) => row.data['file_path']?.toString() ?? '')
          .where((value) => value.isNotEmpty)
          .toList();
    });
  }

  void _addTag(String value) {
    final allowed = _masterTags
        .map((tag) => tag.name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();
    final incoming = value
        .split(',')
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .where((item) => allowed.contains(item))
        .where((item) => !_tags.contains(item))
        .toList();
    if (incoming.isEmpty) {
      if (allowed.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Buat tag di Data Utama dulu kalau mau memakainya.'),
          ),
        );
      }
      return;
    }
    setState(() => _tags = [..._tags, ...incoming]);
    _tagController.clear();
  }

  Future<void> _showTagInfo() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tag transaksi itu buat apa?'),
        content: const Text(
          'Tag adalah penanda tambahan untuk mengelompokkan transaksi lintas kategori. Contohnya wajib, sekolah, kerja, mudik, atau bisa ditunda. Tag tidak mengubah saldo dan tidak menggantikan kategori. Buat dan kelola tag dari Data Utama, lalu pilih tag yang diperlukan di sini.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Oke, paham'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result.isEmpty) return;
    final paths = result
        .map((file) => file.path)
        .whereType<String>()
        .where((path) => path.isNotEmpty)
        .toList();
    if (paths.isEmpty) return;
    setState(() {
      _attachmentPaths = {..._attachmentPaths, ...paths}.toList();
    });
  }

  Future<void> _showVoiceGuide() async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          VoiceInputGuide(isIncome: _type == TransactionType.income),
    );
  }

  Future<void> _startVoiceInput() async {
    if (_listening) {
      if (_offlineAi.isWhisperRecording) {
        await _finishWhisperInput();
      } else {
        await _speech.stop();
        if (mounted) setState(() => _listening = false);
      }
      return;
    }
    setState(() {
      _listening = true;
      _voiceText = null;
    });

    if (_offlineAi.isWhisperReady) {
      try {
        if (await _offlineAi.startWhisperRecording()) return;
      } on Object catch (error) {
        if (mounted) {
          setState(() {
            _listening = false;
            _voiceText = 'Voice Note offline belum bisa dimulai: $error';
          });
        }
        return;
      }
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        if (!mounted || status != 'done') return;
        setState(() => _listening = false);
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _listening = false);
      },
    );
    if (!available) {
      if (mounted) {
        setState(() {
          _listening = false;
          _voiceText = 'Pengenalan suara tanpa internet belum tersedia di perangkat ini. Cek izin mikrofon dan bahasa Indonesia di pengaturan HP.';
        });
      }
      return;
    }
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        final text = result.recognizedWords.trim();
        setState(() => _voiceText = text.isEmpty ? null : text);
        if (result.finalResult && text.isNotEmpty) {
          unawaited(_applyVoiceResult(text));
        }
      },
      listenOptions: SpeechListenOptions(
        localeId: 'id_ID',
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
        partialResults: false,
        onDevice: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  Future<void> _finishWhisperInput() async {
    try {
      final result = await _offlineAi.stopWhisperRecording();
      final transcript = result.text.trim();
      if (transcript.isEmpty) {
        if (mounted) setState(() => _listening = false);
        return;
      }
      await _applyVoiceResult(transcript);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _listening = false;
        _voiceText = 'Voice Note offline perlu dicoba lagi: $error';
      });
    }
  }

  Future<void> _applyVoiceResult(String transcript) async {
    final parsedMany = VoiceTransactionParser.parseMany(
      transcript,
      _categories,
      merchants: _merchants,
      accounts: _accounts,
      parties: _parties,
      tags: _masterTags,
    );
    if (!mounted || parsedMany.isEmpty) return;
    setState(() {
      _voiceText = transcript;
      _voiceResult = parsedMany.length == 1 ? parsedMany.first : null;
      _listening = false;
    });
    if (parsedMany.length > 1) {
      await _reviewVoiceBatch(parsedMany);
      return;
    }
    await _reviewVoiceResult(parsedMany.first);
  }

  Future<void> _reviewVoiceBatch(
    List<VoiceTransactionParseResult> parsedResults,
  ) async {
    final drafts = await showDialog<List<TransactionDraft>>(
      context: context,
      builder: (_) => VoiceBatchReviewDialog(
        transcript: _voiceText ?? '',
        results: parsedResults,
        categories: _categories,
        merchants: _merchants,
        accounts: _accounts,
        parties: _parties,
        tagsMaster: _masterTags,
      ),
    );
    if (!mounted || drafts == null || drafts.isEmpty) return;
    Navigator.of(context).pop(drafts);
  }

  Future<void> _reviewVoiceResult(VoiceTransactionParseResult parsed) async {
    final parsedType = parsed.type == VoiceTransactionType.income
        ? TransactionType.income
        : TransactionType.expense;
    final nextType = parsed.hasExplicitType ? parsedType : _type;
    final existingCategory =
        _categoryId != null &&
            _categories.any((category) => category.id == _categoryId)
        ? _categoryId
        : null;
    final selectedCategory = parsed.hasExplicitType
        ? parsed.categoryId ?? existingCategory
        : existingCategory ?? parsed.categoryId;
    final selectedParty =
        parsed.partyName ??
        _partyNameOrEmpty(
          parsed.owner ?? '',
          nextType == TransactionType.income ? 'income_source' : 'used_by',
        );
    final review = await showDialog<VoiceReviewDraft>(
      context: context,
      builder: (_) => VoiceReviewDialog(
        transcript: _voiceText ?? parsed.note ?? '',
        type: nextType,
        amount: parsed.hasAmount
            ? parsed.amount
            : parseRupiah(_amountController.text),
        categoryId: selectedCategory,
        merchantId: parsed.merchantId ?? _merchantId,
        accountId: parsed.accountId ?? _accountId,
        partyName: selectedParty,
        note: parsed.note ?? _noteController.text,
        tags: {..._tags, ...parsed.tagNames}.toList(),
        categories: _categories,
        merchants: _merchants,
        accounts: _accounts,
        parties: _parties,
        tagsMaster: _masterTags,
      ),
    );
    if (!mounted || review == null) return;
    setState(() {
      _type = review.type;
      _amountController.text = formatRupiahInput(review.amount.toString());
      _categoryId = review.categoryId;
      _merchantId = review.merchantId;
      _accountId = review.accountId;
      _partyName = review.partyName;
      _noteController.text = review.note;
      _tags = review.tags;
      _source = 'voice';
    });
  }

  String _partyNameOrEmpty(String rawName, String kind) {
    final normalized = rawName.trim().toLowerCase();
    if (normalized.isEmpty) return '';
    final kindsToSearch = kind == 'used_by'
        ? ['used_by', 'husband', 'wife']
        : [kind];
    return _parties
            .where((party) => kindsToSearch.contains(party.kind))
            .where((party) => party.name.trim().toLowerCase() == normalized)
            .map((party) => party.name)
            .firstOrNull ??
        '';
  }

  List<TransactionParty> _partiesOfKind(String kind) =>
      _parties.where((party) => party.kind == kind).toList(growable: false);

  List<TransactionParty> _uniquePartiesByName(
    Iterable<TransactionParty> parties,
  ) {
    final seen = <String>{};
    return parties
        .where((party) {
          final name = party.name.trim().toLowerCase();
          return name.isNotEmpty && seen.add(name);
        })
        .toList(growable: false);
  }

  void _clearVoiceResult() {
    setState(() {
      _voiceText = null;
      _voiceResult = null;
      if (_source == 'voice') _source = 'manual';
    });
  }

  @override
  void dispose() {
    if (_offlineAi.isWhisperRecording) {
      unawaited(_offlineAi.cancelWhisperRecording());
    } else if (_listening) {
      unawaited(_speech.stop());
    }
    _amountController.dispose();
    _noteController.dispose();
    _locationController.dispose();
    _itemNameController.dispose();
    _itemPriceController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  String _fieldLabel(String field) {
    switch (field) {
      case 'amount':
        return 'Nominal';
      case 'fromAccountName':
        return 'Rekening asal';
      case 'toAccountName':
        return 'Rekening tujuan';
      case 'categoryName':
        return 'Kategori';
      case 'note':
        return 'Catatan';
      case 'date':
        return 'Tanggal';
      case 'title':
        return 'Judul';
      default:
        return field;
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate() ||
        _categoryId == null ||
        _accountId == null) {
      if (_accountId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pilih rekening atau dompet dulu supaya arus uangnya jelas.',
            ),
          ),
        );
      }
      return;
    }
    final amount = parseRupiah(_amountController.text);
    Navigator.of(context).pop([
      TransactionDraft(
        type: _type,
        categoryId: _categoryId!,
        owner: OwnerLabels.family,
        date: _date,
        amount: _type == TransactionType.income ? amount : -amount,
        note: _noteController.text.trim(),
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        source: _source,
        merchantId: _merchantId,
        accountId: _accountId,
        goalId: null,
        partyName: _partyName.trim().isEmpty ? null : _partyName.trim(),
        receiptRawText: _receiptRawText,
        receiptNumber: _receiptNumber,
        receiptPaidAmount: _receiptPaidAmount,
        receiptChangeAmount: _receiptChangeAmount,
        items: _items,
        tags: _tags,
        attachmentPaths: _attachmentPaths,
        assistantMerchantName: widget.assistantMerchantName,
        assistantSlmFieldValues: widget.assistantSlmFieldValues,
      ),
    ]);
  }

  Widget _buildAccountBalancePreview({required bool isExpense}) {
    if (_accountBalanceLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: LinearProgressIndicator(minHeight: 3),
      );
    }
    final balance = _selectedAccountBalance;
    if (balance == null) return const SizedBox.shrink();
    final amount = parseRupiah(_amountController.text);
    final after = isExpense ? balance - amount : balance + amount;
    final afterColor = after < 0 ? AppColors.negative : AppColors.positive;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Saldo sekarang'),
                AppMoneyText(balance, compact: true),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_rounded, size: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Saldo setelah disimpan'),
                AppMoneyText(after, compact: true, color: afterColor),
                if (after < 0)
                  Text(
                    'Saldo jadi minus',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.negative,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSelector() {
    if (_accounts.isEmpty) {
      return AppCard(
        color: Theme.of(context).colorScheme.primaryContainer
            .withValues(alpha: .45),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rekening atau dompet belum ada',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Rekening adalah tempat uang berada, misalnya Tunai, BCA, DANA, atau GoPay. Tambahkan dulu di Data Utama sebelum mencatat transaksi.',
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _openMasterData,
                    icon: const Icon(Icons.tune_outlined),
                    label: const Text('Buka Data Utama'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final selectedAccounts = _accounts
        .where((account) => account.id == _accountId)
        .toList(growable: false);
    final isExpense = _type == TransactionType.expense;
    final accountColor = _accountId == null
        ? AppColors.negative
        : AppColors.primary;
    return AppCard(
      color: isExpense
          ? AppColors.negativeSoft.withValues(alpha: .32)
          : AppColors.positiveSoft.withValues(alpha: .45),
      border: BorderSide(color: accountColor, width: 1.6),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_rounded, color: accountColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isExpense
                      ? 'Sumber uang keluar · wajib diisi'
                      : 'Tujuan uang masuk · wajib diisi',
                  style: TextStyle(
                    color: accountColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SearchableDropdown<Account>(
            items: _accounts,
            selectedItem: selectedAccounts.isEmpty
                ? null
                : selectedAccounts.first,
            itemLabel: (account) =>
                '${account.name} · ${_accountTypeLabel(account.type)}',
            itemId: (account) => account.id,
            labelText: isExpense
                ? 'Rekening sumber pengeluaran'
                : 'Rekening tujuan pemasukan',
            helperText: isExpense
                ? 'Pengeluaran akan mengurangi saldo rekening ini.'
                : 'Pemasukan akan menambah saldo rekening ini.',
            searchHintText: 'Cari rekening atau dompet',
            cacheKey: 'transaksi.rekening',
            onChanged: (account) {
              setState(() => _accountId = account?.id);
              _loadSelectedAccountBalance(account?.id);
            },
            validator: (account) =>
                account == null ? 'Pilih rekening atau dompet dulu.' : null,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              final result = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (_) => const MasterDataPage(
                    assistantTab: 3,
                    returnOnCreate: true,
                  ),
                ),
              );
              if (result != null && mounted) {
                await _loadAccounts();
                setState(() => _accountId = result);
                _loadSelectedAccountBalance(result);
              }
            },
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Tambah rekening baru di Data Utama'),
          ),
          _buildAccountBalancePreview(isExpense: isExpense),
        ],
      ),
    );
  }

  Widget _buildPartySelector({required bool isIncome}) {
    final options = isIncome
        ? _partiesOfKind('income_source')
        : _uniquePartiesByName([
            ..._partiesOfKind('husband'),
            ..._partiesOfKind('wife'),
            ..._partiesOfKind('used_by'),
          ]);
    final label = isIncome ? 'Sumber pemasukan' : 'Dipakai oleh';
    final help = isIncome
        ? 'Pilih sumber uangnya, misalnya gaji atau panen. Saldo tetap gabungan keluarga.'
        : 'Cuma penanda rincian pemakaian. Saldo tetap gabungan keluarga.';
    if (options.isEmpty) {
      return AppCard(
        color: Theme.of(context).colorScheme.primaryContainer
            .withValues(alpha: .45),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.tune_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$label belum ada',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isIncome
                        ? 'Tambahkan sumber pemasukan di Data Utama supaya pilihan ini muncul di sini.'
                        : 'Tambahkan rincian pemakai di Data Utama kalau ingin menandainya.',
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _openMasterData,
                    icon: const Icon(Icons.tune_outlined),
                    label: const Text('Buka Data Utama'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final selectedParties = options
        .where((party) => party.name == _partyName)
        .toList(growable: false);
    return SearchableDropdown<TransactionParty>(
      items: options,
      selectedItem: selectedParties.isEmpty ? null : selectedParties.first,
      itemLabel: (party) => party.details?.trim().isNotEmpty == true
          ? '${party.name} · ${party.details}'
          : party.name,
      itemId: (party) => party.name,
      labelText: label,
      helperText: help,
      searchHintText: 'Cari sumber atau pemakai',
      cacheKey: 'transaksi.${isIncome ? 'sumber_pemasukan' : 'dipakai_oleh'}',
      onChanged: (party) => setState(() => _partyName = party?.name ?? ''),
      validator: isIncome
          ? (party) => party == null ? 'Pilih sumber pemasukan dulu.' : null
          : null,
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _date,
      helpText: 'Pilih tanggal transaksi',
      cancelText: AppCopy.batal,
      confirmText: AppCopy.selesai,
    );
    if (picked != null) {
      setState(
        () => _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _date.hour,
          _date.minute,
          _date.second,
        ),
      );
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
      helpText: 'Pilih jam kejadian',
      cancelText: AppCopy.batal,
      confirmText: AppCopy.selesai,
    );
    if (picked != null) {
      setState(
        () => _date = DateTime(
          _date.year,
          _date.month,
          _date.day,
          picked.hour,
          picked.minute,
          _date.second,
        ),
      );
    }
  }

  void _addItem() {
    final name = _itemNameController.text.trim();
    final price = parseRupiah(_itemPriceController.text);
    if (name.isEmpty || price <= 0) {
      return;
    }
    setState(() {
      _items = [..._items, ReceiptItemDraft(name: name, price: price)];
      _syncAmountFromItems();
      _itemNameController.clear();
      _itemPriceController.clear();
    });
  }

  void _syncAmountFromItems() {
    final total = _items.fold<int>(
      0,
      (sum, item) => sum + (item.price * item.qty).round(),
    );
    if (total > 0) {
      _amountController.text = formatRupiahInput(total.toString());
    }
  }

  Future<void> _editItem(int index) async {
    final edited = await showDialog<ReceiptItemDraft>(
      context: context,
      builder: (_) => ReceiptItemEditorDialog(item: _items[index]),
    );
    if (!mounted || edited == null) return;
    setState(() {
      _items[index] = edited;
      _syncAmountFromItems();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = _type == TransactionType.income;
    final scheme = Theme.of(context).colorScheme;
    final flowColor = isIncome ? AppColors.positive : AppColors.negative;
    final flowLabel = isIncome ? 'Uang masuk' : 'Uang keluar';
    final categoryOptions = transactionCategoryOptions(
      _categories,
      isIncome ? 'income' : 'expense',
      selectedId: _categoryId,
    );
    final voiceResult = _voiceResult;
    final voiceCategoryId = voiceResult?.categoryId;
    final voiceCategoryName = voiceCategoryId == null
        ? 'Belum terbaca'
        : _categories
                  .where((category) => category.id == voiceCategoryId)
                  .map((category) => category.name)
                  .firstOrNull ??
              'Belum terbaca';
    final hasAssistantPrefill =
        widget.initialAmount != null ||
        widget.initialAccountName != null ||
        widget.initialCategoryName != null ||
        widget.initialNote != null ||
        widget.initialDate != null;
    return FfmAssistantPageContext(
      destination: FfmAssistantDestination.transactions,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.existingTransaction == null
                ? (isIncome ? 'Tambah pemasukan' : 'Tambah pengeluaran')
                : (isIncome ? 'Ubah pemasukan' : 'Ubah pengeluaran'),
          ),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (widget.showFirstTransactionGuide)
                FirstTransactionGuide(
                  isIncome: isIncome,
                  onOpenLiability: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LiabilityReceivablePage(),
                      ),
                    );
                  },
                ),
              if (widget.showFirstTransactionGuide) const SizedBox(height: 16),
              if (hasAssistantPrefill) ...[
                AppCard(
                  color: scheme.secondaryContainer,
                  padding: const EdgeInsets.all(12),
                  child: const Row(
                    children: [
                      Icon(Icons.auto_awesome_outlined),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Diisi dari draft Asisten — periksa sebelum simpan.',
                        ),
                      ),
                    ],
                  ),
                ),
                if (_prefillCheck != null && _prefillCheck!.missingFields.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange.shade700,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Field yang belum lengkap:',
                              style: TextStyle(
                                color: Colors.orange.shade900,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ..._prefillCheck!.missingFields.map((field) => Padding(
                          padding: const EdgeInsets.only(left: 20, top: 2),
                          child: Text(
                            _fieldLabel(field),
                            style: TextStyle(
                              color: Colors.orange.shade800,
                              fontSize: 11,
                            ),
                          ),
                        )),
                      ],
                    ),
                  ),
                if (_prefillCheck != null && _prefillCheck!.warnings.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.amber.shade700,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Perhatian:',
                              style: TextStyle(
                                color: Colors.amber.shade900,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ..._prefillCheck!.warnings.map((warning) => Padding(
                          padding: const EdgeInsets.only(left: 20, top: 2),
                          child: Text(
                            warning,
                            style: TextStyle(
                              color: Colors.amber.shade800,
                              fontSize: 11,
                            ),
                          ),
                        )),
                      ],
                    ),
                  ),
                if (widget.onReturnToAssistant != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await widget.onReturnToAssistant?.call();
                      },
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Kembali ke chat untuk koreksi'),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              AppCard(
                color: flowColor.withValues(alpha: isIncome ? .16 : .10),
                border: BorderSide(color: flowColor, width: isIncome ? 2 : 1.4),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isIncome
                              ? Icons.south_west_rounded
                              : Icons.north_east_rounded,
                          color: flowColor,
                          size: 28,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                flowLabel,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: flowColor,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              Text(
                                isIncome
                                    ? 'Menambah saldo keluarga'
                                    : 'Mengurangi saldo keluarga',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cara input suara',
                          onPressed: _showVoiceGuide,
                          icon: const Icon(Icons.help_outline_rounded),
                        ),
                        IconButton.filledTonal(
                          tooltip: _listening
                              ? 'Berhenti mendengar'
                              : 'Isi dengan suara',
                          onPressed: _categoriesLoading
                              ? null
                              : _startVoiceInput,
                          icon: Icon(
                            _listening
                                ? Icons.stop_rounded
                                : Icons.mic_none_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _listening
                          ? 'Ngomong sekarang: sebut arah, nominal, dan keperluannya.'
                          : 'Tekan mikrofon, ucapkan satu kalimat pendek, lalu cek hasilnya.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: flowColor.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Jenis transaksi: $flowLabel',
                        style: TextStyle(
                          color: flowColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: const [RupiahInputFormatter()],
                      readOnly: _items.isNotEmpty,
                      decoration: InputDecoration(
                        labelText: _items.isNotEmpty
                            ? 'Nominal $flowLabel (otomatis dari item)'
                            : 'Nominal $flowLabel',
                        prefixText: 'Rp ',
                        hintText: '0',
                        filled: true,
                        fillColor: scheme.surfaceContainerLowest,
                        helperText: _items.isNotEmpty
                            ? 'Terkunci: dijumlahkan otomatis dari seluruh item di bawah.'
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (value) {
                        final amount = parseRupiah(value ?? '');
                        if (amount <= 0) {
                          return AppCopy.nominalTidakValid;
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_voiceText != null)
                AppCard(
                  color: scheme.primaryContainer.withValues(alpha: .45),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.graphic_eq_rounded, color: scheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _listening
                                  ? 'Lagi mendengarkan…'
                                  : 'Hasil suara: “$_voiceText”',
                            ),
                          ),
                        ],
                      ),
                      if (!_listening && voiceResult != null) ...[
                        const SizedBox(height: 14),
                        const Text(
                          'Cek dulu hasilnya. Data belum tersimpan sampai kamu menekan Simpan.',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        VoiceResultLine(
                          label: 'Arah transaksi',
                          value: voiceResult.hasExplicitType ? flowLabel : 'Belum disebut — pilih Uang masuk atau Uang keluar',
                          isValid: voiceResult.hasExplicitType,
                        ),
                        VoiceResultLine(
                          label: 'Nominal',
                          value: voiceResult.hasAmount
                              ? 'Rp ${formatRupiahInput(voiceResult.amount.toString())}'
                              : 'Belum terbaca — isi manual',
                          isValid: voiceResult.hasAmount,
                        ),
                        VoiceResultLine(
                          label: 'Kategori',
                          value: voiceCategoryName,
                          isValid: voiceResult.categoryId != null,
                        ),
                        VoiceResultLine(
                          label: 'Dipakai oleh / sumber',
                          value:
                              voiceResult.partyName ??
                              voiceResult.owner ??
                              'Belum diatur',
                          isValid: voiceResult.partyName != null,
                        ),
                        VoiceResultLine(
                          label: 'Toko / rekening',
                          value:
                              voiceResult.merchantId != null ||
                                  voiceResult.accountId != null
                              ? 'Terbaca dari Data Utama'
                              : 'Belum cocok — pilih manual di editor',
                          isValid:
                              voiceResult.merchantId != null ||
                              voiceResult.accountId != null,
                        ),
                        VoiceResultLine(
                          label: 'Tag',
                          value: voiceResult.tagNames.isEmpty
                              ? 'Belum ada — boleh ditambahkan'
                              : voiceResult.tagNames
                                    .map((tag) => '#$tag')
                                    .join(', '),
                          isValid: voiceResult.tagNames.isNotEmpty,
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _reviewVoiceResult(voiceResult),
                            icon: const Icon(Icons.edit_note_rounded),
                            label: const Text(
                              'Tinjau dan terapkan ke transaksi',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            TextButton.icon(
                              onPressed: _startVoiceInput,
                              icon: const Icon(Icons.mic_none_rounded),
                              label: const Text('Dengar lagi'),
                            ),
                            TextButton.icon(
                              onPressed: _clearVoiceResult,
                              icon: const Icon(Icons.clear_rounded),
                              label: const Text('Hapus hasil'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              if (_voiceText != null) const SizedBox(height: 12),
              AppSectionHeader(
                title: isIncome
                    ? '1. Lokasi uang masuk'
                    : '1. Lokasi uang keluar',
                helpText: isIncome
                    ? 'Pilih rekening tujuan. Saldo rekening ini akan bertambah setelah disimpan.'
                    : 'Pilih rekening sumber. Saldo rekening ini akan berkurang setelah disimpan.',
              ),
              const SizedBox(height: 8),
              _buildAccountSelector(),
              const SizedBox(height: 16),
              AppSectionHeader(
                title: isIncome
                    ? '2. Kategori pemasukan'
                    : '2. Kategori pengeluaran',
                helpText: isIncome
                    ? 'Contoh: gaji, panen, bonus, atau pemberian.'
                    : 'Contoh: belanja, listrik, BBM, makan, atau biaya admin.',
              ),
              const SizedBox(height: 8),
              if (_categoriesLoading)
                const LinearProgressIndicator()
              else if (categoryOptions.isEmpty)
                AppCard(
                  color: Theme.of(context).colorScheme.errorContainer
                      .withValues(alpha: .45),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.category_outlined,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Kategori ${_type == TransactionType.income ? 'pemasukan' : 'pengeluaran'} masih kosong',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Buat kategori ${_type == TransactionType.income ? 'pemasukan' : 'pengeluaran'} dulu supaya transaksi bisa masuk ke laporan dan Anggaran.',
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _openMasterData,
                              icon: const Icon(Icons.add),
                              label: const Text('Buka Data Utama'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                SearchableDropdown(
                  items: categoryOptions,
                  selectedItem: categoryOptions
                      .where((category) => category.id == _categoryId)
                      .firstOrNull,
                  itemLabel: _categoryDisplayName,
                  itemId: (category) => category.id,
                  labelText: 'Kategori uang masuk / keluar',
                  helperText: 'Pilih sendiri. Tidak ada kategori yang dipilih otomatis.',
                  searchHintText: 'Cari kategori transaksi',
                  cacheKey: 'transaksi.kategori',
                  onChanged: (category) {
                    if (category != null) {
                      setState(() => _categoryId = category.id);
                    }
                  },
                  validator: (category) =>
                      category == null ? 'Pilih kategori dulu.' : null,
                ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  final result = await Navigator.of(context).push<String>(
                    MaterialPageRoute(
                      builder: (_) => const MasterDataPage(
                        assistantTab: 0,
                        returnOnCreate: true,
                      ),
                    ),
                  );
                  if (result != null && mounted) {
                    await _loadCategories();
                    setState(() => _categoryId = result);
                  }
                },
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Tambah kategori baru di Data Utama'),
              ),
              if (_type == TransactionType.expense)
                AppCard(
                  color: Theme.of(context).colorScheme.primaryContainer
                      .withValues(alpha: .45),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.auto_awesome_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Kategori ini akan dihitung otomatis ke pos Anggaran yang sesuai. Target uang terkumpul dicatat lewat menu khusus, bukan di sini.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              AppSectionHeader(
                title: isIncome
                    ? '3. Rincian tambahan pemasukan'
                    : '3. Rincian tambahan',
                helpText:
                    'Buka bagian ini kalau ingin mengisi toko, lokasi, tanggal, sumber/pemakai, atau catatan.',
              ),
              const SizedBox(height: 4),
              ExpansionTile(
                initiallyExpanded:
                    isIncome ||
                    _merchantId != null ||
                    _locationController.text.trim().isNotEmpty ||
                    _partyName.trim().isNotEmpty,
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                leading: Icon(
                  isIncome ? Icons.event_note_outlined : Icons.tune_outlined,
                ),
                title: Text(
                  isIncome ? 'Buka rincian pemasukan' : 'Buka rincian tambahan',
                ),
                subtitle: const Text(
                  'Toko, lokasi, waktu, sumber/pemakai, dan catatan',
                ),
                children: [
                  // Kolom disamakan untuk pemasukan + pengeluaran + draft
                  // asisten + database: toko, lokasi, tanggal, pihak, catatan.
                  if (_merchants.isNotEmpty)
                      SearchableDropdown(
                        items: _merchants,
                        selectedItem: _merchants
                            .where((merchant) => merchant.id == _merchantId)
                            .firstOrNull,
                        itemLabel: (merchant) =>
                            merchant.details?.trim().isNotEmpty == true
                            ? '${merchant.name} · ${merchant.details}'
                            : merchant.name,
                        itemId: (merchant) => merchant.id,
                        labelText: 'Toko / tempat',
                        helperText: 'Pilih dari Data Utama agar nama dan rinciannya konsisten.',
                        searchHintText: 'Cari toko atau tempat',
                        cacheKey: 'transaksi.toko',
                        allowClear: true,
                        onChanged: (merchant) =>
                            setState(() => _merchantId = merchant?.id),
                      )
                    else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _openMasterData,
                          icon: const Icon(Icons.tune_rounded),
                          label: const Text('Atur toko di Data Utama'),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _locationController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Lokasi transaksi',
                        hintText: 'Misalnya pasar, rumah, atau kantor',
                        helperText: 'Rekening = tempat uang berada. Lokasi = tempat kejadian.',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: const Text('Tanggal kejadian'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(formatTanggalLengkap(_date)),
                        HijriDateLabel(date: _date),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickDate,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_outlined),
                    title: const Text('Jam kejadian'),
                    subtitle: Text(formatJam(_date)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickTime,
                  ),
                  if (isDataSusulan(_date, now: DateTime.now()))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Tanggal kejadian berbeda dari hari ini. Data ini akan ditandai sebagai susulan.',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: AppColors.warning),
                      ),
                    ),
                  if (_partiesLoading)
                    const LinearProgressIndicator()
                  else
                    _buildPartySelector(isIncome: isIncome),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _noteController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: AppCopy.catatanOpsional,
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppSectionHeader(
                title: isIncome
                    ? '4. Opsi tambahan pemasukan (opsional)'
                    : '4. Tag dan lampiran',
                helpText: isIncome
                    ? 'Tag untuk menandai sumber pemasukan. Lampiran untuk bukti penerimaan bila ada.'
                    : 'Tag membantu pencarian dan pengelompokan. Lampiran hanya sebagai bukti transaksi.',
              ),
              const SizedBox(height: 4),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isIncome ? 'Bukti dan penanda' : 'Tag dan lampiran',
                            style: AppTextStyles.labelCaps,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Buka penjelasan Tag',
                          onPressed: _showTagInfo,
                          icon: const Icon(Icons.info_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _masterTags.isEmpty
                          ? 'Belum ada tag. Atur dulu dari Data Utama.'
                          : (isIncome
                                ? 'Opsional. Tag tidak mengubah saldo; lampiran hanya sebagai bukti penerimaan.'
                                : 'Pilih penanda dari Data Utama. Tag tidak mengubah saldo.'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_masterTags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final tag in _masterTags)
                            FilterChip(
                              label: Text('#${tag.name}'),
                              selected: _tags.contains(
                                tag.name.trim().toLowerCase(),
                              ),
                              onSelected: (_) => _addTag(tag.name),
                            ),
                        ],
                      ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: TextButton.icon(
                          onPressed: _openMasterData,
                          icon: const Icon(Icons.tune_rounded),
                          label: const Text('Atur tag di Data Utama'),
                        ),
                      ),
                    if (_tags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final tag in _tags)
                            InputChip(
                              label: Text('#$tag'),
                              onDeleted: () => setState(
                                () => _tags = [..._tags]..remove(tag),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pickAttachments,
                      icon: const Icon(Icons.attach_file_rounded),
                      label: Text(
                        isIncome
                            ? 'Tambah bukti penerimaan (foto/PDF)'
                            : 'Tambah foto atau PDF nota',
                      ),
                    ),
                    if (_attachmentPaths.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      for (final path in _attachmentPaths)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.insert_drive_file_outlined),
                          title: Text(
                            path.split(RegExp(r'[/\\\\]')).last,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: 'Hapus lampiran',
                            onPressed: () => setState(
                              () =>
                                  _attachmentPaths = [..._attachmentPaths]
                                    ..remove(path),
                            ),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Rincian item disamakan untuk pemasukan + pengeluaran +
              // draft asisten + database (transaction_items).
              const AppSectionHeader(
                title: '5. Rincian nota dan banyak item',
                helpText: 'Pakai bagian ini kalau satu transaksi punya beberapa barang atau detail nota.',
              ),
                const SizedBox(height: 4),
                AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Rincian nota',
                              style: AppTextStyles.labelCaps,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _showAddItemSheet,
                            icon: const Icon(Icons.add),
                            label: const Text(AppCopy.tambah),
                          ),
                        ],
                      ),
                      if (_items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Belum ada item nota. Bagian ini boleh dilewati.',
                          ),
                        )
                      else
                        ..._items.map(
                          (item) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.name),
                            subtitle: item.qty == 1
                                ? null
                                : Text('Jumlah ${item.qty.toStringAsFixed(2)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppMoneyText(item.price, compact: true),
                                IconButton(
                                  tooltip: 'Ubah item',
                                  onPressed: () =>
                                      _editItem(_items.indexOf(item)),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Hapus item',
                                  onPressed: () => setState(() {
                                    _items.remove(item);
                                    _syncAmountFromItems();
                                  }),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: Text(
                    widget.existingTransaction == null
                        ? AppCopy.simpanTransaksi
                        : 'Simpan perubahan',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddItemSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tambah item nota',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _itemNameController,
              decoration: const InputDecoration(labelText: 'Nama item'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _itemPriceController,
              keyboardType: TextInputType.number,
              inputFormatters: const [RupiahInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Harga item',
                prefixText: 'Rp ',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                _addItem();
                Navigator.pop(context);
              },
              child: const Text('Tambahkan item'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  String _accountTypeLabel(String type) {
    return switch (type) {
      'cash' => 'Tunai',
      'bank' => 'Rekening',
      'ewallet' => 'Dompet digital',
      _ => type,
    };
  }
}
