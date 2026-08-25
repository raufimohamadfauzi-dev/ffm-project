import 'ffm_assistant_memory_repository.dart';

/// Scope memori tahan lama yang dapat muncul pada context engine dan aman
/// ditampilkan di Pusat Kontrol Memori Personal.
enum FfmPersonalMemoryControlScope {
  userModel,
  personalMemory,
  aliasCorrection,
}

class FfmPersonalMemoryControlItem {
  const FfmPersonalMemoryControlItem({
    required this.id,
    required this.scope,
    required this.label,
    required this.value,
    required this.sourceLabel,
    required this.savedAt,
  });

  final String id;
  final FfmPersonalMemoryControlScope scope;
  final String label;
  final String value;
  final String sourceLabel;
  final DateTime savedAt;
}

/// Satu policy untuk UI kontrol memori. Policy ini tidak mengubah data lama;
/// ia hanya mencegah data sensitif atau non-personal tampil sebagai memori.
abstract final class FfmPersonalMemorySafetyPolicy {
  static const _sensitiveTerms = <String>{
    'pin',
    'password',
    'sandi',
    'otp',
    'token',
    'secret',
    'kunci',
    'saldo',
    'balance',
    'nominal',
    'amount',
    'rekening',
    'account',
    'aset',
    'asset',
    'hutang',
    'piutang',
    'transaksi',
    'transaction',
    'anggaran',
    'budget',
    'draft',
    'path',
    'gambar',
  };

  static bool isSafeForPersonalContext({
    required String key,
    required String value,
  }) {
    final normalized = '${key.trim()} ${value.trim()}'.toLowerCase();
    if (normalized.isEmpty) return false;
    if (_sensitiveTerms.any(normalized.contains)) return false;
    if (RegExp(
      r'\b(?:rp\.?\s*)?\d{4,}\b',
      caseSensitive: false,
    ).hasMatch(normalized)) {
      return false;
    }
    return true;
  }
}

/// Gateway tunggal untuk halaman kontrol memori. Hanya record aktif yang
/// memang eligible bagi context engine dan telah disetujui yang dipulangkan.
class FfmPersonalMemoryControlService {
  const FfmPersonalMemoryControlService(this._repository);

  final FfmAssistantMemoryRepository _repository;

  Future<List<FfmPersonalMemoryControlItem>> readVisible() async {
    final records = await _repository.readActive();
    final visible = <FfmPersonalMemoryControlItem>[];
    for (final record in records) {
      final item = _toItem(record);
      if (item != null) visible.add(item);
    }
    visible.sort((left, right) => right.savedAt.compareTo(left.savedAt));
    return List.unmodifiable(visible);
  }

  Future<void> forget(String id) => _repository.archive(id);

  FfmPersonalMemoryControlItem? _toItem(FfmAssistantMemoryRecord record) {
    final scope = _scopeFor(record);
    if (scope == null) return null;
    if (!FfmPersonalMemorySafetyPolicy.isSafeForPersonalContext(
      key: record.triggerText,
      value: record.valueText,
    )) {
      return null;
    }
    return FfmPersonalMemoryControlItem(
      id: record.id,
      scope: scope,
      label: _labelFor(record, scope),
      value: record.valueText,
      sourceLabel: _sourceLabel(scope),
      savedAt: record.updatedAt ?? record.createdAt,
    );
  }

  FfmPersonalMemoryControlScope? _scopeFor(FfmAssistantMemoryRecord record) {
    final scope = record.metadata['scope'];
    if (scope == 'user-model' && record.metadata['approved'] != false) {
      return FfmPersonalMemoryControlScope.userModel;
    }
    if (scope == 'personal-memory' && record.metadata['approved'] != false) {
      return FfmPersonalMemoryControlScope.personalMemory;
    }
    if (record.kind == 'alias') {
      return FfmPersonalMemoryControlScope.aliasCorrection;
    }
    return null;
  }

  String _labelFor(
    FfmAssistantMemoryRecord record,
    FfmPersonalMemoryControlScope scope,
  ) {
    if (scope == FfmPersonalMemoryControlScope.personalMemory) {
      final humanLabel = record.metadata['humanLabel'];
      if (humanLabel is String && humanLabel.trim().isNotEmpty) {
        return humanLabel.trim();
      }
    }
    return switch (scope) {
      FfmPersonalMemoryControlScope.userModel => record.triggerText,
      FfmPersonalMemoryControlScope.personalMemory => record.triggerText,
      FfmPersonalMemoryControlScope.aliasCorrection =>
        'Koreksi: ${record.triggerText}',
    };
  }

  String _sourceLabel(FfmPersonalMemoryControlScope scope) => switch (scope) {
    FfmPersonalMemoryControlScope.userModel => 'Profil yang disetujui',
    FfmPersonalMemoryControlScope.personalMemory => 'Memori yang disetujui',
    FfmPersonalMemoryControlScope.aliasCorrection => 'Alias/koreksi lokal',
  };
}
