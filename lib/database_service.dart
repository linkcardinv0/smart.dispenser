import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // 1. TAMBAH UBAT BAHARU
  Future<void> addMedication({
    required String name,
    required String dosage,
    required int slot,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    await _supabase.from('medications').insert({
      'user_id': user.id,
      'medication_name': name,
      'dosage': dosage,
      'slot_number': slot,
    });
  }

  // 2. DAPATKAN SENARAI UBAT (REAL-TIME STREAM)
  Stream<List<Map<String, dynamic>>> getMedicationsStream() {
    final userId = _supabase.auth.currentUser?.id ?? '';
    return _supabase
        .from('medications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('slot_number', ascending: true);
  }

  // 3. REKOD PENGLOGAN UBAT (PILL LOGS)
  Future<void> addPillLog({
    required String medicationName,
    required String status, // 'TAKEN', 'MISSED', 'DISPENSED'
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    await _supabase.from('pill_logs').insert({
      'user_id': user.id,
      'medication_name': medicationName,
      'status': status,
    });
  }

  // 4. DAPATKAN SENARAI PILL LOGS (REAL-TIME STREAM)
  Stream<List<Map<String, dynamic>>> getPillLogsStream() {
    final userId = _supabase.auth.currentUser?.id ?? '';
    return _supabase
        .from('pill_logs')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('dispensed_at', ascending: false);
  }

  // 5. PADAM UBAT
  Future<void> deleteMedication(String id) async {
    await _supabase.from('medications').delete().eq('id', id);
  }
}