import 'dart:ui';
import 'package:flutter/material.dart';
import 'ai_service.dart';
import 'main.dart'; // Mengakses instance global 'supabase'

class RemindersPage extends StatefulWidget {
  final String dispenserId;

  const RemindersPage({
    super.key,
    this.dispenserId = 'dispensers_01',
  });

  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> {
  bool _isAnalyzing = false;
  String? _interactionResult;

  // Jadual lalai jika tiada tetapan masa disimpan di Supabase (4 Slot Carousel)
  final Map<int, TimeOfDay> _defaultSchedules = {
    1: const TimeOfDay(hour: 8, minute: 0),
    2: const TimeOfDay(hour: 12, minute: 0),
    3: const TimeOfDay(hour: 18, minute: 0),
    4: const TimeOfDay(hour: 21, minute: 0),
  };

  // Fungsi menukar TimeOfDay kepada string "HH:mm" untuk Supabase
  String _formatTimeOfDayToString(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // Fungsi menukar string "HH:mm" dari Supabase kepada TimeOfDay
  TimeOfDay _parseStringToTimeOfDay(String? timeStr, TimeOfDay fallback) {
    if (timeStr == null || !timeStr.contains(':')) return fallback;
    try {
      final parts = timeStr.split(':');
      return TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _selectTime(int slotNumber, Map<String, dynamic>? slotData) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final currentTime = _parseStringToTimeOfDay(
      slotData?['scheduled_time']?.toString(),
      _defaultSchedules[slotNumber]!,
    );

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: currentTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00B4D8),
              onPrimary: Colors.white,
              surface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final formattedTimeString = _formatTimeOfDayToString(picked);

      try {
        // ==========================================
        // LANGKAH 1: Kemas kini jadual 'medications'
        // ==========================================
        if (slotData != null && slotData['id'] != null) {
          await supabase
              .from('medications')
              .update({'scheduled_time': formattedTimeString})
              .eq('id', slotData['id']);
        } else {
          await supabase.from('medications').insert({
            'user_id': user.id,
            'slot_number': slotNumber,
            'medication_name': 'Empty',
            'dosage': '1 Pill',
            'scheduled_time': formattedTimeString,
          });
        }

        // ==========================================
        // LANGKAH 2: Sinkronkan ke 'jadual_ubat' (Untuk Raspberry Pi Auto-Dispense & FCM)
        // ==========================================
        final existingJadual = await supabase
            .from('jadual_ubat')
            .select()
            .eq('motor_pilihan', slotNumber.toString())
            .maybeSingle();

        if (existingJadual != null) {
          await supabase
              .from('jadual_ubat')
              .update({
                'masa': formattedTimeString,
                'status_aktif': true,
              })
              .eq('id', existingJadual['id']);
        } else {
          await supabase.from('jadual_ubat').insert({
            'motor_pilihan': slotNumber.toString(),
            'masa': formattedTimeString,
            'status_aktif': true,
          });
        }

        // 🟢 NOTIFIKASI LOCAL ALARM DIBUANG: 
        // Notifikasi kini dipicu secara terpusat oleh Raspberry Pi / Pelayan melalui FCM ke semua peranti.

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Slot $slotNumber masa dikemas kini ke ${picked.format(context)} & disegerakkan dengan Raspberry Pi',
            ),
            backgroundColor: const Color(0xFF00B4D8),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengemas kini jadual: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _runInteractionCheck(List<dynamic> medications) async {
    List<String> activeMeds = [];

    for (var med in medications) {
      final name = med['medication_name']?.toString().trim() ?? '';
      if (name.isNotEmpty && name != 'Empty' && name != 'Unassigned') {
        activeMeds.add(name);
      }
    }

    if (activeMeds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sila tambah sekurang-kurangnya satu ubat aktif pada mana-mana slot dahulu.',
          ),
          backgroundColor: Colors.orangeAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _interactionResult = null;
    });

    final result = await AIService.checkDrugInteractions(activeMeds);

    if (!mounted) return;
    setState(() {
      _isAnalyzing = false;
      _interactionResult = result.trim().isNotEmpty
          ? result
          : 'Semakan interaksi ubat tidak tersedia buat masa ini. Sila rujuk doktor atau ahli farmasi tentang kombinasi ubat anda.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF0284C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: supabase
              .from('medications')
              .stream(primaryKey: ['id'])
              .eq('user_id', user?.id ?? ''),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Ralat memuatkan jadual: ${snapshot.error}',
                  style: const TextStyle(color: Colors.redAccent),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF00B4D8)),
              );
            }

            final medications = snapshot.data ?? [];

            final Map<int, Map<String, dynamic>?> slotsData = {
              1: null,
              2: null,
              3: null,
              4: null,
            };

            for (var med in medications) {
              final slotNum = med['slot_number'] as int?;
              if (slotNum != null && slotNum >= 1 && slotNum <= 4) {
                slotsData[slotNum] = med;
              }
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.only(
                top: 70,
                left: 20,
                right: 20,
                bottom: 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Safety & Smart Reminders',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInteractionCheckerCard(medications),
                  const SizedBox(height: 20),
                  const Text(
                    'Daily Dispensing Schedules',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00B4D8),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...List.generate(4, (index) {
                    final slotNumber = index + 1;
                    final slotData = slotsData[slotNumber];

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10.0),
                      child: _buildSlotScheduleRow(
                        slotNumber: slotNumber,
                        slotData: slotData,
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildInteractionCheckerCard(List<dynamic> medications) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF00B4D8).withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: Color(0xFF00B4D8),
                    size: 24,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'AI Drug Interaction Scanner',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Evaluates cross-medication risks between all active slots in Supabase using AI.',
                style: TextStyle(fontSize: 12, color: Colors.white60),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isAnalyzing
                      ? null
                      : () => _runInteractionCheck(medications),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00B4D8),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _isAnalyzing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.auto_awesome, size: 20),
                  label: Text(
                    _isAnalyzing
                        ? 'Scanning Medications...'
                        : 'CHECK ALL SLOT INTERACTIONS',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              if (_interactionResult != null) ...[
                const Divider(color: Colors.white12, height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF00B4D8).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    _interactionResult!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlotScheduleRow({
    required int slotNumber,
    required Map<String, dynamic>? slotData,
  }) {
    final medName = slotData?['medication_name']?.toString().trim() ?? 'Unassigned';
    final dosageInfo = slotData?['dosage']?.toString().trim() ?? 'No inventory data';
    
    final displayTime = _parseStringToTimeOfDay(
      slotData?['scheduled_time']?.toString(),
      _defaultSchedules[slotNumber]!,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor:
                    const Color(0xFF00B4D8).withValues(alpha: 0.2),
                child: Text(
                  'S$slotNumber',
                  style: const TextStyle(
                    color: Color(0xFF00B4D8),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medName.isEmpty ? 'Slot $slotNumber' : medName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      dosageInfo,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _selectTime(slotNumber, slotData),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00B4D8),
                  side: const BorderSide(color: Color(0xFF00B4D8)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                icon: const Icon(Icons.access_time_rounded, size: 16),
                label: Text(
                  displayTime.format(context),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}