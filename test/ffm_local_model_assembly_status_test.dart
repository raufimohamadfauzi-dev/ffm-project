import 'package:flutter_test/flutter_test.dart';
import 'package:ffm_manager/features/assistant/data/ffm_local_model_assembly_status.dart';

void main() {
  test('status rakit menyimpan tahap dan byte progres lintas lifecycle', () {
    final status = FfmLocalModelAssemblyStatus(
      stage: FfmLocalModelAssemblyStage.verifyingProjector,
      updatedAt: DateTime.utc(2026, 8, 24, 1),
      startedAt: DateTime.utc(2026, 8, 24),
      fileName: 'mmproj.gguf',
      processedBytes: 400,
      totalBytes: 1000,
    );

    final restored = FfmLocalModelAssemblyStatus.fromJson(status.toJson());

    expect(restored.stage, FfmLocalModelAssemblyStage.verifyingProjector);
    expect(restored.fileName, 'mmproj.gguf');
    expect(restored.processedBytes, 400);
    expect(restored.totalBytes, 1000);
    expect(restored.fraction, .4);
    expect(restored.isWorking, isTrue);
  });

  test('status gagal mempertahankan detail ringkas dan dapat dipulihkan', () {
    final status = FfmLocalModelAssemblyStatus(
      stage: FfmLocalModelAssemblyStage.failed,
      updatedAt: DateTime.utc(2026, 8, 24, 1),
      errorDetail: 'SHA-256 tidak cocok.',
    );

    final restored = FfmLocalModelAssemblyStatus.fromJson(status.toJson());

    expect(restored.isWorking, isFalse);
    expect(restored.errorDetail, 'SHA-256 tidak cocok.');
  });
}
