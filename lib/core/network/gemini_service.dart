import 'dart:convert';

import 'package:http/http.dart' as http;

import 'gemini_diagnostics.dart';
import 'supabase_config.dart';

class GeminiModelOption {
  const GeminiModelOption({required this.id, required this.displayName});
  final String id;
  final String displayName;
}

class GeminiFunctionCall {
  const GeminiFunctionCall({required this.name, required this.args});
  final String name;
  final Map<String, dynamic> args;
}

class GeminiResult {
  const GeminiResult({required this.model, required this.statusCode, required this.message, this.text, this.functionCalls, this.latency, this.diagnosticCode});
  final String model;
  final int? statusCode;
  final String message;
  final String? text;
  final List<GeminiFunctionCall>? functionCalls;
  final Duration? latency;
  final String? diagnosticCode;
  bool get ok => (text != null && text!.trim().isNotEmpty) || (functionCalls != null && functionCalls!.isNotEmpty);
}

class GeminiModelsResult {
  const GeminiModelsResult({required this.models, required this.statusCode, required this.message, this.diagnosticCode});
  final List<GeminiModelOption> models;
  final int? statusCode;
  final String message;
  final String? diagnosticCode;
  bool get ok => models.isNotEmpty;
}

class GeminiService {
  GeminiService({http.Client? client, SupabaseConfig? config}) : _client = client ?? http.Client(), _config = config ?? SupabaseConfig();
  final http.Client _client;
  final SupabaseConfig _config;

  Future<GeminiResult> chat({required String prompt, String? systemInstruction, List<Map<String, String>> history = const [], List<Map<String, dynamic>>? tools, String? apiKey, String? model}) async {
    final key = apiKey ?? await _config.getGeminiKey();
    final selectedModel = (model ?? await _config.getGeminiModel())?.trim() ?? '';
    if (key == null || key.trim().isEmpty) return GeminiResult(model: selectedModel, statusCode: null, message: 'API key Gemini belum diisi.', diagnosticCode: GeminiDiagnosticCodes.keyEmpty);
    if (selectedModel.isEmpty) return const GeminiResult(model: '', statusCode: null, message: 'Model Gemini belum dipilih.', diagnosticCode: GeminiDiagnosticCodes.modelEmpty);
    return _generate(apiKey: key.trim(), model: selectedModel, prompt: prompt, systemInstruction: _hardenSystemInstruction(prompt, systemInstruction), history: history, tools: tools);
  }

  String? _hardenSystemInstruction(String prompt, String? systemInstruction) {
    final base = systemInstruction?.trim();
    if (base == null || base.isEmpty) return base;
    final normalized = prompt.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final explicitMutation = RegExp(r'\b(?:buat|buatkan|tambahkan|tambah|catat|catatkan|masukkan|rekam|simpan|ubah|hapus|arsip|arsipkan|siapkan draft|simpan sebagai)\b').hasMatch(normalized);
    final explicitTransactionRequest = RegExp(r'\b(?:catat|rekam|simpan|masukkan)\s+(?:transaksi|pembelian|belanja|pembayaran|pemasukan|pengeluaran)\b').hasMatch(normalized);
    final proposalAllowed = explicitMutation || explicitTransactionRequest;
    return '$base\n\nMUTATION_PROPOSAL_GATE: ${proposalAllowed ? 'ALLOW' : 'DENY'}. Jika DENY, jangan keluarkan JSON proposal mutasi atau memory teaching proposal. Kata seperti beli, bayar, jual, makan, belanja, atau transfer yang hanya muncul sebagai cerita, rencana, pertanyaan, atau fakta historis bukan izin mutasi. Jika ALLOW, tetap jangan mengklaim data sudah tersimpan; keluarkan proposal JSON hanya untuk permintaan eksplisit dan biarkan Agent melakukan validasi serta konfirmasi.';
  }

  Future<GeminiResult> testConnection({String? apiKey, String? model}) => chat(apiKey: apiKey, model: model, prompt: 'Tes koneksi FFM. Balas tepat: Gemini aktif.', systemInstruction: 'Balas singkat dalam Bahasa Indonesia. Jangan menambahkan informasi lain.');

