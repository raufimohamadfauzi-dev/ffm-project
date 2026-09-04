import 'dart:async';
import '../domain/ffm_assistant_models.dart';

/// Service untuk melacak perubahan draft dan mengirim feedback ke LLM
/// serta mempelajari aturan personal baru secara otonom (Modul 3A).
class FfmAssistantDraftFeedbackService {
  FfmAssistantDraftFeedbackService({
    this.onRuleLearned,
  });

  Future<void> Function({
    required String key,
    required String value,
    required String label,
  })? onRuleLearned;

  final List<DraftChangeRecord> _changeHistory = [];
  final List<({String key, String value, String label})> _learnedRules = [];
  static const int _maxHistorySize = 10;

  List<({String key, String value, String label})> get learnedRules =>
      List.unmodifiable(_learnedRules);

  /// Mencatat perubahan draft saat user mengedit draft dan belajar aturan personal secara otonom
  Future<void> recordDraftEdit({
    required FfmAssistantDraft originalDraft,
    required FfmAssistantDraft editedDraft,
    required DateTime timestamp,
  }) async {
    final changedFields = _identifyChangedFields(originalDraft, editedDraft);
    
    if (changedFields.isEmpty) return;

    final record = DraftChangeRecord(
      originalDraft: originalDraft,
      editedDraft: editedDraft,
      changedFields: changedFields,
      timestamp: timestamp,
      changeType: _determineChangeType(changedFields),
    );

    _changeHistory.add(record);
    if (_changeHistory.length > _maxHistorySize) {
      _changeHistory.removeAt(0);
    }

    await _extractAndLearnRules(originalDraft, editedDraft);
  }

  Future<void> _extractAndLearnRules(
    FfmAssistantDraft original,
    FfmAssistantDraft edited,
  ) async {
    // 1. Koreksi Kategori berdasarkan Toko / Merchant
    final merchant = edited.merchantName?.trim();
    final editedCategory = edited.categoryName?.trim();
    if (merchant != null &&
        merchant.isNotEmpty &&
        editedCategory != null &&
        editedCategory.isNotEmpty &&
        original.categoryName != edited.categoryName) {
      final key = 'merchant_category_${merchant.toLowerCase()}';
      final label = 'Toko "$merchant" dikategorikan sebagai: $editedCategory';
      _learnedRules.removeWhere((r) => r.key == key);
      _learnedRules.add((key: key, value: editedCategory, label: label));
      if (onRuleLearned != null) {
        await onRuleLearned!(
          key: key,
          value: editedCategory,
          label: label,
        );
      }
    }

    // 2. Koreksi Kategori berdasarkan Judul Transaksi (jika merchant tidak ada)
    final title = edited.title?.trim();
    if ((merchant == null || merchant.isEmpty) &&
        title != null &&
        title.isNotEmpty &&
        editedCategory != null &&
        editedCategory.isNotEmpty &&
        original.categoryName != edited.categoryName) {
      final key = 'item_category_${title.toLowerCase()}';
      final label = 'Item "$title" dikategorikan sebagai: $editedCategory';
      _learnedRules.removeWhere((r) => r.key == key);
      _learnedRules.add((key: key, value: editedCategory, label: label));
      if (onRuleLearned != null) {
        await onRuleLearned!(
          key: key,
          value: editedCategory,
          label: label,
        );
      }
    }

    // 3. Koreksi Rekening Sumber
    final fromAccount = edited.fromAccountName?.trim();
    if (fromAccount != null &&
        fromAccount.isNotEmpty &&
        original.fromAccountName != edited.fromAccountName) {
      const key = 'preferred_account';
      final label = 'Rekening sumber utama pilihan: $fromAccount';
      _learnedRules.removeWhere((r) => r.key == key);
      _learnedRules.add((key: key, value: fromAccount, label: label));
      if (onRuleLearned != null) {
        await onRuleLearned!(
          key: key,
          value: fromAccount,
          label: label,
        );
      }
    }
  }

  /// Mencari kategori yang dipelajari untuk merchant tertentu (lookup deterministik).
  String? findCategoryForMerchant(String merchant) {
    final key = 'merchant_category_${merchant.trim().toLowerCase()}';
    for (final rule in _learnedRules.reversed) {
      if (rule.key == key) return rule.value;
    }
    return null;
  }

