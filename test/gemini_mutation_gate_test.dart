import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ffm_manager/core/network/gemini_service.dart';

class _GateFakeClient extends http.BaseClient {
  String? lastBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    lastBody = utf8.decode(body);
    final response = http.Response(
      jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'ok'},
              ],
            },
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

String _instructionFrom(String body) {
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  return ((decoded['system_instruction'] as Map)['parts'] as List).first['text']
      as String;
}

void main() {
  test('cerita transaksi tidak membuka mutation proposal gate', () async {
    final client = _GateFakeClient();
    final service = GeminiService(client: client);

    await service.chat(
      apiKey: 'test-key',
      model: 'gemini-2.5-flash',
      prompt: 'Saya mau beli rumah tahun depan, menurut kamu masuk akal?',
      systemInstruction: 'Kamu adalah assistant FFM.',
    );

    expect(
      _instructionFrom(client.lastBody!),
      contains('MUTATION_PROPOSAL_GATE: DENY'),
    );
  });

  test('fakta historis transaksi tidak membuka mutation proposal gate',
      () async {
    final client = _GateFakeClient();
    final service = GeminiService(client: client);

    await service.chat(
      apiKey: 'test-key',
      model: 'gemini-2.5-flash',
      prompt: 'Saya sudah bayar listrik kemarin.',
      systemInstruction: 'Kamu adalah assistant FFM.',
    );

    expect(
      _instructionFrom(client.lastBody!),
      contains('MUTATION_PROPOSAL_GATE: DENY'),
    );
  });

  test('pertanyaan tentang jual aset tidak membuka mutation proposal gate',
      () async {
    final client = _GateFakeClient();
    final service = GeminiService(client: client);

    await service.chat(
      apiKey: 'test-key',
      model: 'gemini-2.5-flash',
      prompt: 'Menurut kamu, sebaiknya saya jual motor ini?',
      systemInstruction: 'Kamu adalah assistant FFM.',
    );

    expect(
      _instructionFrom(client.lastBody!),
      contains('MUTATION_PROPOSAL_GATE: DENY'),
    );
  });

  test('permintaan catat eksplisit membuka mutation proposal gate', () async {
    final client = _GateFakeClient();
    final service = GeminiService(client: client);

    await service.chat(
      apiKey: 'test-key',
      model: 'gemini-2.5-flash',
      prompt: 'Catat beli makan 25000 sebagai pengeluaran.',
      systemInstruction: 'Kamu adalah assistant FFM.',
    );

    expect(
      _instructionFrom(client.lastBody!),
      contains('MUTATION_PROPOSAL_GATE: ALLOW'),
    );
  });

  test('permintaan tambah eksplisit membuka mutation proposal gate', () async {
    final client = _GateFakeClient();
    final service = GeminiService(client: client);

    await service.chat(
      apiKey: 'test-key',
      model: 'gemini-2.5-flash',
      prompt: 'Tambahkan rekening BCA sebagai akun baru.',
      systemInstruction: 'Kamu adalah assistant FFM.',
    );

    expect(
      _instructionFrom(client.lastBody!),
      contains('MUTATION_PROPOSAL_GATE: ALLOW'),
    );
  });
}
