import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AIService {
  /// Method 1: Drug interaction check (used by reminders_page.dart)
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
      return 'No medications to check for interactions.';
    }

    final prompt = '''
You are an AI pharmacist for the SmartDispense AI system.
Analyze the following list of medications and check whether there are any drug-drug interactions or risks if they are taken together:

Medication list: $medsListString

Please give a clear response in English:
1. **Risk Status**: (Safe / Caution / Danger)
2. **Interaction Analysis**: (Brief explanation if any medications interact with each other)
3. **Recommendation**: (Time gap between doses, or advice to consult a doctor if needed)

Keep it short (maximum 200 words) and make sure the answer is complete to the end.
Do not give a definitive diagnosis; remind the user to confirm with a doctor or pharmacist.
''';

    return _callAi(prompt);
  }

  /// Method 2: Medication analysis for AddMedicationPage
  static Future<String> analyzeMedication({
    required String medicationName,
    required String dosage,
    required String form,
    required int slotNumber,
  }) async {
    if (medicationName.trim().isEmpty) {
      return 'Please enter the medication name first.';
    }

    final prompt = '''
You are an AI pharmacy assistant for a smart medicine dispenser system (SmartDispense AI).
Analyze the following medication and give brief, concise information in English:

- Medication name: $medicationName
- Dosage: $dosage
- Form: $form
- Dispenser slot: Slot $slotNumber

Respond in this format:
1. **Main Use**: (1-2 sentence summary of what the medicine is for)
2. **Instructions**: (Before/after meals or other important tips)
3. **Common Side Effects**: (2-3 side effects to watch for)
4. **Warnings**: (Things to avoid while taking this medicine)

Keep it short (maximum 200 words) and make sure the answer is complete to the end.
Remind the user to confirm with a doctor or pharmacist.
''';

    return _callAi(prompt);
  }

  /// Method 3: General chat (AIChatSheet / SmartDispense)
  static Future<String> askAi(String userPrompt) async {
    if (userPrompt.trim().isEmpty) {
      return 'Please type a question or medication information.';
    }

    final prompt = '''
You are a friendly AI health assistant for the SmartDispense AI system.
Answer the user's question about medications, dosage, or general health in a professional and clear way, in English:

Question: $userPrompt

Keep it short (maximum 200 words), use complete sentences, and make sure the answer is finished.
Do not give a definitive diagnosis or dosing instructions; recommend consulting a doctor or pharmacist for medical decisions.
''';

    return _callAi(prompt);
  }

  static Future<String> _callAi(String prompt) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'ai-assistant',
        body: {'prompt': prompt},
      ).timeout(const Duration(seconds: 60));

      if (response.status < 200 || response.status >= 300) {
        debugPrint('AI Edge Function returned status ${response.status}.');
        return 'The AI service could not process the request. Please try again.';
      }

      final data = response.data;
      if (data is Map && data['text'] is String) {
        final text = (data['text'] as String)
            .replaceAll('**', '')
            .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
            .trim();
        if (text.isNotEmpty) {
          // The edge function flags truncated answers (model token limit)
          if (data['truncated'] == true) {
            return '$text\n\n(The answer was shortened. Ask again with a more specific question for more details.)';
          }
          return text;
        }
      }

      debugPrint('AI Edge Function returned an invalid response.');
      return 'The AI service did not return a valid answer. Please try again.';
    } on Exception catch (error) {
      debugPrint('AI Edge Function request failed: $error');
      return 'Could not reach the AI service. Make sure the Supabase function is deployed and you are logged in.';
    }
  }
}