  Future<GeminiModelsResult> fetchModels({required String apiKey}) async {
    final key = apiKey.trim();
    if (key.isEmpty) return const GeminiModelsResult(models: [], statusCode: null, message: 'API key Gemini belum diisi.', diagnosticCode: GeminiDiagnosticCodes.keyEmpty);
    final uri = Uri.https('generativelanguage.googleapis.com', '/v1beta/models');
    try {
      final response = await _client.get(uri, headers: {'x-goog-api-key': key}).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return GeminiModelsResult(models: const [], statusCode: response.statusCode, message: _statusMessage(response.statusCode, response.body), diagnosticCode: _diagnosticCodeFor(response.statusCode));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['models'] is! List) return const GeminiModelsResult(models: [], statusCode: 200, message: 'Respons daftar model Gemini tidak valid.', diagnosticCode: GeminiDiagnosticCodes.responseMalformed);
      final models = (decoded['models'] as List).whereType<Map<String, dynamic>>().where((model) {
        final methods = model['supportedGenerationMethods'];
        return methods is List && methods.contains('generateContent');
      }).map((model) {
        final name = '${model['name'] ?? ''}';
        final id = name.startsWith('models/') ? name.substring('models/'.length) : name;
        return GeminiModelOption(id: id, displayName: '${model['displayName'] ?? id}');
      }).where((model) => model.id.isNotEmpty).toList(growable: false);
      return GeminiModelsResult(models: models, statusCode: 200, message: models.isEmpty ? 'Tidak ada model Gemini dengan generateContent untuk key ini.' : '${models.length} model Gemini tersedia untuk key ini.', diagnosticCode: models.isEmpty ? GeminiDiagnosticCodes.modelsUnavailable : GeminiDiagnosticCodes.modelsSuccess);
    } on FormatException {
      return const GeminiModelsResult(models: [], statusCode: 200, message: 'Respons daftar model Gemini tidak berformat JSON yang valid.', diagnosticCode: GeminiDiagnosticCodes.responseMalformed);
    } on Object catch (error) {
      final isTimeout = error.toString().toLowerCase().contains('timeout');
      return GeminiModelsResult(models: const [], statusCode: null, message: isTimeout ? 'Request daftar model Gemini timeout setelah 10 detik.' : 'Daftar model Gemini gagal diambil: ${error.runtimeType}.', diagnosticCode: isTimeout ? GeminiDiagnosticCodes.timeout : GeminiDiagnosticCodes.network);
    }
  }

  Future<List<GeminiModelOption>> listModels({required String apiKey}) async => (await fetchModels(apiKey: apiKey)).models;

  Future<GeminiResult> _generate({required String apiKey, required String model, required String prompt, required String? systemInstruction, required List<Map<String, String>> history, List<Map<String, dynamic>>? tools}) async {
    final url = Uri.https('generativelanguage.googleapis.com', '/v1beta/models/$model:generateContent');
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _client.post(url, headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey}, body: jsonEncode({
        if (systemInstruction != null) 'system_instruction': {'parts': [{'text': systemInstruction}]},
        if (tools != null && tools.isNotEmpty) 'tools': tools,
        'contents': [
          ...history.map((item) => {'role': item['role'] == 'user' ? 'user' : 'model', 'parts': [{'text': item['text'] ?? ''}]}),
          {'role': 'user', 'parts': [{'text': prompt}]},
        ],
        'generationConfig': {'temperature': 0.7, 'topK': 40, 'topP': 0.95, 'maxOutputTokens': 1024},
      })).timeout(const Duration(seconds: 15));
      stopwatch.stop();
      if (response.statusCode != 200) return GeminiResult(model: model, statusCode: response.statusCode, message: _statusMessage(response.statusCode, response.body), latency: stopwatch.elapsed, diagnosticCode: _diagnosticCodeFor(response.statusCode));
      
      final (text, functionCalls) = _extractContent(response.body);
      if (text == null && functionCalls == null) return GeminiResult(model: model, statusCode: response.statusCode, message: 'Gemini mengirim respons tanpa teks yang dapat dibaca.', latency: stopwatch.elapsed, diagnosticCode: GeminiDiagnosticCodes.responseEmpty);
      
      var finalText = text;
      if (finalText != null && _proposalGateDenied(systemInstruction) && _containsStructuredProposal(finalText)) {
        finalText = 'Aku bisa membantu menjelaskan atau menganalisisnya, tetapi aku tidak membuat rancangan perubahan data dari kalimat ini. Jika memang ingin mengubah data FFM, sebutkan tindakan secara eksplisit, misalnya “catat…”, “tambahkan…”, atau “ubah…”.';
      }
      return GeminiResult(model: model, statusCode: response.statusCode, message: 'Gemini merespons (${stopwatch.elapsedMilliseconds} ms).', text: finalText, functionCalls: functionCalls, latency: stopwatch.elapsed, diagnosticCode: GeminiDiagnosticCodes.chatSuccess);
    } on http.ClientException {
      stopwatch.stop();
      return GeminiResult(model: model, statusCode: null, message: 'Koneksi ke Gemini gagal. Periksa internet atau endpoint API.', latency: stopwatch.elapsed, diagnosticCode: GeminiDiagnosticCodes.network);
    } on FormatException {
      stopwatch.stop();
      return GeminiResult(model: model, statusCode: null, message: 'Respons Gemini tidak berformat JSON yang valid.', latency: stopwatch.elapsed, diagnosticCode: GeminiDiagnosticCodes.responseMalformed);
    } on Exception catch (error) {
      stopwatch.stop();
      final isTimeout = error.toString().toLowerCase().contains('timeout');
      return GeminiResult(model: model, statusCode: null, message: isTimeout ? 'Request Gemini timeout setelah 15 detik.' : 'Request Gemini gagal: ${error.runtimeType}.', latency: stopwatch.elapsed, diagnosticCode: isTimeout ? GeminiDiagnosticCodes.timeout : GeminiDiagnosticCodes.network);
    }
  }

  bool _proposalGateDenied(String? instruction) => instruction?.contains('MUTATION_PROPOSAL_GATE: DENY') ?? false;
  bool _containsStructuredProposal(String text) => text.contains('ffm-assistant-proposal-v1') || RegExp(r'"(?:proposal|clarification)"\s*:').hasMatch(text);

  (String?, List<GeminiFunctionCall>?) _extractContent(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return (null, null);
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) return (null, null);
    final first = candidates.first;
    if (first is! Map<String, dynamic>) return (null, null);
    final content = first['content'];
    if (content is! Map<String, dynamic>) return (null, null);
    final parts = content['parts'];
    if (parts is! List) return (null, null);
    
    final texts = <String>[];
    final functionCalls = <GeminiFunctionCall>[];
    
    for (final part in parts.whereType<Map<String, dynamic>>()) {
      if (part.containsKey('text')) {
        texts.add(part['text']);
      } else if (part.containsKey('functionCall')) {
        final call = part['functionCall'];
        if (call is Map<String, dynamic>) {
          final name = call['name'] as String?;
          final args = call['args'] as Map<String, dynamic>?;
          if (name != null) {
            functionCalls.add(GeminiFunctionCall(name: name, args: args ?? {}));
          }
        }
      }
    }
    
    final finalString = texts.join().trim();
    return (
      finalString.isEmpty ? null : finalString, 
      functionCalls.isEmpty ? null : functionCalls
    );
  }

  String _statusMessage(int statusCode, [String? body]) {
    final lowerBody = body?.toLowerCase() ?? '';
    if (lowerBody.contains('api key not valid') || lowerBody.contains('invalid api key')) return 'Kunci API Gemini tidak valid. Silakan periksa kembali di Pengaturan.';
    return switch (statusCode) {
      400 => 'Permintaan tidak dipahami oleh Gemini (HTTP 400). Coba gunakan kalimat lain.',
      401 || 403 => 'Akses Gemini ditolak. Pastikan Kunci API sudah benar dan memiliki kuota.',
      404 => 'Model Gemini tidak ditemukan. Coba pilih model lain di Pengaturan.',
      429 => 'Batas pemakaian Gemini tercapai untuk saat ini. Silakan coba lagi nanti.',
      >= 500 => 'Layanan Gemini sedang mengalami gangguan teknis. Mohon tunggu beberapa saat.',
      _ => 'Terjadi kendala saat menghubungi Gemini (HTTP $statusCode).',
    };
  }

  String _diagnosticCodeFor(int statusCode) => switch (statusCode) {
    400 => GeminiDiagnosticCodes.invalidRequest,
    401 => GeminiDiagnosticCodes.unauthorized,
    403 => GeminiDiagnosticCodes.forbidden,
    404 => GeminiDiagnosticCodes.modelNotFound,
    429 => GeminiDiagnosticCodes.rateLimited,
    >= 500 => GeminiDiagnosticCodes.server,
    _ => GeminiDiagnosticCodes.chatError,
  };
}
