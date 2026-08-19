class AssetEntity {
  const AssetEntity({
    required this.id,
    required this.householdId,
    required this.name,
    required this.assetType,
    required this.value,
    required this.placement,
    required this.createdAt,
    this.updatedAt,
    this.note,
    this.isArchived = false,
  });

  final String id;
  final String householdId;
  final String name;
  final String assetType;
  final int value;
  final String placement;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? note;
  final bool isArchived;
}
