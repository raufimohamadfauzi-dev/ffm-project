enum GeminiDiagnosticLevel { info, success, warning, error }

class GeminiDiagnosticCodes {
  const GeminiDiagnosticCodes._();

  static const keyEmpty = 'GEM-KEY-000';
  static const keyChanged = 'GEM-KEY-001';
  static const keyReady = 'GEM-KEY-200';
  static const modelsRequest = 'GEM-MODEL-100';
  static const modelsSuccess = 'GEM-MODEL-200';
  static const modelsUnavailable = 'GEM-MODEL-204';
  static const modelEmpty = 'GEM-MODEL-000';
  static const modelSelected = 'GEM-MODEL-201';
  static const testRequest = 'GEM-TEST-100';
  static const testPending = 'GEM-TEST-422';
  static const verified = 'GEM-VERIFY-200';
  static const responseEmpty = 'GEM-RESP-204';
  static const responseMalformed = 'GEM-RESP-422';
  static const invalidRequest = 'GEM-REQ-400';
  static const unauthorized = 'GEM-AUTH-401';
  static const forbidden = 'GEM-AUTH-403';
  static const modelNotFound = 'GEM-MODEL-404';
  static const rateLimited = 'GEM-RATE-429';
  static const timeout = 'GEM-NET-408';
  static const network = 'GEM-NET-001';
  static const server = 'GEM-SRV-500';
  static const configMissing = 'GEM-CONFIG-000';
  static const configSaved = 'GEM-CONFIG-200';
  static const configRejected = 'GEM-CONFIG-422';
  static const chatSuccess = 'GEM-CHAT-200';
  static const chatError = 'GEM-CHAT-500';
  static const usageLoaded = 'GEM-CHAT-204';

  static const descriptions = <String, String>{
    keyEmpty: 'API key belum diisi.',
    keyChanged: 'API key berubah; verifikasi sebelumnya dibatalkan.',
    keyReady:
        'API key terisi di form; nilainya tidak ditampilkan atau dicatat.',
    modelsRequest: 'Meminta daftar model untuk API key ini.',
    modelsSuccess: 'Daftar model berhasil diambil dari Gemini.',
    modelsUnavailable: 'Tidak ada model generateContent untuk key ini.',
    modelEmpty: 'Model Gemini belum dipilih.',
    modelSelected: 'Model dipilih; test koneksi masih diperlukan.',
    testRequest: 'Mengirim test generateContent ke model pilihan.',
    testPending: 'Test generateContent belum berhasil dilakukan.',
    verified: 'Test berhasil; model siap dipakai chatbot.',
    responseEmpty: 'Respons Gemini tidak memiliki teks yang dapat dibaca.',
    responseMalformed: 'Respons Gemini bukan JSON yang dapat dibaca.',
    invalidRequest: 'Gemini menolak format atau parameter request.',
    unauthorized: 'API key tidak valid atau ditolak.',
    forbidden: 'API key tidak memiliki izin untuk request ini.',
    modelNotFound: 'Model tidak ditemukan atau tidak tersedia untuk key ini.',
    rateLimited: 'Kuota atau rate limit Gemini tercapai.',
    timeout: 'Request Gemini melewati batas waktu.',
    network: 'Koneksi ke endpoint Gemini gagal.',
    server: 'Layanan Gemini bermasalah sementara.',
    configMissing: 'Konfigurasi Gemini belum lengkap atau belum verified.',
    configSaved: 'Key dan model tersimpan dengan status verified.',
    configRejected:
        'Konfigurasi tersimpan tetapi belum boleh dipakai karena test gagal.',
    chatSuccess: 'Chatbot berhasil menggunakan Gemini.',
    chatError: 'Chatbot mencoba Gemini tetapi request gagal.',
    usageLoaded: 'Metadata pemakaian chatbot terakhir berhasil dibaca.',
  };

  static String descriptionFor(String code) =>
      descriptions[code] ?? 'Kode Gemini tidak dikenal; lihat detail status.';
}

class GeminiDiagnosticEvent {
  const GeminiDiagnosticEvent({
    required this.code,
    required this.message,
    required this.level,
    required this.at,
    this.model,
    this.httpStatus,
    this.latency,
  });

  final String code;
  final String message;
  final GeminiDiagnosticLevel level;
  final DateTime at;
  final String? model;
  final int? httpStatus;
  final Duration? latency;
}
