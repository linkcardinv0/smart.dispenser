import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AIService {
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

    return _callAi(prompt);
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

    return _callAi(prompt);
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

    return _callAi(prompt);
  }

  static Future<String> _callAi(String prompt) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'ai-assistant',
        body: {'prompt': prompt},
      );

      if (response.status < 200 || response.status >= 300) {
        debugPrint('AI Edge Function returned status ${response.status}.');
        return 'Servis AI tidak dapat memproses permintaan. Sila cuba lagi.';
      }

      final data = response.data;
      if (data is Map && data['text'] is String) {
        final text = (data['text'] as String).trim();
        if (text.isNotEmpty) return text;
      }

      debugPrint('AI Edge Function returned an invalid response.');
      return 'Servis AI tidak memberikan jawapan yang sah. Sila cuba lagi.';
    } on Exception catch (error) {
      debugPrint('AI Edge Function request failed: $error');
      return 'Gagal menghubungi servis AI. Pastikan fungsi Supabase telah diterbitkan dan anda telah log masuk.';
    }
  }
}
