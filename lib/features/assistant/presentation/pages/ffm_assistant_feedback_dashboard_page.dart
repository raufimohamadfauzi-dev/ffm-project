import 'package:flutter/material.dart';

import '../../data/ffm_assistant_feedback_repository.dart';
import '../../domain/ffm_assistant_feedback.dart';

class FfmAssistantFeedbackDashboardPage extends StatefulWidget {
  const FfmAssistantFeedbackDashboardPage({super.key});

  @override
  State<FfmAssistantFeedbackDashboardPage> createState() =>
      _FfmAssistantFeedbackDashboardPageState();
}

class _FfmAssistantFeedbackDashboardPageState
    extends State<FfmAssistantFeedbackDashboardPage> {
  final FfmAssistantFeedbackRepository _feedbackRepository =
      FfmAssistantFeedbackRepository();
  Map<String, int>? _stats;
  List<FfmAssistantFeedback>? _allFeedback;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    final stats = await _feedbackRepository.getFeedbackStats();
    final feedback = await _feedbackRepository.getAllFeedback();
    
    setState(() {
      _stats = stats;
      _allFeedback = feedback;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard Feedback Assistant'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatsCard(isDark),
                  const SizedBox(height: 24),
                  _buildTypeBreakdown(isDark),
                  const SizedBox(height: 24),
                  _buildCategoryBreakdown(isDark),
                  const SizedBox(height: 24),
                  _buildRecentFeedback(isDark),
                ],
              ),
            ),
    );
  }

  Widget _buildStatsCard(bool isDark) {
    if (_stats == null) return const SizedBox.shrink();

    return Card(
      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Statistik Feedback',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildStatItem('Total', _stats!['total']?.toString() ?? '0'),
                const SizedBox(width: 16),
                _buildStatItem('Berguna', _stats!['thumbsUp']?.toString() ?? '0'),
                const SizedBox(width: 16),
                _buildStatItem('Tidak Berguna', _stats!['thumbsDown']?.toString() ?? '0'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStatItem('Salah', _stats!['incorrect']?.toString() ?? '0'),
                const SizedBox(width: 16),
                _buildStatItem('Lapor', _stats!['issue']?.toString() ?? '0'),
                const SizedBox(width: 16),
                _buildStatItem('Koreksi', _stats!['correction']?.toString() ?? '0'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeBreakdown(bool isDark) {
    if (_stats == null) return const SizedBox.shrink();

    final total = _stats!['total'] ?? 0;
    if (total == 0) {
      return Card(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Belum ada feedback'),
        ),
      );
    }

    return Card(
      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Breakdown Berdasarkan Tipe',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildProgressBar('Berguna', _stats!['thumbsUp']!, total, Colors.green),
            const SizedBox(height: 8),
            _buildProgressBar('Tidak Berguna', _stats!['thumbsDown']!, total, Colors.red),
            const SizedBox(height: 8),
            _buildProgressBar('Salah', _stats!['incorrect']!, total, Colors.orange),
            const SizedBox(height: 8),
            _buildProgressBar('Lapor', _stats!['issue']!, total, Colors.blue),
            const SizedBox(height: 8),
            _buildProgressBar('Koreksi', _stats!['correction']!, total, Colors.purple),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBreakdown(bool isDark) {
    if (_stats == null) return const SizedBox.shrink();

    final total = _stats!['total'] ?? 0;
    if (total == 0) return const SizedBox.shrink();

    return Card(
      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Breakdown Berdasarkan Kategori',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildProgressBar('Fakta Salah', _stats!['factual']!, total, Colors.red),
            const SizedBox(height: 8),
            _buildProgressBar('Membingungkan', _stats!['confusing']!, total, Colors.orange),
            const SizedBox(height: 8),
            _buildProgressBar('Berguna', _stats!['helpful']!, total, Colors.green),
            const SizedBox(height: 8),
            _buildProgressBar('Hallusinasi', _stats!['hallucination']!, total, Colors.purple),
            const SizedBox(height: 8),
            _buildProgressBar('Kurang Konteks', _stats!['missingContext']!, total, Colors.blue),
            const SizedBox(height: 8),
            _buildProgressBar('Lainnya', _stats!['other']!, total, Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar(String label, int value, int total, Color color) {
    final percentage = total > 0 ? (value / total * 100).toStringAsFixed(1) : '0.0';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text('$value ($percentage%)'),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: total > 0 ? value / total : 0,
          color: color,
          backgroundColor: Colors.grey[300],
        ),
      ],
    );
  }

  Widget _buildRecentFeedback(bool isDark) {
    if (_allFeedback == null || _allFeedback!.isEmpty) {
      return Card(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Belum ada feedback'),
        ),
      );
    }

    return Card(
      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Feedback Terbaru',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ..._allFeedback!.take(10).map((feedback) => _buildFeedbackItem(feedback, isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackItem(FfmAssistantFeedback feedback, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildTypeChip(feedback.type),
                const SizedBox(width: 8),
                _buildCategoryChip(feedback.category),
                const Spacer(),
                Text(
                  _formatDate(feedback.createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'User: ${feedback.userQuery}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              'Assistant: ${feedback.assistantResponse}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            if (feedback.note != null && feedback.note!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Catatan: ${feedback.note}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white60 : Colors.black54,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (feedback.correction != null && feedback.correction!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Koreksi: ${feedback.correction}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(FfmAssistantFeedbackType type) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color color;
    String label;
    
    switch (type) {
      case FfmAssistantFeedbackType.thumbsUp:
        color = isDark ? Colors.green.shade200 : Colors.green;
        label = 'Berguna';
        break;
      case FfmAssistantFeedbackType.thumbsDown:
        color = isDark ? Colors.red.shade200 : Colors.red;
        label = 'Tidak Berguna';
        break;
      case FfmAssistantFeedbackType.incorrect:
        color = isDark ? Colors.orange.shade200 : Colors.orange;
        label = 'Salah';
        break;
      case FfmAssistantFeedbackType.issue:
        color = isDark ? Colors.blue.shade200 : Colors.blue;
        label = 'Lapor';
        break;
      case FfmAssistantFeedbackType.correction:
        color = isDark ? Colors.purple.shade200 : Colors.purple;
        label = 'Koreksi';
        break;
    }
    
    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.2),
      labelStyle: TextStyle(color: color, fontSize: 11),
    );
  }

  Widget _buildCategoryChip(FfmAssistantFeedbackCategory category) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color color;
    
    switch (category) {
      case FfmAssistantFeedbackCategory.factual:
        color = isDark ? Colors.red.shade200 : Colors.red;
        break;
      case FfmAssistantFeedbackCategory.confusing:
        color = isDark ? Colors.orange.shade200 : Colors.orange;
        break;
      case FfmAssistantFeedbackCategory.helpful:
        color = isDark ? Colors.green.shade200 : Colors.green;
        break;
      case FfmAssistantFeedbackCategory.hallucination:
        color = isDark ? Colors.purple.shade200 : Colors.purple;
        break;
      case FfmAssistantFeedbackCategory.missingContext:
        color = isDark ? Colors.blue.shade200 : Colors.blue;
        break;
      case FfmAssistantFeedbackCategory.other:
        color = isDark ? Colors.grey.shade300 : Colors.grey;
        break;
    }
    
    return Chip(
      label: Text(category.name),
      backgroundColor: color.withValues(alpha: 0.2),
      labelStyle: TextStyle(color: color, fontSize: 11),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      return 'Hari ini';
    } else if (difference.inDays == 1) {
      return 'Kemarin';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} hari lalu';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
