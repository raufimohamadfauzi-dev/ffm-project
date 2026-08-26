import 'dart:convert';
import 'package:http/http.dart' as http;
import 'supabase_config.dart';

class GeminiService {
  final _config = SupabaseConfig();
  static const _model = 'gemini-1.5-flash';

  Future<String?> chat({
    required String prompt,
    String? systemInstruction,
    List<Map<String, String>> history = const [],
  }) async {
    final apiKey = await _config.getGeminiKey();
    if (apiKey == null || apiKey.isEmpty) return null;

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$apiKey',
    );

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (systemInstruction != null)
            "system_instruction": {
              "parts": [{"text": systemInstruction}]
            },
          "contents": [
            ...history.map((h) => {
              "role": h['role'] == 'user' ? 'user' : 'model',
              "parts": [{"text": h['text']}]
            }),
            {
              "role": "user",
              "parts": [{"text": prompt}]
            }
          ],
          "generationConfig": {
            "temperature": 0.7,
            "topK": 40,
            "topP": 0.95,
            "maxOutputTokens": 1024,
          }
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'] as String;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
