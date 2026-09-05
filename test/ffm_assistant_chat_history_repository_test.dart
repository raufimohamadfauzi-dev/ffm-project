import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ffm_manager/features/assistant/data/ffm_assistant_chat_history_repository.dart';
import 'package:ffm_manager/features/assistant/domain/ffm_assistant_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('menyimpan dan memulihkan entry chat dasar secara lokal', () async {
    final repository = FfmAssistantChatHistoryRepository();
    final entries = [
      FfmAssistantChatEntry(
        isUser: true,
        text: 'Cek saldo',
        createdAt: DateTime(2026, 8, 23),
      ),
      FfmAssistantChatEntry(
        isUser: false,
        text: 'Saldo lokal ditemukan.',
        createdAt: DateTime(2026, 8, 23, 1),
      ),
    ];

    await repository.save(entries);
    final restored = await repository.load();

    expect(restored, hasLength(2));
    expect(restored.first.text, 'Cek saldo');
    expect(restored.last.isUser, isFalse);
    expect(restored.last.createdAt, DateTime(2026, 8, 23, 1));
  });

  test('retensi menyimpan hanya entry terbaru', () async {
    final repository = FfmAssistantChatHistoryRepository();
    final entries = List.generate(
      FfmAssistantChatHistoryRepository.maxEntries + 3,
      (index) => FfmAssistantChatEntry(isUser: true, text: '$index'),
    );

    await repository.save(entries);
    final restored = await repository.load();

    expect(restored, hasLength(FfmAssistantChatHistoryRepository.maxEntries));
    expect(restored.first.text, '3');
    expect(restored.last.text, '102');
  });

  test('clear menghapus history lokal', () async {
    final repository = FfmAssistantChatHistoryRepository();
    await repository.save([
      const FfmAssistantChatEntry(isUser: true, text: 'Hapus saya'),
    ]);

    await repository.clear();

    expect(await repository.load(), isEmpty);
  });

  test('import menggabungkan history lama dan mencegah duplikat', () async {
    final repository = FfmAssistantChatHistoryRepository();
    await repository.save([
      const FfmAssistantChatEntry(isUser: true, text: 'Data lama HP B'),
    ]);

    final imported = [
      {
        'isUser': true,
        'text': 'Data baru HP A',
        'createdAt': '2026-08-23T02:00:00.000',
      },
    ];
    await repository.importRaw(imported);
    await repository.importRaw(imported);

    final restored = await repository.readRaw();
    expect(restored, hasLength(2));
    expect(restored.map((row) => row['text']),
        containsAll(['Data lama HP B', 'Data baru HP A']));
  });

  test('entry chat menyimpan waktu kirim, terima, dan model', () async {
    final repository = FfmAssistantChatHistoryRepository();
    final sentAt = DateTime(2026, 9, 5, 9, 12, 5);
    final receivedAt = DateTime(2026, 9, 5, 9, 12, 9);
    await repository.save([
      FfmAssistantChatEntry(
        isUser: true,
        text: 'Cek saldo',
        sentAt: sentAt,
        modelUsed: 'user',
      ),
      FfmAssistantChatEntry(
        isUser: false,
        text: 'Saldo lokal tersedia.',
        sentAt: sentAt,
        receivedAt: receivedAt,
        modelUsed: 'gemini-cloud',
      ),
    ]);

    final restored = await repository.load();

    expect(restored.first.sentAt, sentAt);
    expect(restored.first.receivedAt, isNull);
    expect(restored.first.modelUsed, 'user');
    expect(restored.last.sentAt, sentAt);
    expect(restored.last.receivedAt, receivedAt);
    expect(restored.last.modelUsed, 'gemini-cloud');
  });

  test('entry legacy tanpa field metadata tetap terbaca dan fallback ke createdAt',
      () async {
    final repository = FfmAssistantChatHistoryRepository();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'ffm_assistant_chat_history_v1',
      jsonEncode([
        {
          'isUser': true,
          'text': 'Pesan lama',
          'createdAt': '2026-08-23T02:00:00.000',
        },
      ]),
    );

    final restored = await repository.load();
    final entry = restored.single;

    expect(entry.text, 'Pesan lama');
    expect(entry.createdAt, DateTime(2026, 8, 23, 2));
    expect(entry.sentAt, isNull);
    expect(entry.receivedAt, isNull);
    expect(entry.modelUsed, isNull);
  });

  test('updateEntryWithFeedback mempertahankan metadata chat', () async {
    final repository = FfmAssistantChatHistoryRepository();
    final sentAt = DateTime(2026, 9, 5, 9, 12, 5);
    await repository.save([
      FfmAssistantChatEntry(
        isUser: false,
        text: 'Jawaban asisten.',
        sentAt: sentAt,
        receivedAt: sentAt.add(const Duration(seconds: 4)),
        modelUsed: 'gemini-cloud',
      ),
    ]);

    await repository.updateEntryWithFeedback(0, 'thumbsup', null);

    final restored = await repository.load();
    expect(restored.single.feedbackType, 'thumbsup');
    expect(restored.single.sentAt, sentAt);
    expect(restored.single.receivedAt, sentAt.add(const Duration(seconds: 4)));
    expect(restored.single.modelUsed, 'gemini-cloud');
  });
}
