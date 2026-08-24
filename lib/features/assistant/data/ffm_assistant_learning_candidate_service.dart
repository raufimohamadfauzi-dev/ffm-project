import 'dart:convert';

import 'ffm_assistant_memory_repository.dart';

class FfmAssistantLearningCandidate {
  const FfmAssistantLearningCandidate({
    required this.id,
    required this.trigger,
    required this.workflowJson,
    required this.status,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String trigger;
  final Map<String, Object?> workflowJson;
  final String status;
  final String source;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
}

/// Mengelola kandidat skill/workflow yang dapat di-review user.
/// Kandidat pending tidak pernah dipakai untuk eksekusi sampai disetujui.
class FfmAssistantLearningCandidateService {
  const FfmAssistantLearningCandidateService(this._memories);

  final FfmAssistantMemoryRepository _memories;

  Future<FfmAssistantLearningCandidate> proposeWorkflow({
    required String trigger,
    required List<Map<String, Object?>> steps,
    String source = 'local-observation',
  }) async {
    final safeTrigger = trigger.trim();
    if (safeTrigger.isEmpty || steps.isEmpty) {
      throw ArgumentError('Pemicu dan langkah workflow wajib diisi.');
    }
    final now = DateTime.now();
    final id = 'assistant-workflow-${now.microsecondsSinceEpoch}';
    final workflow = <String, Object?>{
      'version': 1,
      'steps': steps,
      'requiresFinalConfirmation': true,
    };
    final record = await _memories.save(
      id: id,
      kind: 'workflow_candidate',
      triggerText: safeTrigger,
      valueText: jsonEncode(workflow),
      source: source,
      metadata: {
        'scope': 'agent-workflow',
        'approvalStatus': 'pending',
        'requiresReplay': true,
      },
    );
    return _fromRecord(record);
  }

  Future<List<FfmAssistantLearningCandidate>> readPending() async {
    final records = await _memories.readActive(kind: 'workflow_candidate');
    return records
        .where((record) => record.metadata['approvalStatus'] == 'pending')
        .map(_fromRecord)
        .toList(growable: false);
  }

  Future<List<FfmAssistantLearningCandidate>> readApproved() async {
    final records = await _memories.readActive(kind: 'workflow_candidate');
    return records
        .where((record) => record.metadata['approvalStatus'] == 'approved')
        .map(_fromRecord)
        .toList(growable: false);
  }

  Future<FfmAssistantLearningCandidate> approve(
    FfmAssistantLearningCandidate candidate,
  ) async {
    final record = await _memories.save(
      id: candidate.id,
      kind: 'workflow_candidate',
      triggerText: candidate.trigger,
      valueText: jsonEncode(candidate.workflowJson),
      source: candidate.source,
      metadata: {
        'scope': 'agent-workflow',
        'approvalStatus': 'approved',
        'requiresReplay': false,
      },
    );
    return _fromRecord(record);
  }

  Future<void> reject(FfmAssistantLearningCandidate candidate) =>
      _memories.archive(candidate.id);

  FfmAssistantLearningCandidate _fromRecord(FfmAssistantMemoryRecord record) {
    Map<String, Object?> workflow = const {};
    try {
      final decoded = jsonDecode(record.valueText);
      if (decoded is Map) {
        workflow = decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } on FormatException {
      workflow = const {};
    }
    return FfmAssistantLearningCandidate(
      id: record.id,
      trigger: record.triggerText,
      workflowJson: workflow,
      status: record.metadata['approvalStatus']?.toString() ?? 'pending',
      source: record.source,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    );
  }
}
