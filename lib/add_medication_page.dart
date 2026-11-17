import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ai_service.dart';
import 'main.dart'; // Mengakses instance global 'supabase'
import 'notification_service.dart';

class SlotSensorData {
  final int slotNumber;
  final String? medicationName;
  final int currentPillCount;
  final int maxCapacity;

  const SlotSensorData({
    required this.slotNumber,
    this.medicationName,
    required this.currentPillCount,
    this.maxCapacity = 10,
  });

  bool get isEmpty => currentPillCount == 0;
  bool get isLow => currentPillCount > 0 && currentPillCount <= 2;
}

class AddMedicationPage extends StatefulWidget {
  const AddMedicationPage({super.key});

  @override
  State<AddMedicationPage> createState() => _AddMedicationPageState();
}

class _AddMedicationPageState extends State<AddMedicationPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _dosageController = TextEditingController();
  final TextEditingController _formController = TextEditingController();

  int _selectedSlot = 1;
  String _selectedFrequency = 'Every Day';
  final List<String> _frequencies = const [
    'Every Day',
    'Every Other Day',
    'As Needed',
    'Custom Schedule',
  ];

  // Masa dipilih bebas oleh user (time picker)
  TimeOfDay _selectedTime = const TimeOfDay(hour: 8, minute: 0);

  // AI Insight state variables
  String _aiInsightText = 'Tap "Analyze with AI" to generate real-time safety warnings.';
  bool _isAnalyzing = false;
  bool _isSaving = false;
  final ScrollController _aiScroll = ScrollController();

  // Simulated live sensor data from the 4 dispenser slots
  final Map<int, SlotSensorData> _slotsData = const {
    1: SlotSensorData(slotNumber: 1, medicationName: null, currentPillCount: 0),
    2: SlotSensorData(slotNumber: 2, medicationName: null, currentPillCount: 0),
    3: SlotSensorData(slotNumber: 3, medicationName: null, currentPillCount: 0),
    4: SlotSensorData(slotNumber: 4, medicationName: null, currentPillCount: 0),
  };

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _formController.dispose();
    _aiScroll.dispose();
    super.dispose();
  }

  /// Format masa ke 24-jam 'HH:mm' untuk pangkalan data
  String _timeToDb(TimeOfDay t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _runAILogic() async {
    setState(() {
      _isAnalyzing = true;
    });

    final result = await AIService.analyzeMedication(
      medicationName: _nameController.text,
      dosage: _dosageController.text,
      form: _formController.text,
      slotNumber: _selectedSlot,
    );

    if (mounted) {
      setState(() {
        _aiInsightText = result;
        _isAnalyzing = false;
      });
      if (_aiScroll.hasClients) _aiScroll.jumpTo(0);
    }
  }

  // Fungsi simpan data ke Supabase
  Future<void> _saveMedicationToSupabase() async {
    final medName = _nameController.text.trim();
    final dosage = _dosageController.text.trim();

    if (medName.isEmpty || dosage.isEmpty) {
      _showSnackBar('Please enter Medication Name and Dosage.');
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      _showSnackBar('User session not found. Please log in again.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final scheduledTime = _timeToDb(_selectedTime);
      final displayTime = _selectedTime.format(context);

      final payload = {
        'medication_name': medName,
        'dosage': dosage,
        'slot_number': _selectedSlot,
        'scheduled_time': scheduledTime,
        'last_notified_on': null,
      };

      // Satu slot = satu baris. Kemas kini SEMUA baris slot ini milik user
      // (termasuk pendua) dan pulangkan baris yang dikemas kini.
      // .select('id') penting: jika RLS menyekat update, senarai ini kosong
      // dan kita akan insert baris baru, bukannya senyap-senyap gagal.
      final updated = await supabase
          .from('medications')
          .update(payload)
          .eq('user_id', user.id)
          .eq('slot_number', _selectedSlot)
          .select('id');

      if (updated.isEmpty) {
        await supabase.from('medications').insert({
          'user_id': user.id,
          ...payload,
        });
      }

      // Sinkronkan ke 'jadual_ubat' (Raspberry Pi auto-dispense)
      final existingJadual = await supabase
          .from('jadual_ubat')
          .select()
          .eq('motor_pilihan', _selectedSlot.toString())
          .maybeSingle();

      if (existingJadual != null) {
        await supabase.from('jadual_ubat').update({
          'masa': scheduledTime,
          'status_aktif': true,
        }).eq('id', existingJadual['id']);
      } else {
        await supabase.from('jadual_ubat').insert({
          'motor_pilihan': _selectedSlot.toString(),
          'masa': scheduledTime,
          'status_aktif': true,
        });
      }

      // Jadualkan alarm (Android sahaja, web guna Web Push dari Supabase)
      if (!kIsWeb) {
        try {
          await NotificationService().syncFromDatabase();
        } catch (e) {
          _showSnackBar('Medication saved, but the alarm could not be scheduled: $e');
        }
      }

      _showSnackBar('Medication saved. Reminder set for $displayTime daily.');
      if (mounted) Navigator.of(context).pop();
    } on PostgrestException catch (error) {
      _showSnackBar('Supabase Error: ${error.message}');
    } catch (error) {
      debugPrint('Save medication failed: $error');
      _showSnackBar('An unexpected error occurred while saving.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: const Color(0xFF0056C6),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0056C6);
    const lightBgColor = Color(0xFFF5F7FA);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'NEW MEDICATION',
          style: TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveMedicationToSupabase,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primaryColor,
                    ),
                  )
                : const Text(
                    'SAVE',
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Select Dispenser Slot (4 Slots Grid)
            _buildSectionLabel('ASSIGN DISPENSER SLOT'),
            const SizedBox(height: 10),
            Row(
              children: List.generate(4, (index) {
                final slotNum = index + 1;
                final slot = _slotsData[slotNum]!;
                final isSelected = _selectedSlot == slotNum;

                Color badgeColor = Colors.green;
                if (slot.isEmpty) {
                  badgeColor = Colors.grey;
                } else if (slot.isLow) {
                  badgeColor = Colors.orange;
                }

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedSlot = slotNum;
                      });
                    },
                    child: Container(
                      margin: EdgeInsets.only(right: index == 3 ? 0 : 8),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? primaryColor.withValues(alpha: 0.1) : lightBgColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? primaryColor : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'SLOT $slotNum',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? primaryColor : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${slot.currentPillCount} left',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: badgeColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),

            // Medication Name
            _buildSectionLabel('MEDICATION NAME'),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              decoration: _buildInputDecoration(
                hintText: 'e.g. Lisinopril',
                fillColor: lightBgColor,
              ),
            ),
            const SizedBox(height: 20),

            // Dosage & Form (Row)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionLabel('DOSAGE'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _dosageController,
                        decoration: _buildInputDecoration(
                          hintText: '10mg',
                          fillColor: lightBgColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionLabel('FORM'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _formController,
                        decoration: _buildInputDecoration(
                          hintText: 'Tablet',
                          fillColor: lightBgColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Schedule Frequency
            _buildSectionLabel('SCHEDULE FREQUENCY'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: lightBgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedFrequency,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down),
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                  items: _frequencies.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedFrequency = newValue;
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Reminder Time (pilih bebas)
            _buildSectionLabel('REMINDER TIME'),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: lightBgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_rounded, color: primaryColor, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _selectedTime.format(context),
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Text(
                      'Change',
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // AI Safety Insight Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14.0),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.grey.shade200,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.auto_awesome, color: primaryColor, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'AI SAFETY INSIGHT',
                            style: TextStyle(
                              color: primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      InkWell(
                        onTap: _isAnalyzing ? null : _runAILogic,
                        child: Text(
                          _isAnalyzing ? 'Analyzing...' : 'Analyze with AI',
                          style: const TextStyle(
                            color: primaryColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_isAnalyzing)
                    const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: primaryColor,
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: Scrollbar(
                        controller: _aiScroll,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _aiScroll,
                          padding: const EdgeInsets.only(right: 8),
                          child: SelectableText(
                            _aiInsightText,
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
        letterSpacing: 0.5,
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String hintText,
    required Color fillColor,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
    );
  }
}