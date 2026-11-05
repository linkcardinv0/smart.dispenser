import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class AIService {
  // 1. Ambil API Key dari fail .env (atau fallback kunci peranti)
  static String get _apiKey {
    final key = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (key.isNotEmpty) return key;
    return 'AIzaSy_GANTIKAN_DENGAN_KEY_AIzaSy_SEBENAR_ANDA';
  }

  // 2. Senarai model rasmi Google Gemini (dengan mekanisme fallback)
  static const String _primaryModel = 'gemini-1.5-flash';
  static const List<String> _fallbackModels = [
    'gemini-2.0-flash',
    'gemini-1.5-pro',
  ];

  /// Method 1: Semakan Interaksi Ubat (Digunakan oleh reminders_page.dart)
  static Future<String> checkDrugInteractions(dynamic medications) async {
    String medsListString = '';

    if (medications is List) {
      medsListString = medications.map((m) {
        if (m is Map) {
          return m['name'] ?? m['medication_name'] ?? m.toString();
        }
        return m.toString();
      }).join(', ');
    } else {
      medsListString = medications.toString();
    }

    if (medsListString.trim().isEmpty) {
      return 'Tiada ubat untuk disemak interaksi.';
    }

    final prompt = '''
Anda ialah pakar farmasi AI untuk sistem SmartDispense AI.
Analisis senarai ubat-ubatan berikut dan semak sama ada terdapat sebarang interaksi ubat (drug-drug interaction) atau risiko jika diambil bersama:

Senarai Ubat: $medsListString

Sila berikan respon jelas dalam Bahasa Melayu:
1. **Status Risiko**: (Selamat / Perhatian / Bahaya)
2. **Analisis Interaksi**: (Penjelasan ringkas jika ada ubat yang bertindak balas antara satu sama lain)
3. **Saranan Pengambilan**: (Jarak masa pengambilan atau nasihat doktor jika perlu)
''';

    return await _callGeminiApi(prompt);
  }

  /// Method 2: Analisis Ubat untuk AddMedicationPage
  static Future<String> analyzeMedication({
    required String medicationName,
    required String dosage,
    required String form,
    required int slotNumber,
  }) async {
    if (medicationName.trim().isEmpty) {
      return 'Sila masukkan nama ubat terlebih dahulu.';
    }

    final prompt = '''
Anda ialah pembantu farmasi AI untuk sistem dispenser ubat pintar (SmartDispense AI).
Analisis ubat berikut dan berikan maklumat ringkas serta padat dalam Bahasa Melayu:

- Nama Ubat: $medicationName
- Dos: $dosage
- Bentuk: $form
- Slot Dispenser: Slot $slotNumber

Berikan respon mengikut format ini:
1. **Kegunaan Utama**: (Ringkasan 1-2 ayat fungsi ubat)
2. **Arahan Pengambilan**: (Sebelum/selepas makan atau petua penting)
3. **Kesan Sampingan Biasa**: (2-3 kesan sampingan yang perlu diperhatikan)
4. **Amaran Peringatan**: (Perkara yang elak dilakukan semasa mengambil ubat ini)
''';

    return await _callGeminiApi(prompt);
  }

  /// Method 3: Perbualan Am (AIChatSheet / SmartDispense)
  static Future<String> askAi(String userPrompt) async {
    if (userPrompt.trim().isEmpty) {
      return 'Sila taip soalan atau maklumat ubat.';
    }

    final prompt = '''
Anda ialah pembantu kesihatan AI mesra untuk sistem SmartDispense AI.
Jawab soalan pengguna berkaitan ubat-ubatan, dos, atau kesihatan am secara profesional dan jelas dalam Bahasa Melayu:

Soalan: $userPrompt
''';

    return await _callGeminiApi(prompt);
  }

  /// Fungsi Utama Hantar Request HTTP ke Endpoint Google Gemini REST API
  static Future<String> _callGeminiApi(String prompt) async {
    final currentKey = _apiKey;
    if (currentKey.contains('GANTIKAN_DENGAN_KEY') || currentKey.isEmpty) {
      return 'API Key belum disetkan. Sila masukkan API Key bermula dengan "AIzaSy..." dalam fail .env atau ai_service.dart.';
    }

    final modelsToTry = [_primaryModel, ..._fallbackModels];

    for (final model in modelsToTry) {
      try {
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$currentKey',
        );

        final response = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'contents': [
                  {
                    'parts': [
                      {'text': prompt}
                    ]
                  }
                ],
                'generationConfig': {
                  'temperature': 0.4,
                  'maxOutputTokens': 600,
                }
              }),
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final String? text =
              data['candidates']?[0]?['content']?['parts']?[0]?['text'];

          if (text != null && text.isNotEmpty) {
            return text.trim();
          }
        } else {
          debugPrint(
              'Gemini API Error ($model): ${response.statusCode} - ${response.body}');
        }
      } catch (e) {
        debugPrint('Ralat sambungan ke model $model: $e');
      }
    }

    return 'Gagal berhubung dengan AI. Sila semak sambungan internet atau sahkan API Key anda.';
  }
}