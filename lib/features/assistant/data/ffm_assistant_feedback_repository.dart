import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../domain/ffm_assistant_feedback.dart';

/// Repository untuk menyimpan feedback assistant
/// 
/// Menggunakan local storage untuk feedback karena ini adalah data sensitif
/// dan tidak perlu sync ke Supabase kecuali untuk analisis agregat.
class FfmAssistantFeedbackRepository {
  FfmAssistantFeedbackRepository({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _feedbackListKey = 'ffm_assistant_feedback_list';
  static const maxFeedbackItems = 500;

  final FlutterSecureStorage _storage;
  final Uuid _uuid = const Uuid();

  /// Simpan feedback baru
  Future<void> saveFeedback(FfmAssistantFeedback feedback) async {
    final feedbackList = await getAllFeedback();
    
    // Tambah feedback baru di awal list
    feedbackList.insert(0, feedback);
    
    // Batasi jumlah feedback
    if (feedbackList.length > maxFeedbackItems) {
      feedbackList.removeRange(maxFeedbackItems, feedbackList.length);
    }
    
    await _storage.write(
      key: _feedbackListKey,
      value: jsonEncode(feedbackList.map((f) => f.toJson()).toList()),
    );
  }

  /// Buat feedback baru dari chat entry
  Future<FfmAssistantFeedback> createFeedback({
    required String householdId,
    required String userQuery,
    required String assistantResponse,
    required FfmAssistantFeedbackType type,
    required FfmAssistantFeedbackCategory category,
    String? correction,
    String? note,
    String? verifiedFacts,
    String? analysisResults,
    String? intentType,
  }) async {
    return FfmAssistantFeedback(
      id: _uuid.v4(),
      householdId: householdId,
      userQuery: userQuery,
      assistantResponse: assistantResponse,
      type: type,
      category: category,
      createdAt: DateTime.now(),
      correction: correction,
      note: note,
      verifiedFacts: verifiedFacts,
      analysisResults: analysisResults,
      intentType: intentType,
    );
  }

  /// Ambil semua feedback
  Future<List<FfmAssistantFeedback>> getAllFeedback() async {
    final data = await _storage.read(key: _feedbackListKey);
    if (data == null || data.trim().isEmpty) return [];

    try {
      final decoded = jsonDecode(data) as List;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((json) => FfmAssistantFeedback.fromJson(json))
          .toList();
    } catch (e) {
      // Jika ada error parsing, return empty list
      return [];
    }
  }

  /// Ambil feedback untuk household tertentu
  Future<List<FfmAssistantFeedback>> getFeedbackForHousehold(
    String householdId,
  ) async {
    final allFeedback = await getAllFeedback();
    return allFeedback
        .where((feedback) => feedback.householdId == householdId)
        .toList();
  }

  /// Ambil feedback berdasarkan tipe
  Future<List<FfmAssistantFeedback>> getFeedbackByType(
    FfmAssistantFeedbackType type,
  ) async {
    final allFeedback = await getAllFeedback();
    return allFeedback
        .where((feedback) => feedback.type == type)
        .toList();
  }

  /// Ambil feedback berdasarkan kategori
  Future<List<FfmAssistantFeedback>> getFeedbackByCategory(
    FfmAssistantFeedbackCategory category,
  ) async {
    final allFeedback = await getAllFeedback();
    return allFeedback
        .where((feedback) => feedback.category == category)
        .toList();
  }

  /// Hapus feedback berdasarkan ID
  Future<void> deleteFeedback(String id) async {
    final feedbackList = await getAllFeedback();
    feedbackList.removeWhere((feedback) => feedback.id == id);
    
    await _storage.write(
      key: _feedbackListKey,
      value: jsonEncode(feedbackList.map((f) => f.toJson()).toList()),
    );
  }

  /// Hapus semua feedback untuk household tertentu
  Future<void> deleteFeedbackForHousehold(String householdId) async {
    final feedbackList = await getAllFeedback();
    feedbackList.removeWhere((feedback) => feedback.householdId == householdId);
    
    await _storage.write(
      key: _feedbackListKey,
      value: jsonEncode(feedbackList.map((f) => f.toJson()).toList()),
    );
  }

  /// Bersihkan feedback lama (opsional - untuk maintenance)
  Future<void> cleanupOldFeedback({Duration maxAge = const Duration(days: 90)}) async {
    final feedbackList = await getAllFeedback();
    final cutoffDate = DateTime.now().subtract(maxAge);
    
    feedbackList.removeWhere((feedback) => feedback.createdAt.isBefore(cutoffDate));
    
    await _storage.write(
      key: _feedbackListKey,
      value: jsonEncode(feedbackList.map((f) => f.toJson()).toList()),
    );
  }

  /// Ambil statistik feedback
  Future<Map<String, int>> getFeedbackStats() async {
    final allFeedback = await getAllFeedback();
    
    final stats = <String, int>{
      'total': allFeedback.length,
      'thumbsUp': 0,
      'thumbsDown': 0,
      'incorrect': 0,
      'issue': 0,
      'correction': 0,
      'factual': 0,
      'confusing': 0,
      'helpful': 0,
      'hallucination': 0,
      'missingContext': 0,
      'other': 0,
    };

    for (final feedback in allFeedback) {
      stats['thumbsUp'] = (stats['thumbsUp'] ?? 0) + 
          (feedback.type == FfmAssistantFeedbackType.thumbsUp ? 1 : 0);
      stats['thumbsDown'] = (stats['thumbsDown'] ?? 0) + 
          (feedback.type == FfmAssistantFeedbackType.thumbsDown ? 1 : 0);
      stats['incorrect'] = (stats['incorrect'] ?? 0) + 
          (feedback.type == FfmAssistantFeedbackType.incorrect ? 1 : 0);
      stats['issue'] = (stats['issue'] ?? 0) + 
          (feedback.type == FfmAssistantFeedbackType.issue ? 1 : 0);
      stats['correction'] = (stats['correction'] ?? 0) + 
          (feedback.type == FfmAssistantFeedbackType.correction ? 1 : 0);
      
      stats['factual'] = (stats['factual'] ?? 0) + 
          (feedback.category == FfmAssistantFeedbackCategory.factual ? 1 : 0);
      stats['confusing'] = (stats['confusing'] ?? 0) + 
          (feedback.category == FfmAssistantFeedbackCategory.confusing ? 1 : 0);
      stats['helpful'] = (stats['helpful'] ?? 0) + 
          (feedback.category == FfmAssistantFeedbackCategory.helpful ? 1 : 0);
      stats['hallucination'] = (stats['hallucination'] ?? 0) + 
          (feedback.category == FfmAssistantFeedbackCategory.hallucination ? 1 : 0);
      stats['missingContext'] = (stats['missingContext'] ?? 0) + 
          (feedback.category == FfmAssistantFeedbackCategory.missingContext ? 1 : 0);
      stats['other'] = (stats['other'] ?? 0) + 
          (feedback.category == FfmAssistantFeedbackCategory.other ? 1 : 0);
    }

    return stats;
  }
}
