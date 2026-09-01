import '../domain/ffm_assistant_models.dart';

/// Service untuk melacak perubahan draft dan mengirim feedback ke LLM
/// agar context percakapan tetap konsisten.
class FfmAssistantDraftFeedbackService {
  FfmAssistantDraftFeedbackService();

  final List<DraftChangeRecord> _changeHistory = [];
  static const int _maxHistorySize = 10;

  /// Mencatat perubahan draft saat user mengedit draft
  void recordDraftEdit({
    required FfmAssistantDraft originalDraft,
    required FfmAssistantDraft editedDraft,
    required DateTime timestamp,
  }) {
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
    if (original.fromAccountName != edited.fromAccountName) changed.add('fromAccount');
    if (original.toAccountName != edited.toAccountName) changed.add('toAccount');
    
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
