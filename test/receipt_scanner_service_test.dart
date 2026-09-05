import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:ffm_manager/core/network/gemini_service.dart';
import 'package:ffm_manager/features/assistant/data/receipt_scanner_service.dart';

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this.handler);

  final Future<http.Response> Function(String method, Uri uri, String? body)
      handler;
  Map<String, String>? lastHeaders;
  Uri? lastUri;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastHeaders = request.headers;
    lastUri = request.url;
    final bodyBytes = await request.finalize().toBytes();
    final response = await handler(
      request.method,
      request.url,
      utf8.decode(bodyBytes),
    );
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

String _batchJson({String note = ''}) => jsonEncode({
  'format': 'ffm-transaction-batch-v1',
  'transactions': [
    {
      'type': 'expense',
      'date': '2026-09-05',
      'merchant': 'PT PLN',
      'budget_name': 'Listrik',
      'amount': 205000,
      'note': note,
      'items': const [
        {'name': 'TOKEN LISTRIK 200000', 'quantity': 1, 'amount': 205000},
      ],
    },
  ],
});

Uint8List _tinyImage() =>
    Uint8List.fromList(List<int>.generate(256, (index) => index % 251));

void main() {
  test(
    'hasil JSON batch yang valid menghasilkan outcome sukses dan draft expense',
    () async {
      final service = ReceiptScannerService(
        gemini: GeminiService(
          client: _FakeHttpClient(
            (method, uri, body) async => http.Response(
              jsonEncode({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': _batchJson()},
                      ],
                    },
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      );

      final outcome = await service.scanImage(
        bytes: _tinyImage(),
        imagePath: '/tmp/struk.jpg',
        apiKey: 'test-key',
        model: 'gemini-test',
      );

      expect(outcome.ok, isTrue);
      expect(outcome.transactionCount, 1);
      final entry = outcome.batch!.entries.single;
      expect(entry.type, 'expense');
      expect(entry.amount, 205000);
      expect(entry.merchant, 'PT PLN');
      expect(entry.budgetName, 'Listrik');
      expect(outcome.imagePath, '/tmp/struk.jpg');
      expect(outcome.warnings, isEmpty);
    },
  );

  test(
    'request ke Gemini membawa gambar inline dan sistem instruksi vision',
    () async {
      Map<String, dynamic>? requestJson;
      final client = _FakeHttpClient((method, uri, body) async {
        requestJson = jsonDecode(body!) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': _batchJson()},
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final service = ReceiptScannerService(
        gemini: GeminiService(client: client),
      );
      final bytes = _tinyImage();

      await service.scanImage(
        bytes: bytes,
        mimeType: 'image/jpeg',
        apiKey: 'test-key',
        model: 'gemini-test',
      );

      final parts =
          (requestJson!['contents'] as List).last['parts'] as List;
      expect(parts, hasLength(2));
      final inline = parts[1]['inline_data'] as Map<String, dynamic>;
      expect(inline['mime_type'], 'image/jpeg');
      final systemInstruction =
          requestJson!['system_instruction'] as Map<String, dynamic>;
      final systemParts = systemInstruction['parts'] as List;
      final system = systemParts.first['text'] as String;
      expect(system, contains('FOTO STRUK'));
    },
  );

  test(
    'JSON satu struk (ffm-receipt-draft-v1) tetap diterima sebagai satu transaksi',
    () async {
      final service = ReceiptScannerService(
        gemini: GeminiService(
          client: _FakeHttpClient(
            (method, uri, body) async => http.Response(
              jsonEncode({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {
                          'text': jsonEncode({
                            'format': 'ffm-receipt-draft-v1',
                            'receipt': {
                              'merchant': 'Warteg Sederhana',
                              'total': 42000,
                              'items': const [
                                {
                                  'name': 'Nasi ayam',
                                  'quantity': 1,
                                  'amount': 25000,
                                },
                                {
                                  'name': 'Es teh',
                                  'quantity': 1,
                                  'amount': 17000,
                                },
                              ],
                            },
                          }),
                        },
                      ],
                    },
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      );

      final outcome = await service.scanImage(
        bytes: _tinyImage(),
        apiKey: 'test-key',
        model: 'gemini-test',
      );

      expect(outcome.ok, isTrue);
      expect(outcome.transactionCount, 1);
      final entry = outcome.batch!.entries.single;
      expect(entry.amount, 42000);
      expect(entry.merchant, 'Warteg Sederhana');
      expect(outcome.warnings, isEmpty);
    },
  );

  test(
    'ketidakcocokan total transaksi dengan jumlah baris menghasilkan warning',
    () async {
      final service = ReceiptScannerService(
        gemini: GeminiService(
          client: _FakeHttpClient(
            (method, uri, body) async => http.Response(
              jsonEncode({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {
                          'text': jsonEncode({
                            'format': 'ffm-transaction-batch-v1',
                            'transactions': const [
                              {
                                'type': 'expense',
                                'merchant': 'Indomaret',
                                'amount': 100000,
                                'items': [
                                  {
                                    'name': 'Minyak',
                                    'quantity': 1,
                                    'amount': 60000,
                                  },
                                  {
                                    'name': 'Telur',
                                    'quantity': 1,
                                    'amount': 25000,
                                  },
                                ],
                              },
                            ],
                          }),
                        },
                      ],
                    },
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
      );

      final outcome = await service.scanImage(
        bytes: _tinyImage(),
        apiKey: 'test-key',
        model: 'gemini-test',
      );

      expect(outcome.ok, isTrue);
      expect(outcome.warnings, hasLength(1));
      expect(outcome.warnings.single, contains('berbeda dengan jumlah baris'));
    },
  );

  test('respond tanpa teks menghasilkan outcome gagal yang jujur', () async {
    final service = ReceiptScannerService(
      gemini: GeminiService(
        client: _FakeHttpClient(
          (method, uri, body) async => http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': ''},
                    ],
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    final outcome = await service.scanImage(
      bytes: _tinyImage(),
      apiKey: 'test-key',
      model: 'gemini-test',
    );

    expect(outcome.ok, isFalse);
    expect(outcome.message, contains('tanpa teks'));
    expect(outcome.batch, isNull);
  });

  test('kesalahan jaringan Gemini menghasilkan outcome gagal jujur', () async {
    final service = ReceiptScannerService(
      gemini: GeminiService(
        client: _FakeHttpClient(
          (method, uri, body) async => http.Response(
            jsonEncode({
              'error': {'message': 'API key not valid'},
            }),
            400,
          ),
        ),
      ),
    );

    final outcome = await service.scanImage(
      bytes: _tinyImage(),
      apiKey: 'wrong-key',
      model: 'gemini-test',
    );

    expect(outcome.ok, isFalse);
    expect(outcome.message, isNotEmpty);
    expect(outcome.model, 'gemini-test');
    expect(outcome.latency, isNotNull);
  });

  test('token listrik: note token & IDPEL dipertahankan pada transaksi',
      () async {
    final service = ReceiptScannerService(
      gemini: GeminiService(
        client: _FakeHttpClient(
          (method, uri, body) async => http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'text': _batchJson(
                          note:
                              'IDPEL 123456789012 TOKEN 52305443146247152564',
                        ),
                      },
                    ],
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );

    final outcome = await service.scanImage(
      bytes: _tinyImage(),
      apiKey: 'test-key',
      model: 'gemini-test',
    );

    expect(outcome.ok, isTrue);
    final entry = outcome.batch!.entries.single;
    expect(entry.budgetName, 'Listrik');
    expect(entry.note, contains('TOKEN'));
    expect(entry.note, contains('IDPEL'));
  });
}