import 'entities/activity_entity.dart';

enum ActivityVoiceIntentType {
  start,
  startChild,
  finish,
  checkpoint,
  note,
  confirm,
  cancel,
  unknown,
}

enum ActivityVoiceStatus {
  preview,
  confirmed,
  cancelled,
  rejected,
  failed,
  expired,
}

class ActivityVoiceIntent {
  const ActivityVoiceIntent({
    required this.rawTranscript,
    required this.normalizedText,
    required this.type,
    required this.status,
    this.kind = ActivityKind.timer,
    this.category = 'Lainnya',
    this.targetTitle,
    this.targetSessionId,
    this.parentTitle,
    this.parentSessionId,
    this.checkpointLabel,
    this.confidence = 0,
    this.ambiguityReason,
    this.resultMessage,
  });

  final String rawTranscript;
  final String normalizedText;
  final ActivityVoiceIntentType type;
  final ActivityVoiceStatus status;
  final ActivityKind kind;
  final String category;
  final String? targetTitle;
  final String? targetSessionId;
  final String? parentTitle;
  final String? parentSessionId;
  final String? checkpointLabel;
  final double confidence;
  final String? ambiguityReason;
  final String? resultMessage;

  ActivityVoiceIntent copyWith({
    ActivityVoiceIntentType? type,
    ActivityVoiceStatus? status,
    ActivityKind? kind,
    String? category,
    String? targetTitle,
    String? targetSessionId,
    String? parentTitle,
    String? parentSessionId,
    String? checkpointLabel,
    double? confidence,
    String? ambiguityReason,
    String? resultMessage,
    bool clearAmbiguity = false,
  }) => ActivityVoiceIntent(
    rawTranscript: rawTranscript,
    normalizedText: normalizedText,
    type: type ?? this.type,
    status: status ?? this.status,
    kind: kind ?? this.kind,
    category: category ?? this.category,
    targetTitle: targetTitle ?? this.targetTitle,
    targetSessionId: targetSessionId ?? this.targetSessionId,
    parentTitle: parentTitle ?? this.parentTitle,
    parentSessionId: parentSessionId ?? this.parentSessionId,
    checkpointLabel: checkpointLabel ?? this.checkpointLabel,
    confidence: confidence ?? this.confidence,
    ambiguityReason: clearAmbiguity
        ? null
        : ambiguityReason ?? this.ambiguityReason,
    resultMessage: resultMessage ?? this.resultMessage,
  );

  bool get canConfirm =>
      status == ActivityVoiceStatus.preview &&
      type != ActivityVoiceIntentType.unknown &&
      type != ActivityVoiceIntentType.confirm &&
      type != ActivityVoiceIntentType.cancel &&
      ambiguityReason == null;

  String get actionLabel => switch (type) {
    ActivityVoiceIntentType.start => 'Mulai aktivitas',
    ActivityVoiceIntentType.startChild => 'Mulai aktivitas di dalam',
    ActivityVoiceIntentType.finish => 'Selesaikan aktivitas',
    ActivityVoiceIntentType.checkpoint => 'Tambah update aktivitas',
    ActivityVoiceIntentType.note => 'Catat aktivitas',
    ActivityVoiceIntentType.confirm => 'Konfirmasi',
    ActivityVoiceIntentType.cancel => 'Batal',
    ActivityVoiceIntentType.unknown => 'Belum jelas',
  };
}

class ActivityVoiceParser {
  const ActivityVoiceParser();

