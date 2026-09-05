import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

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

Future<Uint8List> _noiseImage(int size) async {
  final raw = Uint8List(size * size * 4);
  final rng = math.Random(7);
  for (var index = 0; index < raw.length; index++) {
    raw[index] = rng.nextInt(256);
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    raw,
    size,
    size,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  final image = await completer.future;
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}

/// Gambar padat satu warna sehingga PNG-nya sangat kecil walau dimensi besar.
/// Berguna untuk menguji kompresi berbasis dimensi tanpa mencapai ambang 10MB.
Future<Uint8List> _solidImage(int width, int height, {int r = 200, int g = 200, int b = 200}) async {
  final raw = Uint8List(width * height * 4);
  for (var i = 0; i < raw.length; i += 4) {
    raw[i] = r;
    raw[i + 1] = g;
    raw[i + 2] = b;
    raw[i + 3] = 255;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    raw,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  final image = await completer.future;
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}

ReceiptScannerService _serviceReturning(String text, {int statusCode = 200}) =>
    ReceiptScannerService(
      gemini: GeminiService(
        client: _FakeHttpClient(
          (method, uri, body) async => http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': text},
                    ],
                  },
                },
              ],
            }),
            statusCode,
            headers: {'content-type': 'application/json'},
          ),
        ),
      ),
    );

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

  test('gambar lebih dari 10MB diturunkan resolusinya menjadi PNG', () async {
    final noisy = await _noiseImage(2048);
    expect(noisy.lengthInBytes, greaterThan(10 * 1024 * 1024));

    Map<String, dynamic>? requestJson;
    final service = ReceiptScannerService(
      gemini: GeminiService(
        client: _FakeHttpClient((method, uri, body) async {
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
        }),
      ),
    );

    final outcome = await service.scanImage(
      bytes: noisy,
      mimeType: 'image/jpeg',
      apiKey: 'test-key',
      model: 'gemini-test',
    );

    expect(outcome.ok, isTrue);
    final parts = (requestJson!['contents'] as List).last['parts'] as List;
    final inline = parts[1]['inline_data'] as Map<String, dynamic>;
    expect(inline['mime_type'], 'image/png');
    final sentBytes = base64Decode(inline['data'] as String);
    expect(sentBytes.lengthInBytes, lessThan(noisy.lengthInBytes));
  });

  test('gambar raksasa yang tidak dapat didekode memakai fallback aman',
      () async {
    final garbage = Uint8List(11 * 1024 * 1024);
    final rng = math.Random(3);
    for (var i = 0; i < 1024; i++) {
      garbage[i] = rng.nextInt(256);
    }

    final outcome = await _serviceReturning(_batchJson()).scanImage(
      bytes: garbage,
      mimeType: 'image/jpeg',
      apiKey: 'test-key',
      model: 'gemini-test',
    );

    expect(outcome.ok, isTrue);
  });

  test('PNG kecil tetap dikirim sebagai image/png', () async {
    final smallPng = await _noiseImage(2);

    Map<String, dynamic>? requestJson;
    final service = ReceiptScannerService(
      gemini: GeminiService(
        client: _FakeHttpClient((method, uri, body) async {
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
        }),
      ),
    );

    await service.scanImage(
      bytes: smallPng,
      mimeType: 'image/png',
      apiKey: 'test-key',
      model: 'gemini-test',
    );

    final parts = (requestJson!['contents'] as List).last['parts'] as List;
    final inline = parts[1]['inline_data'] as Map<String, dynamic>;
    expect(inline['mime_type'], 'image/png');
  });

  test('teks yang bukan JSON menghasilkan kegagalan jujur', () async {
    final outcome = await _serviceReturning('Struk ini tidak jelas').scanImage(
      bytes: _tinyImage(),
      apiKey: 'test-key',
      model: 'gemini-test',
    );

    expect(outcome.ok, isFalse);
    expect(outcome.message, contains('belum cocok'));
    expect(outcome.batch, isNull);
  });

  test('batch multi-transaksi (income + transfer) terbaca utuh', () async {
    final multiJson = jsonEncode({
      'format': 'ffm-transaction-batch-v1',
      'transactions': [
        {
          'type': 'income',
          'date': '2026-09-05',
          'merchant': 'Gaji',
          'amount': 500000,
          'note': 'Gaji bulanan',
        },
        {
          'type': 'transfer',
          'date': '2026-09-05',
          'merchant': 'Transfer BCA',
          'amount': 100000,
          'note': 'Kirim ke tabungan',
        },
      ],
    });

    final outcome = await _serviceReturning(multiJson).scanImage(
      bytes: _tinyImage(),
      apiKey: 'test-key',
      model: 'gemini-test',
    );

    expect(outcome.ok, isTrue);
    expect(outcome.transactionCount, 2);
    expect(outcome.batch!.entries[0].type, 'income');
    expect(outcome.batch!.entries[0].amount, 500000);
    expect(outcome.batch!.entries[1].type, 'transfer');
    expect(outcome.batch!.entries[1].amount, 100000);
  });

  test('teks token listrik PLN dikenali sebagai konteks meteran', () {
    expect(
      ReceiptScannerService.isPlnTokenText(
        'PT PLN (PERSERO) STRUK PEMBELIAN TOKEN LISTRIK '
        'IDPEL 14123456789 TOKEN 1234-5678-9012-3456-7890',
      ),
      isTrue,
    );
  });

  test('nomor panjang pada struk non-PLN tidak dikenali sebagai token', () {
    expect(
      ReceiptScannerService.isPlnTokenText(
        'INVOICE 1234-5678-9012-3456-7890 REF 12345678901 NO 9876543210',
      ),
      isFalse,
    );
    expect(
      ReceiptScannerService.isPlnTokenText('Indomaret belanja Rp 50.000'),
      isFalse,
    );
  });

  test('gambar dimensi besar tapi kecil ukuran ikut di-resize ke PNG', () async {
    // 2400x2400 padat satu warna: ukuran file kecil (<10MB) tapi sisi panjang
    // melebihi 1600px, sehingga tetap harus diturunkan resolusinya.
    final bigDim = await _solidImage(2400, 2400);

    Map<String, dynamic>? requestJson;
    final service = ReceiptScannerService(
      gemini: GeminiService(
        client: _FakeHttpClient((method, uri, body) async {
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
        }),
      ),
    );

    final outcome = await service.scanImage(
      bytes: bigDim,
      mimeType: 'image/png',
      apiKey: 'test-key',
      model: 'gemini-test',
    );

    expect(outcome.ok, isTrue);
    final parts = (requestJson!['contents'] as List).last['parts'] as List;
    final inline = parts[1]['inline_data'] as Map<String, dynamic>;
    expect(inline['mime_type'], 'image/png');
    final sentBytes = base64Decode(inline['data'] as String);
    expect(sentBytes.lengthInBytes, lessThan(bigDim.lengthInBytes));
  });

  test('scanImage menyertakan userCaption dalam prompt request ke Gemini', () async {
    Map<String, dynamic>? requestJson;
    final service = ReceiptScannerService(
      gemini: GeminiService(
        client: _FakeHttpClient((_, _, body) async {
          requestJson = jsonDecode(body!) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [{'text': _batchJson()}],
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final outcome = await service.scanImage(
      bytes: _tinyImage(),
      apiKey: 'test-key',
      model: 'gemini-test',
      userCaption: 'Pakai rekening BCA dan pos Belanja Dapur',
    );

    expect(outcome.ok, isTrue);
    final parts = (requestJson!['contents'] as List).last['parts'] as List;
    final promptText = parts[0]['text'] as String;
    expect(promptText, contains('Pakai rekening BCA dan pos Belanja Dapur'));
  });

  test('scanImage merekam tokenUsage secara realtime dari respon Gemini', () async {
    final service = ReceiptScannerService(
      gemini: GeminiService(
        client: _FakeHttpClient((_, _, _) async {
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [{'text': _batchJson()}],
                  },
                },
              ],
              'usageMetadata': {
                'promptTokenCount': 420,
                'candidatesTokenCount': 135,
                'totalTokenCount': 555,
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final outcome = await service.scanImage(
      bytes: _tinyImage(),
      apiKey: 'test-key',
      model: 'gemini-test',
    );

    expect(outcome.ok, isTrue);
    expect(outcome.tokenUsage, isNotNull);
    expect(outcome.tokenUsage!['promptTokenCount'], equals(420));
    expect(outcome.tokenUsage!['candidatesTokenCount'], equals(135));
    expect(outcome.tokenUsage!['totalTokenCount'], equals(555));
  });
}