import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ffm_manager/core/network/gemini_diagnostics.dart';
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
    expect(result.diagnosticCode, GeminiDiagnosticCodes.chatSuccess);
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
      expect(result.diagnosticCode, GeminiDiagnosticCodes.unauthorized);
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
    expect(result.diagnosticCode, GeminiDiagnosticCodes.modelNotFound);
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
    expect(result.diagnosticCode, GeminiDiagnosticCodes.responseEmpty);
  });

  test('model kosong ditolak tanpa default tersembunyi', () async {
    final service = GeminiService();

    final result = await service.testConnection(apiKey: 'test-key', model: '');

    expect(result.ok, isFalse);
    expect(result.model, isEmpty);
    expect(result.message, contains('belum dipilih'));
    expect(result.diagnosticCode, GeminiDiagnosticCodes.modelEmpty);
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
    expect(result.diagnosticCode, GeminiDiagnosticCodes.invalidRequest);
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
      expect(result.diagnosticCode, GeminiDiagnosticCodes.chatSuccess);
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

      final modelsResult = await service.fetchModels(apiKey: 'test-key');
      final models = modelsResult.models;

      expect(modelsResult.diagnosticCode, GeminiDiagnosticCodes.modelsSuccess);
      expect(models.map((model) => model.id), ['gemini-2.5-flash']);
      expect(models.single.displayName, 'Gemini 2.5 Flash');
    },
  );

  test('status HTTP penting dipetakan ke kode diagnostik', () async {
    final expected = <int, String>{
      400: GeminiDiagnosticCodes.invalidRequest,
      401: GeminiDiagnosticCodes.unauthorized,
      403: GeminiDiagnosticCodes.forbidden,
      404: GeminiDiagnosticCodes.modelNotFound,
      429: GeminiDiagnosticCodes.rateLimited,
      500: GeminiDiagnosticCodes.server,
      503: GeminiDiagnosticCodes.server,
    };
    for (final entry in expected.entries) {
      final service = GeminiService(
        client: _FakeHttpClient(
          (method, uri) async => http.Response('{}', entry.key),
        ),
      );
      final result = await service.testConnection(
        apiKey: 'test-key',
        model: 'gemini-2.5-flash',
      );
      expect(result.diagnosticCode, entry.value, reason: 'HTTP ${entry.key}');
    }
  });

  test('respons JSON malformed menghasilkan kode respons malformed', () async {
    final service = GeminiService(
      client: _FakeHttpClient(
        (method, uri) async => http.Response('not-json', 200),
      ),
    );
    final result = await service.testConnection(
      apiKey: 'test-key',
      model: 'gemini-2.5-flash',
    );
    expect(result.diagnosticCode, GeminiDiagnosticCodes.responseMalformed);
  });

  test(
    'respons daftar model malformed diberi kode respons malformed',
    () async {
      final service = GeminiService(
        client: _FakeHttpClient(
          (method, uri) async => http.Response('not-json', 200),
        ),
      );
      final result = await service.fetchModels(apiKey: 'test-key');
      expect(result.diagnosticCode, GeminiDiagnosticCodes.responseMalformed);
    },
  );

  test('timeout dan network diberi kode diagnostik tanpa rahasia', () async {
    final timeoutService = GeminiService(
      client: _FakeHttpClient(
        (method, uri) async =>
            Future<http.Response>.error(TimeoutException('timed out')),
      ),
    );
    final timeoutResult = await timeoutService.fetchModels(apiKey: 'test-key');
    expect(timeoutResult.diagnosticCode, GeminiDiagnosticCodes.timeout);

    final networkService = GeminiService(
      client: _FakeHttpClient(
        (method, uri) async => Future<http.Response>.error(
          http.ClientException('connection failed'),
        ),
      ),
    );
    final networkResult = await networkService.fetchModels(apiKey: 'test-key');
    expect(networkResult.diagnosticCode, GeminiDiagnosticCodes.network);
  });
}