  ActivityVoiceIntent parse(
    String transcript, {
    List<ActivitySessionEntity> activeSessions = const [],
  }) {
    final raw = transcript.trim();
    final text = _normalize(raw);
    if (text.isEmpty) {
      return _unknown(raw, text, 'Teksnya masih kosong. Coba ngomong lagi ya.');
    }
    final detectedCategory = _detectCategory(text) ?? 'Lainnya';
    if (_isConfirm(text)) {
      return ActivityVoiceIntent(
        rawTranscript: raw,
        normalizedText: text,
        type: ActivityVoiceIntentType.confirm,
        status: ActivityVoiceStatus.preview,
        category: detectedCategory,
        confidence: 1,
      );
    }
    if (_isCancel(text)) {
      return ActivityVoiceIntent(
        rawTranscript: raw,
        normalizedText: text,
        type: ActivityVoiceIntentType.cancel,
        status: ActivityVoiceStatus.preview,
        category: detectedCategory,
        confidence: 1,
      );
    }

    final isFinish = _containsAny(text, const [
      'selesai',
      'beres',
      'hentikan',
      'stop',
    ]);
    final isStart = _containsAny(text, const [
      'mulai',
      'jalankan',
      'buka aktivitas',
    ]);
    final isCheckpoint = _containsAny(text, const [
      'update',
      'sampai ',
      'tiba ',
      'sudah sampai ',
      'sudah di ',
    ]);
    final isTask = _containsAny(text, const [
      'ingatkan',
      'tugas',
      'perlu ',
      'harus ',
      'nanti ',
    ]);
    final isNote = _containsAny(text, const [
      'catat ',
      'jurnal ',
      'refleksi ',
      'keterangan ',
    ]);

    if (isFinish) {
      final title = _extractFinishTitle(text);
      return _resolveTarget(
        ActivityVoiceIntent(
          rawTranscript: raw,
          normalizedText: text,
          type: ActivityVoiceIntentType.finish,
          status: ActivityVoiceStatus.preview,
          targetTitle: title,
          confidence: title == null ? .45 : .9,
        ),
        activeSessions,
        useSingleActiveFallback: true,
      );
    }
    if (isStart || isTask || isNote) {
      final childMarker = _findChildMarker(text);
      final title = _extractStartTitle(text, childMarker);
      final parentTitle = childMarker == null
          ? null
          : _cleanTitle(text.substring(childMarker.end));
      final kind = isTask
          ? ActivityKind.task
          : isNote
              ? ActivityKind.note
              : ActivityKind.timer;
      final intent = ActivityVoiceIntent(
        rawTranscript: raw,
        normalizedText: text,
        type: parentTitle == null
            ? ActivityVoiceIntentType.start
            : ActivityVoiceIntentType.startChild,
        status: ActivityVoiceStatus.preview,
        kind: kind,
        category: detectedCategory,
        targetTitle: title,
        parentTitle: parentTitle,
        confidence: title == null ? .45 : .9,
      );
      return parentTitle == null
          ? intent
          : _resolveParent(intent, activeSessions);
    }
    if (isCheckpoint) {
      final title = _extractCheckpointTarget(text);
      final label = _extractCheckpointLabel(text);
      return _resolveTarget(
        ActivityVoiceIntent(
          rawTranscript: raw,
          normalizedText: text,
          type: ActivityVoiceIntentType.checkpoint,
          status: ActivityVoiceStatus.preview,
          category: detectedCategory,
          targetTitle: title,
          checkpointLabel: label,
          confidence: title == null || label == null ? .45 : .85,
        ),
        activeSessions,
        useSingleActiveFallback: true,
      );
    }

    return ActivityVoiceIntent(
      rawTranscript: raw,
      normalizedText: text,
      type: ActivityVoiceIntentType.note,
      status: ActivityVoiceStatus.preview,
      category: detectedCategory,
      checkpointLabel: raw,
      confidence: .55,
    );
  }

  String? _detectCategory(String text) {
    if (_containsAny(text, const ['belanja', 'beli', 'shop', 'pasar'])) {
      return 'Belanja';
    }
    if (_containsAny(text, const ['perjalanan', 'travel', 'jalan', 'bepergian'])) {
      return 'Perjalanan';
    }
    if (_containsAny(text, const ['kerja', 'pekerjaan', 'task', 'tugas'])) {
      return 'Pekerjaan';
    }
    if (_containsAny(text, const ['keluarga', 'rumah', 'anak', 'suami', 'istri'])) {
      return 'Keluarga';
    }
    if (_containsAny(text, const ['kategori', 'kelas'])) {
      final match = RegExp(r'kategori\s+([a-z0-9\s]+)').firstMatch(text);
      if (match != null) {
        final candidate = match.group(1)?.trim();
        if (candidate != null && candidate.isNotEmpty) {
          return candidate[0].toUpperCase() + candidate.substring(1);
        }
      }
    }
    return 'Lainnya';
  }

