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
    if (_isConfirm(text)) {
      return ActivityVoiceIntent(
        rawTranscript: raw,
        normalizedText: text,
        type: ActivityVoiceIntentType.confirm,
        status: ActivityVoiceStatus.preview,
        confidence: 1,
      );
    }
    if (_isCancel(text)) {
      return ActivityVoiceIntent(
        rawTranscript: raw,
        normalizedText: text,
        type: ActivityVoiceIntentType.cancel,
        status: ActivityVoiceStatus.preview,
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
    if (isStart) {
      final childMarker = _findChildMarker(text);
      final title = _extractStartTitle(text, childMarker);
      final parentTitle = childMarker == null
          ? null
          : _cleanTitle(text.substring(childMarker.end));
      final intent = ActivityVoiceIntent(
        rawTranscript: raw,
        normalizedText: text,
        type: parentTitle == null
            ? ActivityVoiceIntentType.start
            : ActivityVoiceIntentType.startChild,
        status: ActivityVoiceStatus.preview,
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
      checkpointLabel: raw,
      confidence: .55,
    );
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
          confidence: .9,
        );
      }
      return intent.copyWith(ambiguityReason: 'Sebutkan nama aktivitasnya ya.');
    }
    final matches = sessions
        .where((session) => _sameTitle(session.title, title))
        .toList(growable: false);
    if (matches.length == 1) {
      return intent.copyWith(
        targetSessionId: matches.single.id,
        targetTitle: matches.single.title,
        confidence: .98,
      );
    }
    if (matches.isEmpty) {
      return intent.copyWith(
        ambiguityReason:
            'Aktivitas $title belum ditemukan yang sedang berjalan.',
      );
    }
    return intent.copyWith(
      ambiguityReason:
          'Ada ${matches.length} aktivitas $title. Pilih kartu yang benar dulu ya.',
    );
  }

  ActivityVoiceIntent _resolveParent(
    ActivityVoiceIntent intent,
    List<ActivitySessionEntity> sessions,
  ) {
    final title = intent.parentTitle;
    if (title == null) return intent;
    final matches = sessions
        .where((session) => _sameTitle(session.title, title))
        .toList(growable: false);
    if (matches.length == 1) {
      return intent.copyWith(
        parentSessionId: matches.single.id,
        parentTitle: matches.single.title,
        confidence: .98,
      );
    }
    return intent.copyWith(
      ambiguityReason: matches.isEmpty
          ? 'Aktivitas induk $title belum ditemukan yang sedang berjalan.'
          : 'Ada beberapa aktivitas induk $title. Pilih yang benar dulu ya.',
    );
  }

  ActivityVoiceIntent _unknown(String raw, String text, String reason) =>
      ActivityVoiceIntent(
        rawTranscript: raw,
        normalizedText: text,
        type: ActivityVoiceIntentType.unknown,
        status: ActivityVoiceStatus.preview,
        ambiguityReason: reason,
      );

  bool _sameTitle(String left, String right) =>
      _normalize(left) == _normalize(right);
}