  /// Mencari kategori yang dipelajari untuk judul item tertentu (lookup deterministik).
  String? findCategoryForItem(String item) {
    final key = 'item_category_${item.trim().toLowerCase()}';
    for (final rule in _learnedRules.reversed) {
      if (rule.key == key) return rule.value;
    }
    return null;
  }

  /// Mendapatkan rekening sumber preferensi yang dipelajari (lookup deterministik).
  String? findPreferredAccount() {
    for (final rule in _learnedRules.reversed) {
      if (rule.key == 'preferred_account') return rule.value;
    }
    return null;
  }

  /// Mendapatkan feedback message untuk dikirim ke LLM
  String getFeedbackMessageForLLM() {
    if (_changeHistory.isEmpty) {
      return '';
    }

    final recentChanges = _changeHistory.take(3).toList();
    final feedback = StringBuffer();
    
    feedback.writeln('Konteks perubahan draft terbaru:');
    for (final change in recentChanges) {
      feedback.writeln('- ${change.changeType}: ${change.changedFields.join(', ')}');
      if (change.changedFields.contains('title')) {
        feedback.writeln('  Dari: "${change.originalDraft.title ?? '-'}"');
        feedback.writeln('  Ke: "${change.editedDraft.title ?? '-'}"');
      }
    }
    
    return feedback.toString();
  }

  /// Mendapatkan context tentang draft yang sedang diedit
  Map<String, dynamic> getDraftContextForLLM(FfmAssistantDraft? currentDraft) {
    if (currentDraft == null) {
      return {};
    }

    return {
      'activeDraft': {
        'kind': currentDraft.kind.name,
        'title': currentDraft.title,
        'amount': currentDraft.amount,
        'category': currentDraft.categoryName,
        'date': currentDraft.date?.toIso8601String(),
      },
      'recentChanges': _changeHistory.take(3).map((change) => {
        'changeType': change.changeType,
        'changedFields': change.changedFields,
        'timestamp': change.timestamp.toIso8601String(),
      }).toList(),
    };
  }

  /// Reset history (misalnya saat sesi baru dimulai)
  void resetHistory() {
    _changeHistory.clear();
  }

  List<String> _identifyChangedFields(
    FfmAssistantDraft original,
    FfmAssistantDraft edited,
  ) {
    final changed = <String>[];
    
    if (original.title != edited.title) changed.add('title');
    if (original.amount != edited.amount) changed.add('amount');
    if (original.categoryName != edited.categoryName) changed.add('category');
    if (original.date != edited.date) changed.add('date');
    if (original.note != edited.note) changed.add('note');
    if (original.formValues['tags'] != edited.formValues['tags']) {
      changed.add('tags');
    }
    if (original.formValues['incomeSource'] != edited.formValues['incomeSource']) {
      changed.add('incomeSource');
    }
    if (original.fromAccountName != edited.fromAccountName) changed.add('fromAccount');
    if (original.toAccountName != edited.toAccountName) changed.add('toAccount');
    if (original.merchantName != edited.merchantName) changed.add('merchant');
    if (original.location != edited.location) changed.add('location');
    if (original.partyName != edited.partyName) changed.add('party');
    if (original.adminFee != edited.adminFee) changed.add('adminFee');
    
    return changed;
  }

  String _determineChangeType(List<String> changedFields) {
    if (changedFields.contains('title')) {
      return 'perubahan nama';
    }
    if (changedFields.contains('amount')) {
      return 'perubahan nominal';
    }
    if (changedFields.contains('category')) {
      return 'perubahan kategori';
    }
    return 'perubahan field lain';
  }
}

class DraftChangeRecord {
  const DraftChangeRecord({
    required this.originalDraft,
    required this.editedDraft,
    required this.changedFields,
    required this.timestamp,
    required this.changeType,
  });

  final FfmAssistantDraft originalDraft;
  final FfmAssistantDraft editedDraft;
  final List<String> changedFields;
  final DateTime timestamp;
  final String changeType;
}
