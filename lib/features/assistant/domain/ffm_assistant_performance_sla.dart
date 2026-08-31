/// Performance SLA (Service Level Agreement) untuk Assistant
/// 
/// Mendefinisikan target performa dan baseline untuk assistant operations
library;

/// Target performa untuk berbagai operasi assistant
class FfmAssistantPerformanceSLA {
  FfmAssistantPerformanceSLA._();

  // Response time targets (in milliseconds)
  static const int simpleQueryTarget = 3000; // 3 seconds for simple queries
  static const int balanceQueryTarget = 5000; // 5 seconds for balance queries
  static const int analysisQueryTarget = 10000; // 10 seconds for analysis queries
  static const int complexQueryTarget = 15000; // 15 seconds for complex queries

  // Component performance targets (in milliseconds)
  static const int databaseQueryP90 = 100; // 90th percentile for database queries
  static const int databaseQueryP99 = 200; // 99th percentile for database queries
  static const int analysisEngineP90 = 500; // 90th percentile for analysis engine
  static const int analysisEngineP99 = 1000; // 99th percentile for analysis engine
  static const int verifiedFactsP90 = 200; // 90th percentile for verified facts
  static const int verifiedFactsP99 = 400; // 99th percentile for verified facts
  static const int geminiCallP90 = 3000; // 90th percentile for Gemini calls
  static const int geminiCallP99 = 5000; // 99th percentile for Gemini calls

  // Overall response time targets
  static const int overallResponseP90 = 5000; // 90th percentile for overall response
  static const int overallResponseP99 = 10000; // 99th percentile for overall response

  // Cache targets
  static const double cacheHitRateTarget = 0.5; // 50% cache hit rate target
  static const double cacheHitRateGood = 0.7; // 70% cache hit rate is good
  static const double cacheHitRateExcellent = 0.85; // 85% cache hit rate is excellent

  // LLM evaluation targets
  static const double factualityScoreTarget = 0.8; // 80% factuality score target
  static const double hallucinationScoreTarget = 0.2; // 20% hallucination score target (lower is better)
  static const double intentFollowingScoreTarget = 0.9; // 90% intent following score target
  static const double overallQualityScoreTarget = 0.8; // 80% overall quality score target

  // Intent classification targets
  static const double intentClassificationAccuracyTarget = 0.9; // 90% accuracy target

  /// Check if simple query response time is within SLA
  static bool isSimpleQueryWithinSLA(Duration duration) {
    return duration.inMilliseconds <= simpleQueryTarget;
  }

  /// Check if balance query response time is within SLA
  static bool isBalanceQueryWithinSLA(Duration duration) {
    return duration.inMilliseconds <= balanceQueryTarget;
  }

  /// Check if analysis query response time is within SLA
  static bool isAnalysisQueryWithinSLA(Duration duration) {
    return duration.inMilliseconds <= analysisQueryTarget;
  }

  /// Check if overall response time is within SLA (p90)
  static bool isOverallResponseWithinSLA(Duration duration) {
    return duration.inMilliseconds <= overallResponseP90;
  }

  /// Check if database query time is within SLA (p90)
  static bool isDatabaseQueryWithinSLA(Duration duration) {
    return duration.inMilliseconds <= databaseQueryP90;
  }

  /// Check if analysis engine time is within SLA (p90)
  static bool isAnalysisEngineWithinSLA(Duration duration) {
    return duration.inMilliseconds <= analysisEngineP90;
  }

  /// Check if verified facts time is within SLA (p90)
  static bool isVerifiedFactsWithinSLA(Duration duration) {
    return duration.inMilliseconds <= verifiedFactsP90;
  }

  /// Check if Gemini call time is within SLA (p90)
  static bool isGeminiCallWithinSLA(Duration duration) {
    return duration.inMilliseconds <= geminiCallP90;
  }

  /// Check if cache hit rate meets target
  static bool isCacheHitRateWithinTarget(double hitRate) {
    return hitRate >= cacheHitRateTarget;
  }

  /// Check if factuality score meets target
  static bool isFactualityScoreWithinTarget(double score) {
    return score >= factualityScoreTarget;
  }

  /// Check if hallucination score meets target
  static bool isHallucinationScoreWithinTarget(double score) {
    return score <= hallucinationScoreTarget;
  }

  /// Check if intent following score meets target
  static bool isIntentFollowingScoreWithinTarget(double score) {
    return score >= intentFollowingScoreTarget;
  }

  /// Check if overall quality score meets target
  static bool isOverallQualityScoreWithinTarget(double score) {
    return score >= overallQualityScoreTarget;
  }

  /// Get performance grade for a metric
  static String getPerformanceGrade(double actual, double target, {bool lowerIsBetter = false}) {
    if (lowerIsBetter) {
      if (actual <= target * 0.8) return 'Excellent';
      if (actual <= target) return 'Good';
      if (actual <= target * 1.2) return 'Fair';
      return 'Poor';
    } else {
      if (actual >= target * 1.2) return 'Excellent';
      if (actual >= target) return 'Good';
      if (actual >= target * 0.8) return 'Fair';
      return 'Poor';
    }
  }

  /// Get performance grade for response time
  static String getResponseTimeGrade(Duration duration, int target) {
    return getPerformanceGrade(
      duration.inMilliseconds.toDouble(),
      target.toDouble(),
      lowerIsBetter: true,
    );
  }

  /// Get performance grade for cache hit rate
  static String getCacheHitRateGrade(double hitRate) {
    return getPerformanceGrade(
      hitRate,
      cacheHitRateTarget,
      lowerIsBetter: false,
    );
  }

  /// Get performance grade for evaluation score
  static String getEvaluationScoreGrade(double score, double target) {
    return getPerformanceGrade(
      score,
      target,
      lowerIsBetter: false,
    );
  }
}
