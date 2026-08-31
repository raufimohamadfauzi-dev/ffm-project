import 'package:flutter/material.dart';

import '../../domain/ffm_assistant_feedback.dart';

class FfmAssistantFeedbackDialog extends StatefulWidget {
  const FfmAssistantFeedbackDialog({
    super.key,
    required this.feedbackType,
    required this.userQuery,
    required this.assistantResponse,
  });

  final FfmAssistantFeedbackType feedbackType;
  final String userQuery;
  final String assistantResponse;

  @override
  State<FfmAssistantFeedbackDialog> createState() =>
      _FfmAssistantFeedbackDialogState();
}

class _FfmAssistantFeedbackDialogState
    extends State<FfmAssistantFeedbackDialog> {
  FfmAssistantFeedbackCategory? _selectedCategory;
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _correctionController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    _correctionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      title: Text(_getDialogTitle()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.feedbackType == FfmAssistantFeedbackType.thumbsDown ||
                widget.feedbackType == FfmAssistantFeedbackType.incorrect ||
                widget.feedbackType == FfmAssistantFeedbackType.issue) ...[
              const Text(
                'Kategori feedback:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: FfmAssistantFeedbackCategory.values
                    .where((cat) => _isValidCategory(cat))
                    .map((category) => ChoiceChip(
                          label: Text(_getCategoryLabel(category)),
                          selected: _selectedCategory == category,
                          onSelected: (selected) {
                            setState(() {
                              _selectedCategory = selected ? category : null;
                            });
                          },
                          selectedColor: isDark
                              ? const Color(0xFF4CAF50).withValues(alpha: 0.3)
                              : const Color(0xFF4CAF50).withValues(alpha: 0.2),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],
            const Text(
              'Catatan tambahan (opsional):',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Jelaskan lebih detail...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
              ),
            ),
            if (widget.feedbackType == FfmAssistantFeedbackType.correction) ...[
              const SizedBox(height: 16),
              const Text(
                'Koreksi yang benar:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _correctionController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Tulis jawaban yang benar...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: () {
            if (widget.feedbackType == FfmAssistantFeedbackType.thumbsUp) {
              Navigator.of(context).pop({
                'type': widget.feedbackType,
                'category': FfmAssistantFeedbackCategory.helpful,
                'note': _noteController.text.trim(),
              });
            } else if (_selectedCategory != null) {
              Navigator.of(context).pop({
                'type': widget.feedbackType,
                'category': _selectedCategory,
                'note': _noteController.text.trim(),
                'correction': widget.feedbackType == FfmAssistantFeedbackType.correction
                    ? _correctionController.text.trim()
                    : null,
              });
            }
          },
          child: const Text('Kirim'),
        ),
      ],
    );
  }

  String _getDialogTitle() {
    switch (widget.feedbackType) {
      case FfmAssistantFeedbackType.thumbsUp:
        return 'Feedback: Berguna';
      case FfmAssistantFeedbackType.thumbsDown:
        return 'Feedback: Tidak Berguna';
      case FfmAssistantFeedbackType.incorrect:
        return 'Feedback: Jawaban Salah';
      case FfmAssistantFeedbackType.issue:
        return 'Lapor Masalah';
      case FfmAssistantFeedbackType.correction:
        return 'Koreksi Jawaban';
    }
  }

  String _getCategoryLabel(FfmAssistantFeedbackCategory category) {
    switch (category) {
      case FfmAssistantFeedbackCategory.factual:
        return 'Fakta salah';
      case FfmAssistantFeedbackCategory.confusing:
        return 'Membingungkan';
      case FfmAssistantFeedbackCategory.helpful:
        return 'Berguna';
      case FfmAssistantFeedbackCategory.hallucination:
        return 'Hallusinasi';
      case FfmAssistantFeedbackCategory.missingContext:
        return 'Kurang konteks';
      case FfmAssistantFeedbackCategory.other:
        return 'Lainnya';
    }
  }

  bool _isValidCategory(FfmAssistantFeedbackCategory category) {
    switch (widget.feedbackType) {
      case FfmAssistantFeedbackType.thumbsUp:
        return category == FfmAssistantFeedbackCategory.helpful;
      case FfmAssistantFeedbackType.thumbsDown:
      case FfmAssistantFeedbackType.incorrect:
      case FfmAssistantFeedbackType.issue:
        return category != FfmAssistantFeedbackCategory.helpful;
      case FfmAssistantFeedbackType.correction:
        return category == FfmAssistantFeedbackCategory.factual ||
               category == FfmAssistantFeedbackCategory.hallucination ||
               category == FfmAssistantFeedbackCategory.other;
    }
  }
}
