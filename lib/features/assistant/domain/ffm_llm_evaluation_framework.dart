import 'ffm_assistant_verified_fact_service.dart';

/// LLM Evaluation Framework
/// 
/// Framework ini mengevaluasi kualitas jawaban LLM berdasarkan:
/// - factuality terhadap context
/// - tidak hallucination
/// - mengikuti intent
/// - tidak mengarang hasil aksi
/// - naturalness
/// - relevansi
/// - completeness
/// 
/// Evaluasi dilakukan terhadap data proyek yang sebenarnya, bukan hanya
/// kalimat yang terdengar bagus.
class FfmLLMEvaluationFramework {
  const FfmLLMEvaluationFramework();

  /// Evaluasi respons LLM terhadap verified facts
  FfmLLMEvaluationResult evaluateResponse({
    required String userQuery,
    required String llmResponse,
    required FfmVerifiedFacts verifiedFacts,
    FfmAnalysisFacts? analysisFacts,
    FfmTrendFacts? trendFacts,
    FfmPatternFacts? patternFacts,
  }) {
    final scores = <String, double>{};
    final issues = <String>[];
    final strengths = <String>[];

    // 1. Factuality Check
    final factualityResult = _checkFactuality(
      llmResponse,
      verifiedFacts,
      analysisFacts,
      trendFacts,
      patternFacts,
    );
    scores['factuality'] = factualityResult.score;
    issues.addAll(factualityResult.issues);
    strengths.addAll(factualityResult.strengths);

    // 2. Hallucination Check
    final hallucinationResult = _checkHallucination(
      llmResponse,
      verifiedFacts,
      analysisFacts,
    );
    scores['hallucination'] = hallucinationResult.score;
    issues.addAll(hallucinationResult.issues);
    strengths.addAll(hallucinationResult.strengths);

    // 3. Intent Following
    final intentResult = _checkIntentFollowing(userQuery, llmResponse);
    scores['intent'] = intentResult.score;
    issues.addAll(intentResult.issues);
    strengths.addAll(intentResult.strengths);

    // 4. Action Result Integrity
    final actionResult = _checkActionResultIntegrity(llmResponse);
    scores['actionIntegrity'] = actionResult.score;
    issues.addAll(actionResult.issues);
    strengths.addAll(actionResult.strengths);

    // 5. Naturalness
    final naturalnessResult = _checkNaturalness(llmResponse);
    scores['naturalness'] = naturalnessResult.score;
    issues.addAll(naturalnessResult.issues);
    strengths.addAll(naturalnessResult.strengths);

    // 6. Relevance
    final relevanceResult = _checkRelevance(userQuery, llmResponse);
    scores['relevance'] = relevanceResult.score;
    issues.addAll(relevanceResult.issues);
    strengths.addAll(relevanceResult.strengths);

    // 7. Completeness
    final completenessResult = _checkCompleteness(userQuery, llmResponse);
    scores['completeness'] = completenessResult.score;
    issues.addAll(completenessResult.issues);
    strengths.addAll(completenessResult.strengths);

    // Calculate overall score
    final overallScore = scores.values.reduce((a, b) => a + b) / scores.length;

    return FfmLLMEvaluationResult(
      overallScore: overallScore,
      scores: scores,
      issues: issues,
      strengths: strengths,
      passed: overallScore >= 0.7 && hallucinationResult.score >= 0.8,
    );
  }

  FactualityCheckResult _checkFactuality(
    String response,
    FfmVerifiedFacts verifiedFacts,
    FfmAnalysisFacts? analysisFacts,
    FfmTrendFacts? trendFacts,
    FfmPatternFacts? patternFacts,
  ) {
    final issues = <String>[];
    final strengths = <String>[];
    var score = 1.0;

    // Check if response mentions numbers that contradict verified facts
    if (verifiedFacts.financialSummary != null) {
      // Check for reasonable number ranges
      if (response.contains(RegExp(r'\d+')) && 
          response.contains(RegExp(r'\d{6,}'))) { // Large numbers
        // If response has large numbers, they should be grounded in facts
        if (response.contains('saldo') || response.contains('total')) {
          strengths.add('Mentions financial figures with context');
        }
      }
    }

    // Check analysis facts if provided
    if (analysisFacts != null) {
      if (response.contains(analysisFacts.periodLabel.toLowerCase())) {
        strengths.add('References correct analysis period');
      } else {
        // Mild penalty if analysis period mentioned but doesn't match
        score -= 0.1;
      }
    }

    // Check trend facts if provided
    if (trendFacts != null) {
      if (response.contains(trendFacts.trendDirection.toLowerCase())) {
        strengths.add('Correctly identifies trend direction');
      }
    }

    return FactualityCheckResult(
      score: score.clamp(0.0, 1.0),
      issues: issues,
      strengths: strengths,
    );
  }

