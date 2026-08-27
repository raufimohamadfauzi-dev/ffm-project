import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ffm_manager/core/network/gemini_service.dart';

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this.handler);

  final Future<http.Response> Function(String method, Uri uri) handler;
  Map<String, String>? lastHeaders;
  Uri? lastUri;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastHeaders = request.headers;
    lastUri = request.url;
    final response = await handler(request.method, request.url);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

void main() {
  test('testConnection hanya sukses jika respons Gemini berisi teks', () async {
    final service = GeminiService(
      client: _FakeHttpClient(
        (method, uri) async => http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'Gemini aktif.'},
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    final result = await service.testConnection(
      apiKey: 'test-key',
      model: 'gemini-2.5-flash',
    );

    expect(result.ok, isTrue);
    expect(result.text, 'Gemini aktif.');
    expect(result.statusCode, 200);
    expect(result.model, 'gemini-2.5-flash');
  });

  test(
    'key ditolak menghasilkan status error dan bukan respons sukses',
    () async {
      final service = GeminiService(
        client: _FakeHttpClient(
          (method, uri) async => http.Response(
            jsonEncode({
              'error': {'message': 'invalid API key'},
            }),
            401,
          ),
        ),
      );

      final result = await service.testConnection(
        apiKey: 'wrong-key',
        model: 'gemini-2.5-flash',
      );

      expect(result.ok, isFalse);
      expect(result.statusCode, 401);
      expect(result.message, contains('ditolak'));
    },
  );

  test('model tidak ditemukan menghasilkan error eksplisit', () async {
    final service = GeminiService(
      client: _FakeHttpClient((method, uri) async => http.Response('{}', 404)),
    );

    final result = await service.testConnection(
      apiKey: 'test-key',
      model: 'model-tidak-ada',
    );

    expect(result.ok, isFalse);
    expect(result.statusCode, 404);
    expect(result.message, contains('tidak ditemukan'));
  });

  test('respons tanpa kandidat teks tidak dianggap valid', () async {
    final service = GeminiService(
      client: _FakeHttpClient(
        (method, uri) async =>
            http.Response(jsonEncode({'candidates': []}), 200),
      ),
    );

    final result = await service.testConnection(
      apiKey: 'test-key',
      model: 'gemini-2.5-flash',
    );

    expect(result.ok, isFalse);
    expect(result.message, contains('tanpa teks'));
  });

  test('model kosong ditolak tanpa default tersembunyi', () async {
    final service = GeminiService();

    final result = await service.testConnection(apiKey: 'test-key', model: '');

    expect(result.ok, isFalse);
    expect(result.model, isEmpty);
    expect(result.message, contains('belum dipilih'));
  });

  test('fetchModels membedakan key invalid dari daftar model kosong', () async {
    final service = GeminiService(
      client: _FakeHttpClient(
        (method, uri) async => http.Response(
          jsonEncode({
            'error': {'message': 'API key not valid'},
          }),
          400,
        ),
      ),
    );

    final result = await service.fetchModels(apiKey: 'wrong-key');

    expect(result.ok, isFalse);
    expect(result.models, isEmpty);
    expect(result.statusCode, 400);
    expect(result.message, contains('API key Gemini ditolak'));
  });

  test(
    'request Gemini memakai header dan tidak menaruh key pada URL',
    () async {
      late _FakeHttpClient client;
      client = _FakeHttpClient(
        (method, uri) async => http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'Gemini aktif.'},
                  ],
                },
              },
            ],
          }),
          200,
        ),
      );
      final service = GeminiService(client: client);

      final result = await service.testConnection(
        apiKey: 'test-key',
        model: 'gemini-2.5-flash',
      );

      expect(result.ok, isTrue);
      expect(client.lastHeaders?['x-goog-api-key'], 'test-key');
      expect(client.lastUri?.query, isEmpty);
    },
  );

  test(
    'listModels hanya mengembalikan model yang mendukung generateContent',
    () async {
      final service = GeminiService(
        client: _FakeHttpClient(
          (method, uri) async => http.Response(
            jsonEncode({
              'models': [
                {
                  'name': 'models/gemini-2.5-flash',
                  'displayName': 'Gemini 2.5 Flash',
                  'supportedGenerationMethods': ['generateContent'],
                },
                {
                  'name': 'models/embedding-001',
                  'displayName': 'Embedding',
                  'supportedGenerationMethods': ['embedContent'],
                },
              ],
            }),
            200,
          ),
        ),
      );

      final models = await service.listModels(apiKey: 'test-key');

      expect(models.map((model) => model.id), ['gemini-2.5-flash']);
      expect(models.single.displayName, 'Gemini 2.5 Flash');
    },
  );
}