  ActivityVoiceIntent resolveEdited(
    ActivityVoiceIntent intent,
    List<ActivitySessionEntity> activeSessions,
  ) => parse(intent.rawTranscript, activeSessions: activeSessions);

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool _isConfirm(String text) => _containsToken(text, const [
    'ok',
    'oke',
    'ya',
    'benar',
    'betul',
    'konfirmasi',
  ]);

  bool _isCancel(String text) =>
      _containsToken(text, const ['batal', 'jangan', 'ulang']) ||
      text.contains('tidak jadi');

  bool _containsToken(String text, List<String> words) {
    final tokens = text.split(' ');
    return words.any(tokens.contains);
  }

  bool _containsAny(String text, List<String> words) =>
      words.any((word) => text.contains(word));

  String? _extractFinishTitle(String text) {
    var title = text;
    for (final phrase in const [
      'sudah selesai',
      'telah selesai',
      'sudah beres',
      'telah beres',
      'selesai',
      'beres',
      'hentikan',
      'stop',
    ]) {
      title = title.replaceFirst(phrase, ' ');
    }
    title = title
        .replaceAll(RegExp(r'^(saya|aku|aktivitas|yang)\s+'), '')
        .trim();
    return title.isEmpty ? null : _cleanTitle(title);
  }

  String? _extractStartTitle(String text, RegExpMatch? childMarker) {
    var title = text;
    if (childMarker != null) title = title.substring(0, childMarker.start);
    for (final phrase in const [
      'saya mulai',
      'aku mulai',
      'mulai',
      'jalankan',
      'buka aktivitas',
    ]) {
      title = title.replaceFirst(phrase, ' ');
    }
    title = title.replaceFirst(RegExp(r'^(saya|aku)\s+'), ' ').trim();
    return title.isEmpty ? null : _cleanTitle(title);
  }

  String? _extractCheckpointTarget(String text) {
    if (RegExp(r'^(?:sudah sampai|sampai|tiba|sudah di)\s+').hasMatch(text)) {
      return null;
    }
    final match = RegExp(
      r'^(?:update\s+)?(.+?)\s+(?:sudah sampai|sampai|tiba|sudah di)\s+',
    ).firstMatch(text);
    return match == null ? null : _cleanTitle(match.group(1)!);
  }

  String? _extractCheckpointLabel(String text) {
    final match = RegExp(r'(?:sudah sampai|sampai|tiba|sudah di)\s+(.+)$')
        .firstMatch(text);
    return match == null ? null : _cleanTitle(match.group(1)!);
  }

  RegExpMatch? _findChildMarker(String text) =>
      RegExp(r'\s+(?:di dalam|dalam|sambil di)\s+').firstMatch(text);

  String _cleanTitle(String value) => value
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .split(' ')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');