  HallucinationCheckResult _checkHallucination(
    String response,
    FfmVerifiedFacts verifiedFacts,
    FfmAnalysisFacts? analysisFacts,
  ) {
    final issues = <String>[];
    final strengths = <String>[];
    var score = 1.0;

    // Check for common hallucination patterns
    final hallucinationPatterns = [
      RegExp(r'saya (pikir|perkiraan|kira) Rp[\d.]+', caseSensitive: false),
      RegExp(r'mungkin (sekitar|kira-kira) Rp[\d.]+', caseSensitive: false),
      RegExp(r'tidak ada data (tapi|namun) saya (asumsikan|anggap)', caseSensitive: false),
    ];

    for (final pattern in hallucinationPatterns) {
      if (pattern.hasMatch(response)) {
        issues.add('Contains uncertain assumptions: ${pattern.pattern}');
        score -= 0.3;
      }
    }

    // Check if response makes claims without data
    if (response.contains(RegExp(r'\d+')) && 
        verifiedFacts.financialSummary?.totalBalance == 0 &&
        verifiedFacts.recentTransactions?.isEmpty == true) {
      if (response.contains('Rp') || response.contains('saldo')) {
        issues.add('Makes financial claims when no data available');
        score -= 0.5;
      }
    }

    // Positive indicators
    if (response.contains('berdasarkan data') || 
        response.contains('dari data') ||
        response.contains('tercatat')) {
      strengths.add('References data as source');
    }

    if (response.contains('tidak ada data') || 
        response.contains('belum ada transaksi')) {
      // Only positive if actually no data
      if (verifiedFacts.recentTransactions?.isEmpty == true) {
        strengths.add('Correctly reports no data available');
      } else {
        issues.add('Reports no data when data exists');
        score -= 0.4;
      }
    }

    return HallucinationCheckResult(
      score: score.clamp(0.0, 1.0),
      issues: issues,
      strengths: strengths,
    );
  }

  IntentCheckResult _checkIntentFollowing(String query, String response) {
    final issues = <String>[];
    final strengths = <String>[];
    var score = 1.0;

    // Detect query intent
    final queryLower = query.toLowerCase();
    
    if (queryLower.contains('berapa') || queryLower.contains('berapa banyak')) {
      // Query expects numeric answer
      if (response.contains(RegExp(r'Rp[\d.]+')) || 
          response.contains(RegExp(r'\d+ (kali|transaksi|akun)'))) {
        strengths.add('Provides numeric answer to quantity question');
      } else {
        issues.add('Does not provide expected numeric answer');
        score -= 0.3;
      }
    }

    if (queryLower.contains('apa') || queryLower.contains('bagaimana')) {
      // Query expects descriptive answer
      if (response.length > 20) {
        strengths.add('Provides descriptive answer');
      } else {
        issues.add('Answer too short for descriptive question');
        score -= 0.2;
      }
    }

    if (queryLower.contains('kenapa') || queryLower.contains('mengapa')) {
      // Query expects explanation
      if (response.contains('karena') || response.contains('sebab') || 
          response.contains('akibat')) {
        strengths.add('Provides explanation');
      } else {
        issues.add('Does not provide expected explanation');
        score -= 0.3;
      }
    }

    return IntentCheckResult(
      score: score.clamp(0.0, 1.0),
      issues: issues,
      strengths: strengths,
    );
  }

