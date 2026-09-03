import 'ffm_assistant_models.dart';

/// Kontrak action tool Asisten. Tool hanya boleh membentuk rancangan yang akan
/// diperiksa validator FFM; tool ini tidak mengimpor repository atau use case
/// penyimpanan.
abstract class FfmAssistantActionTool {
  String get name;
  FfmAssistantDraftKind get draftKind;

  Future<FfmAssistantDraft?> buildDraft({
    required String input,
    required FfmAssistantDestination? activePage,
    required Map<String, String> resolvedFields,
  });
}

/// Registry aksi ringan untuk perintah yang sengaja memakai konteks halaman,
/// misalnya “tambah ini di sini” saat pengguna sedang berada di halaman Aset.
/// Bila konteks atau maksud tidak cukup, ia mengembalikan null agar interpreter
/// melanjutkan ke klarifikasi normal dan tidak menebak.
class FfmAssistantContextualActionRegistry {
  FfmAssistantContextualActionRegistry({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  Future<FfmAssistantDraft?> buildDraft({
    required String input,
    required FfmAssistantDestination? activePage,
    Map<String, String> resolvedFields = const <String, String>{},
  }) async {
    final target = _targetFor(activePage);
    if (target == null || !_looksLikeAddCommand(input)) return null;
    if (_mentionsDifferentTarget(input, activePage)) return null;
    return _ContextualDraftTool(target, _clock).buildDraft(
      input: input,
      activePage: activePage,
      resolvedFields: resolvedFields,
    );
  }

  FfmAssistantDraftKind? _targetFor(FfmAssistantDestination? destination) =>
      switch (destination) {
        FfmAssistantDestination.assets => FfmAssistantDraftKind.asset,
        FfmAssistantDestination.goals => FfmAssistantDraftKind.goal,
        FfmAssistantDestination.liabilities => FfmAssistantDraftKind.liability,
        FfmAssistantDestination.activity => FfmAssistantDraftKind.activity,
        FfmAssistantDestination.reminders => FfmAssistantDraftKind.reminder,
        FfmAssistantDestination.budget => FfmAssistantDraftKind.budget,
        FfmAssistantDestination.masterData => FfmAssistantDraftKind.masterData,
        _ => null,
      };

  bool _looksLikeAddCommand(String input) =>
      RegExp(r'\b(tambah|buat|catat)\b', caseSensitive: false).hasMatch(input);

  bool _mentionsDifferentTarget(
    String input,
    FfmAssistantDestination? activePage,
  ) {
    final normalized = input.toLowerCase();
    const destinationWords = <FfmAssistantDestination, List<String>>{
      FfmAssistantDestination.assets: ['aset'],
      FfmAssistantDestination.goals: ['target', 'tujuan'],
      FfmAssistantDestination.liabilities: ['hutang', 'piutang'],
      FfmAssistantDestination.activity: ['aktivitas', 'kegiatan'],
      FfmAssistantDestination.reminders: ['pengingat'],
      FfmAssistantDestination.budget: ['anggaran'],
      FfmAssistantDestination.masterData: [
        'rekening',
        'kategori',
        'data utama',
      ],
      FfmAssistantDestination.transactions: [
        'pemasukan',
        'pengeluaran',
        'uang masuk',
        'uang keluar',
        'transfer',
        'transaksi',
        'belanja',
      ],
    };
    for (final entry in destinationWords.entries) {
      if (entry.key != activePage &&
          entry.value.any((word) => normalized.contains(word))) {
        return true;
      }
    }
    return false;
  }
}

class _ContextualDraftTool implements FfmAssistantActionTool {
  _ContextualDraftTool(this.draftKind, this._clock);

  @override
  final FfmAssistantDraftKind draftKind;
  final DateTime Function() _clock;

  @override
  String get name => 'draft_${draftKind.name}_dari_konteks';

  @override
  Future<FfmAssistantDraft?> buildDraft({
    required String input,
    required FfmAssistantDestination? activePage,
    required Map<String, String> resolvedFields,
  }) async {
    final title = _extractTitle(input);
    return FfmAssistantDraft(
      kind: draftKind,
      createdAt: _clock(),
      title: resolvedFields['title'] ?? title,
      note: resolvedFields['note'],
      formValues: resolvedFields,
    );
  }

  String? _extractTitle(String input) {
    var remaining = input
        .replaceFirst(
          RegExp(r'^\s*(tambah|buat|catat)\s+', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(
            r'\b(aset|target|tujuan|hutang|piutang|aktivitas|kegiatan|pengingat|anggaran|rekening|kategori|data utama)\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(r'\b(di sini|disini|ini)\b', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return remaining.isEmpty ? null : remaining;
  }
}
