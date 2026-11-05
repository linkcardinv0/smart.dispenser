import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class AIService {
  static const String _apiKey =
      'AQ.Ab8RN6L-UdQZwKvkKXmyv-jvrUbJGjKpgFuaW0awkC1wbPKaTQ';

  // Active production endpoints
  static const String _primaryModel = 'gemini-3.8-flash';
  static const List<String> _fallbackModels = [
    'gemini-3.6-flash',
    'gemini-3.5-flash-lite',
  ];

  /// Method 1: Used by AddMedicationPage for Form Inputs
  static Future<String> analyzeMedication({
    required String medicationName,
    required String dosage,
    required String form,
    required int slotNumber,
  }) async {
    if (medicationName.trim().isEmpty) {
      return 'Please enter a medication name first.';
    }

    final prompt = '''
You are a pharmaceutical safety AI integrated into a 4-slot medicine dispenser app.
Analyze this medication:
- Name: $medicationName
- Dosage: $dosage
- Form: $form
- Dispenser Slot: Slot $slotNumber

Provide a 2-sentence summary:
1. Core side effects & food instructions (e.g., take with food or on an empty stomach).
2. A brief safety warning for taking this specific dosage.
''';

    return _callGeminiAPI(prompt);
  }

  /// Method 2: Used by AIChatSheet for General Medical Queries
  static Future<String> analyzeSafety(String query, String category) async {
    if (query.trim().isEmpty) {
      return 'Please ask a valid question.';
    }

    final prompt = '''
You are a helpful AI Medical Assistant integrated into a medicine reminder dispenser app.
The user is asking: "$query"

Provide a concise, clear, and accurate answer suitable for a patient or caregiver regarding dosage, side effects, or drug interactions. Include a brief reminder to consult a medical doctor for professional advice if appropriate.
''';

    return _callGeminiAPI(prompt);
  }

  /// Method 3: Used by RemindersPage to Analyze Interactions across all slots
  static Future<String> checkDrugInteractions(List<String> activeMeds) async {
    if (activeMeds.isEmpty) {
      return 'No active medications found in slots to analyze.';
    }

    final prompt = '''
You are a clinical safety AI integrated into a medicine reminder dispenser.
The patient is currently taking the following list of medications simultaneously:
${activeMeds.map((med) => '- $med').join('\n')}

Analyze these medications together and provide a concise 3-part medical assessment:
1. **Safety Status**: State clearly whether taking these together is SAFE, REQUIRES CAUTION, or CONTRAINDICATED.
2. **Potential Interactions**: Explain any major drug-drug or food-drug interactions in plain language.
3. **Key Advice**: One critical piece of advice for taking them safely (e.g., spacing doses apart).
''';

    return _callGeminiAPI(prompt);
  }

  /// Robust HTTP handler with automatic retries and active fallbacks
  static Future<String> _callGeminiAPI(String prompt) async {
    final modelsToTry = [_primaryModel, ..._fallbackModels];

    for (final modelName in modelsToTry) {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$_apiKey',
      );

      // Try up to 2 attempts per model endpoint with backoff delay
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          if (attempt > 0) {
            await Future.delayed(Duration(milliseconds: 600 * attempt));
          }

          final response = await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt}
                  ]
                }
              ]
            }),
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final text =
                data['candidates']?[0]?['content']?['parts']?[0]?['text'];
            return text?.toString().trim() ??
                'I did not receive a valid response. Please try again.';
          } else if (response.statusCode == 503) {
            // High demand on Google servers, retry attempt or move to fallback
            print(
                'Model $modelName returned 503 (Attempt ${attempt + 1}). Retrying...');
            continue;
          } else {
            return 'API Error (${response.statusCode}): ${response.body}';
          }
        } catch (e) {
          print('Connection exception on $modelName: $e');
        }
      }
    }

    return 'The AI service is temporarily unavailable due to high Google server demand. Please try sending your query again in a few seconds.';
  }
}