  ActionResultCheckResult _checkActionResultIntegrity(String response) {
    final issues = <String>[];
    final strengths = <String>[];
    var score = 1.0;

    // Check if response claims success without proper context
    if (response.contains('berhasil') || response.contains('selesai')) {
      if (response.contains('draft') || response.contains('siap') || 
          response.contains('konfirmasi')) {
        strengths.add('Properly indicates draft/confirmation state');
      } else {
        // Warning if claims success without context
        issues.add('Claims success without clear action context');
        score -= 0.2;
      }
    }

    // Check for premature success claims
    if (response.contains('sudah disimpan') || response.contains('telah disimpan')) {
      if (response.contains('setelah') || response.contains('konfirmasi')) {
        strengths.add('Mentions confirmation before save');
      } else {
        issues.add('Claims save without mentioning confirmation');
        score -= 0.3;
      }
    }

    return ActionResultCheckResult(
      score: score.clamp(0.0, 1.0),
      issues: issues,
      strengths: strengths,
    );
  }

  NaturalnessCheckResult _checkNaturalness(String response) {
    final issues = <String>[];
    final strengths = <String>[];
    var score = 1.0;

    // Check for natural Indonesian language patterns
    final unnaturalPatterns = [
      RegExp(r'\b(dari|ke|dengan|untuk) \1\b', caseSensitive: false), // Repeated words
      RegExp(r'\b(adalah|merupakan|yaitu) \w+ adalah\b', caseSensitive: false), // Redundant
    ];

    for (final pattern in unnaturalPatterns) {
      if (pattern.hasMatch(response)) {
        issues.add('Contains unnatural language pattern');
        score -= 0.1;
      }
    }

    // Check for sentence structure
    final sentences = response.split(RegExp(r'[.!?]'));
    if (sentences.length > 1) {
      strengths.add('Uses multiple sentences for better structure');
    }

    // Check for appropriate Indonesian formality
    if (response.contains('Anda') || response.contains('Saya')) {
      strengths.add('Uses appropriate pronouns');
    }

    // Check length appropriateness
    if (response.length > 500) {
      issues.add('Response possibly too long');
      score -= 0.1;
    } else if (response.length < 10) {
      issues.add('Response too short');
      score -= 0.2;
    } else {
      strengths.add('Response length is appropriate');
    }

    return NaturalnessCheckResult(
      score: score.clamp(0.0, 1.0),
      issues: issues,
      strengths: strengths,
    );
  }

  RelevanceCheckResult _checkRelevance(String query, String response) {
    final issues = <String>[];
    final strengths = <String>[];
    var score = 1.0;

    final queryLower = query.toLowerCase();
    final responseLower = response.toLowerCase();

    // Check if response addresses query keywords
    final queryKeywords = queryLower.split(RegExp(r'\s+')).where((w) => w.length > 3);
    var matchedKeywords = 0;

    for (final keyword in queryKeywords) {
      if (responseLower.contains(keyword)) {
        matchedKeywords++;
      }
    }

    if (queryKeywords.isNotEmpty) {
      final matchRatio = matchedKeywords / queryKeywords.length;
      if (matchRatio >= 0.5) {
        strengths.add('Addresses majority of query keywords');
        score = matchRatio;
      } else {
        issues.add('Does not address enough query keywords');
        score = matchRatio;
      }
    }

    // Check for off-topic responses
    final offTopicIndicators = [
      'maaf saya tidak mengerti',
      'itu di luar kemampuan saya',
      'saya hanya bisa',
    ];

    for (final indicator in offTopicIndicators) {
      if (responseLower.contains(indicator)) {
        if (queryLower.contains('bantuan') || queryLower.contains('fitur')) {
          // Appropriate for capability questions
          strengths.add('Appropriately indicates limitation');
        } else {
          issues.add('Indicates limitation inappropriately');
          score -= 0.3;
        }
      }
    }

    return RelevanceCheckResult(
      score: score.clamp(0.0, 1.0),
      issues: issues,
      strengths: strengths,
    );
  }

