/// Status anggaran per kategori untuk analisis pergeseran (Rebalance).
class CategoryBudgetStatus {
  const CategoryBudgetStatus({
    required this.categoryName,
    required this.budgetLimit,
    required this.spentAmount,
  });

  final String categoryName;
  final double budgetLimit;
  final double spentAmount;

  /// Persentase anggaran yang telah terpakai (0.0 – 1.0+).
  double get spentPercentage => budgetLimit > 0 ? (spentAmount / budgetLimit) : 0.0;

  /// Sisa anggaran yang belum terpakai (Rupiah).
  double get remainingBudget => (budgetLimit - spentAmount).clamp(0.0, double.infinity);
}

/// Rekomendasi proposal pergeseran dana antar-pos anggaran (Rebalance Proposal).
class RebalanceProposal {
  const RebalanceProposal({
    required this.id,
    required this.sourceCategory,
    required this.targetCategory,
    required this.suggestedAmount,
    required this.reason,
  });

  final String id;

  /// Kategori sumber yang anggarannya masih melimpah.
  final String sourceCategory;

  /// Kategori tujuan yang anggarannya menipis/jebol.
  final String targetCategory;

  /// Nominal dana yang disarankan untuk digeser (Rupiah).
  final double suggestedAmount;

  /// Penjelasan logis mengapa pergeseran ini disarankan.
  final String reason;

  /// Format nominal yang rapi (Rp 150.000).
  String get formattedAmount {
    final n = suggestedAmount.toStringAsFixed(0);
    final buf = StringBuffer();
    int count = 0;
    for (int i = n.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buf.write('.');
      buf.write(n[i]);
      count++;
    }
    return 'Rp ${buf.toString().split('').reversed.join()}';
  }
}

/// Modul pergeseran anggaran adaptif (Smart Envelope Rebalance).
class SmartEnvelopeRebalance {
  const SmartEnvelopeRebalance();

  /// Menganalisis peluang pergeseran dana dari pos melimpah ke pos yang menipis.
  List<RebalanceProposal> analyzeRebalanceOpportunities({
    required List<CategoryBudgetStatus> categoryStatuses,
  }) {
    if (categoryStatuses.length < 2) return const [];

    // Cari kategori tujuan yang hampir habis / melampaui (terpakai >= 85%)
    final targetCategories = categoryStatuses
        .where((c) => c.budgetLimit > 0 && c.spentPercentage >= 0.85)
        .toList()
      ..sort((a, b) => b.spentPercentage.compareTo(a.spentPercentage));

    // Cari kategori sumber yang masih aman (terpakai <= 40% dan sisa > Rp 50.000)
    final sourceCategories = categoryStatuses
        .where((c) => c.budgetLimit > 0 && c.spentPercentage <= 0.40 && c.remainingBudget >= 50000)
        .toList()
      ..sort((a, b) => b.remainingBudget.compareTo(a.remainingBudget));

    if (targetCategories.isEmpty || sourceCategories.isEmpty) return const [];

    final proposals = <RebalanceProposal>[];

    for (final target in targetCategories) {
      if (sourceCategories.isEmpty) break;
      final source = sourceCategories.first;

      // Hitung nominal rebalance yang disarankan (maksimal 50% dari sisa pos sumber)
      final neededForTarget = (target.spentAmount - target.budgetLimit) > 0
          ? (target.spentAmount - target.budgetLimit) + (target.budgetLimit * 0.15)
          : (target.budgetLimit * 0.20);

      final availableFromSource = source.remainingBudget * 0.50;
      final rebalanceAmount = _roundToThousands(
        neededForTarget < availableFromSource ? neededForTarget : availableFromSource,
      );

      if (rebalanceAmount >= 10000) {
        final targetPctStr = (target.spentPercentage * 100).toStringAsFixed(0);
        final sourcePctStr = (source.spentPercentage * 100).toStringAsFixed(0);

        proposals.add(RebalanceProposal(
          id: 'rebalance_${DateTime.now().millisecondsSinceEpoch}_${target.categoryName}',
          sourceCategory: source.categoryName,
          targetCategory: target.categoryName,
          suggestedAmount: rebalanceAmount,
          reason: 'Anggaran ${target.categoryName} sudah terpakai $targetPctStr%, sedangkan ${source.categoryName} baru terpakai $sourcePctStr%.',
        ));
      }
    }

    return proposals;
  }

  double _roundToThousands(double amount) {
    return (amount / 1000.0).round() * 1000.0;
  }
}