  ActivityVoiceIntent _resolveTarget(
    ActivityVoiceIntent intent,
    List<ActivitySessionEntity> sessions, {
    bool useSingleActiveFallback = false,
  }) {
    final title = intent.targetTitle;
    if (title == null) {
      if (useSingleActiveFallback && sessions.length == 1) {
        final session = sessions.single;
        return intent.copyWith(
          targetSessionId: session.id,
          targetTitle: session.title,
          confidence: .95,
        );
      }
      if (sessions.length > 1) {
        return intent.copyWith(
          confidence: .65,
          ambiguityReason:
              'Ada ${sessions.length} aktivitas yang masih jalan: ${sessions.map((s) => s.title).join(', ')}. Sebutkan nama aktivitas yang dimaksud ya.',
        );
      }
      return intent.copyWith(
        confidence: .40,
        ambiguityReason: 'Sebutkan nama aktivitasnya ya.',
      );
    }

    final normalizedQuery = _normalize(title);

    // 1. Exact ID matching (if title is an ID)
    final exactIdMatches = sessions.where((s) => s.id == title).toList();
    if (exactIdMatches.isNotEmpty) {
      final match = exactIdMatches.first;
      return intent.copyWith(
        targetSessionId: match.id,
        targetTitle: match.title,
        confidence: 1.0,
      );
    }

    // 2. Exact Title Matches (distinguish child vs root parent)
    final exactMatches = sessions
        .where((s) => _sameTitle(s.title, title))
        .toList(growable: false);

    if (exactMatches.length == 1) {
      final match = exactMatches.single;
      return intent.copyWith(
        targetSessionId: match.id,
        targetTitle: match.title,
        confidence: .98,
      );
    }

    if (exactMatches.length > 1) {
      // If one is child and another is parent, prioritize child for finish
      final childMatches = exactMatches.where((s) => s.parentSessionId != null).toList();
      if (childMatches.length == 1) {
        final match = childMatches.single;
        return intent.copyWith(
          targetSessionId: match.id,
          targetTitle: match.title,
          confidence: .95,
        );
      }
      return intent.copyWith(
        confidence: .70,
        ambiguityReason:
            'Ada ${exactMatches.length} aktivitas bernama "$title". Pilih aktivitas yang dimaksud ya.',
      );
    }

    // 3. Substring / Semantic Matches
    // Prioritize active child sessions first (e.g. "makan" matching "Makan Siang" sub-session)
    final childSemantic = sessions
        .where((s) => s.parentSessionId != null && (_normalize(s.title).contains(normalizedQuery) || normalizedQuery.contains(_normalize(s.title))))
        .toList(growable: false);

    if (childSemantic.length == 1) {
      final match = childSemantic.single;
      return intent.copyWith(
        targetSessionId: match.id,
        targetTitle: match.title,
        confidence: .90,
      );
    }

    final allSemantic = sessions
        .where((s) => _normalize(s.title).contains(normalizedQuery) || normalizedQuery.contains(_normalize(s.title)))
        .toList(growable: false);

    if (allSemantic.length == 1) {
      final match = allSemantic.single;
      return intent.copyWith(
        targetSessionId: match.id,
        targetTitle: match.title,
        confidence: .88,
      );
    }

    if (allSemantic.length > 1) {
      return intent.copyWith(
        confidence: .68,
        ambiguityReason:
            'Ada ${allSemantic.length} aktivitas yang mirip: ${allSemantic.map((s) => s.title).join(', ')}. Pilih yang mana?',
      );
    }

    return intent.copyWith(
      confidence: .40,
      ambiguityReason: 'Aktivitas "$title" belum ditemukan yang sedang berjalan.',
    );
  }

  ActivityVoiceIntent _resolveParent(
    ActivityVoiceIntent intent,
    List<ActivitySessionEntity> sessions,
  ) {
    final title = intent.parentTitle;
    if (title == null) return intent;
    final normalizedQuery = _normalize(title);

    // Exact matches
    final exactMatches = sessions
        .where((s) => _sameTitle(s.title, title))
        .toList(growable: false);
    if (exactMatches.length == 1) {
      return intent.copyWith(
        parentSessionId: exactMatches.single.id,
        parentTitle: exactMatches.single.title,
        confidence: .98,
      );
    }

    // Semantic matches
    final semanticMatches = sessions
        .where((s) => _normalize(s.title).contains(normalizedQuery) || normalizedQuery.contains(_normalize(s.title)))
        .toList(growable: false);
    if (semanticMatches.length == 1) {
      return intent.copyWith(
        parentSessionId: semanticMatches.single.id,
        parentTitle: semanticMatches.single.title,
        confidence: .90,
      );
    }

    return intent.copyWith(
      confidence: .40,
      ambiguityReason: semanticMatches.isEmpty
          ? 'Aktivitas induk "$title" belum ditemukan yang sedang berjalan.'
          : 'Ada beberapa aktivitas induk yang mirip: ${semanticMatches.map((session) => session.title).join(', ')}. Pilih yang benar dulu ya.',
    );
  }

  ActivityVoiceIntent _unknown(String raw, String text, String reason) =>
      ActivityVoiceIntent(
        rawTranscript: raw,
        normalizedText: text,
        type: ActivityVoiceIntentType.unknown,
        status: ActivityVoiceStatus.preview,
        ambiguityReason: reason,
        confidence: .30,
      );

  bool _sameTitle(String left, String right) =>
      _normalize(left) == _normalize(right);
}