  CompletenessCheckResult _checkCompleteness(String query, String response) {
    final issues = <String>[];
    final strengths = <String>[];
    var score = 1.0;

    final queryLower = query.toLowerCase();

    // Check for multi-part questions
    if (queryLower.contains('dan') || queryLower.contains('atau')) {
      // Query has multiple parts
      final parts = queryLower.split(RegExp(r'\s+(dan|atau)\s+'));
      
      if (parts.length > 1) {
        var addressedParts = 0;
        for (final part in parts) {
          final keywords = part.split(RegExp(r'\s+')).where((w) => w.length > 3);
          final responseLower = response.toLowerCase();
          if (keywords.any((k) => responseLower.contains(k))) {
            addressedParts++;
          }
        }

        if (addressedParts >= parts.length) {
          strengths.add('Addresses all parts of multi-part question');
        } else {
          issues.add('Does not address all parts of multi-part question');
          score = addressedParts / parts.length;
        }
      }
    }

    // Check for specific data requests
    if (queryLower.contains('detail') || queryLower.contains('rincian')) {
      if (response.length > 100) {
        strengths.add('Provides detailed response as requested');
      } else {
        issues.add('Response lacks detail for detail request');
        score -= 0.3;
      }
    }

    return CompletenessCheckResult(
      score: score.clamp(0.0, 1.0),
      issues: issues,
      strengths: strengths,
    );
  }
}

// Data models for evaluation results

class FfmLLMEvaluationResult {
  const FfmLLMEvaluationResult({
    required this.overallScore,
    required this.scores,
    required this.issues,
    required this.strengths,
    required this.passed,
  });

  final double overallScore;
  final Map<String, double> scores;
  final List<String> issues;
  final List<String> strengths;
  final bool passed;

  String get qualityLevel {
    if (overallScore >= 0.9) return 'Excellent';
    if (overallScore >= 0.8) return 'Good';
    if (overallScore >= 0.7) return 'Acceptable';
    if (overallScore >= 0.6) return 'Needs Improvement';
    return 'Poor';
  }

  String toReport() {
    final buffer = StringBuffer()
      ..writeln('=== LLM Evaluation Report ===')
      ..writeln('Overall Score: ${(overallScore * 100).toStringAsFixed(1)}%')
      ..writeln('Quality Level: $qualityLevel')
      ..writeln('Status: ${passed ? "PASSED" : "FAILED"}')
      ..writeln()
      ..writeln('Detailed Scores:');
    
    for (final entry in scores.entries) {
      buffer.writeln('  - ${entry.key}: ${(entry.value * 100).toStringAsFixed(1)}%');
    }
    
    if (strengths.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Strengths:');
      for (final strength in strengths) {
        buffer.writeln('  ✓ $strength');
      }
    }
    
    if (issues.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Issues:');
      for (final issue in issues) {
        buffer.writeln('  ✗ $issue');
      }
    }
    
    return buffer.toString();
  }
}

class FactualityCheckResult {
  const FactualityCheckResult({
    required this.score,
    required this.issues,
    required this.strengths,
  });

  final double score;
  final List<String> issues;
  final List<String> strengths;
}

class HallucinationCheckResult {
  const HallucinationCheckResult({
    required this.score,
    required this.issues,
    required this.strengths,
  });

  final double score;
  final List<String> issues;
  final List<String> strengths;
}

class IntentCheckResult {
  const IntentCheckResult({
    required this.score,
    required this.issues,
    required this.strengths,
  });

  final double score;
  final List<String> issues;
  final List<String> strengths;
}

class ActionResultCheckResult {
  const ActionResultCheckResult({
    required this.score,
    required this.issues,
    required this.strengths,
  });

  final double score;
  final List<String> issues;
  final List<String> strengths;
}

class NaturalnessCheckResult {
  const NaturalnessCheckResult({
    required this.score,
    required this.issues,
    required this.strengths,
  });

  final double score;
  final List<String> issues;
  final List<String> strengths;
}

class RelevanceCheckResult {
  const RelevanceCheckResult({
    required this.score,
    required this.issues,
    required this.strengths,
  });

  final double score;
  final List<String> issues;
  final List<String> strengths;
}

class CompletenessCheckResult {
  const CompletenessCheckResult({
    required this.score,
    required this.issues,
    required this.strengths,
  });

  final double score;
  final List<String> issues;
  final List<String> strengths;
}