import 'ffm_background_download_service.dart';
import 'ffm_local_model_service.dart';
import 'ffm_staging_status.dart';

enum FfmLocalModelReadinessState {
  ready,
  stagingReady,
  stagingPartial,
  downloadingBackground,
  downloadFailed,
  notInstalled,
}

class FfmLocalModelReadinessInfo {
  const FfmLocalModelReadinessInfo({
    required this.state,
    required this.title,
    required this.message,
    required this.nextStep,
  });

  final FfmLocalModelReadinessState state;
  final String title;
  final String message;
  final String nextStep;

  bool get canUseAssistant => state == FfmLocalModelReadinessState.ready;
}

abstract final class FfmLocalModelReadiness {
  static FfmLocalModelReadinessInfo resolve({
    required FfmLocalModelInfo? model,
    required FfmStagingStatus? staging,
    required List<FfmBackgroundDownloadStatus> backgroundStatuses,
  }) {
    if (model?.isVerified == true) {
      return const FfmLocalModelReadinessInfo(
        state: FfmLocalModelReadinessState.ready,
        title: 'AI lokal siap dipakai',
        message: 'Model sudah terverifikasi di storage privat FFM.',
        nextStep: 'Kembali ke FFM, buka ✨ Asisten, lalu kirim perintah teks untuk dibuatkan proposal.',
      );
    }

    if (staging?.isReadyToCommit == true) {
      return const FfmLocalModelReadinessInfo(
        state: FfmLocalModelReadinessState.stagingReady,
        title: 'File model siap dirakit',
        message: 'Model telah ada di staging, tetapi belum dipasang sebagai SLM aktif.',
        nextStep: 'Tekan “Rakit dan Pasang SLM” untuk verifikasi akhir.',
      );
    }

    if (staging?.isEmpty == false) {
      return const FfmLocalModelReadinessInfo(
        state: FfmLocalModelReadinessState.stagingPartial,
        title: 'Staging belum lengkap',
        message:
            'File model di staging belum lolos pemeriksaan penuh.',
        nextStep:
            'Pilih GGUF model atau tunggu download background selesai.',
      );
    }

    if (backgroundStatuses.any(
      (status) => !status.isComplete && !status.isFailed,
    )) {
      return const FfmLocalModelReadinessInfo(
        state: FfmLocalModelReadinessState.downloadingBackground,
        title: 'Download SLM masih berjalan',
        message: 'Progres lengkap terlihat pada notifikasi perangkat.',
        nextStep: 'Setelah notifikasi selesai, kembali ke halaman ini lalu tekan “Perbarui status”.',
      );
    }

    final failed = backgroundStatuses.where((status) => status.isFailed);
    if (failed.isNotEmpty) {
      return FfmLocalModelReadinessInfo(
        state: FfmLocalModelReadinessState.downloadFailed,
        title: 'Download SLM belum selesai',
        message: failed.first.reason ?? 'Salah satu file model gagal diunduh.',
        nextStep: 'Periksa jaringan lalu pilih unduh ulang atau impor bundle offline.',
      );
    }

    return const FfmLocalModelReadinessInfo(
      state: FfmLocalModelReadinessState.notInstalled,
      title: 'Belum ada model terpasang',
      message: 'Asisten tetap berjalan dengan aturan lokal bawaan.',
      nextStep: 'Pilih unduh dari GitHub, unduh background, atau impor bundle offline.',
    );
  }
}
