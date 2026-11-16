import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main.dart'; // Mengakses instance global 'supabase'
import 'drugs_header_bar.dart';

const Color _accent = Color(0xFF00B4D8);

const BoxDecoration _bgDecoration = BoxDecoration(
  gradient: LinearGradient(
    colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF0284C7)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  ),
);

Widget _glass({required Widget child, EdgeInsetsGeometry? padding}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: Container(
        width: double.infinity,
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
            width: 1.5,
          ),
        ),
        child: child,
      ),
    ),
  );
}

/// 'HH:MM' (24 jam) -> '4:40 PM'
String _fmtTime(dynamic raw) {
  final s = raw?.toString() ?? '';
  final p = s.split(':');
  if (p.length < 2) return '--:--';
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  if (h == null || m == null) return '--:--';
  final suffix = h >= 12 ? 'PM' : 'AM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} $suffix';
}

// ======================= SENARAI PESAKIT =======================

class CaregiverDashboard extends StatefulWidget {
  const CaregiverDashboard({super.key});

  @override
  State<CaregiverDashboard> createState() => _CaregiverDashboardState();
}

class _CaregiverDashboardState extends State<CaregiverDashboard> {
  List<Map<String, dynamic>> _patients = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final links = await supabase
          .from('caregiver_links')
          .select('patient_id')
          .eq('caregiver_id', user.id);

      final ids = links.map((e) => e['patient_id'] as String).toList();

      List<Map<String, dynamic>> patients = [];
      if (ids.isNotEmpty) {
        final rows = await supabase
            .from('profiles')
            .select('id, full_name, phone_number, age_gender, medical_conditions')
            .inFilter('id', ids);
        patients = List<Map<String, dynamic>>.from(rows);
      }
      if (!mounted) return;
      setState(() => _patients = patients);
    } catch (e) {
      debugPrint('Failed to load patients: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: _accent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showLinkDialog() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Link Patient',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the 6-character invite code from the patient (found in Settings on the patient account).',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              style: const TextStyle(
                  color: Colors.white, fontSize: 20, letterSpacing: 4),
              decoration: const InputDecoration(
                counterText: '',
                hintText: 'ABC123',
                hintStyle: TextStyle(color: Colors.white24),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: _accent)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('LINK', style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );
    controller.dispose();

    if (code == null || code.isEmpty) return;

    try {
      final name = await supabase.rpc('link_patient', params: {'p_code': code});
      _snack('Successfully linked with $name');
      await _load();
    } on PostgrestException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not link the patient. Please try again.');
    }
  }

  Future<void> _unlink(Map<String, dynamic> patient) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Unlink patient?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'You will no longer be able to see data for ${patient['full_name'] ?? 'this patient'}.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('UNLINK',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      await supabase
          .from('caregiver_links')
          .delete()
          .eq('caregiver_id', user.id)
          .eq('patient_id', patient['id']);
      await _load();
    } catch (_) {
      _snack('Could not unlink the patient.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: DrugsHeaderBar(onSignOut: () => supabase.auth.signOut()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showLinkDialog,
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Link Patient'),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: _bgDecoration,
        child: SafeArea(
          child: RefreshIndicator(
            color: _accent,
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding:
                  const EdgeInsets.only(top: 70, left: 20, right: 20, bottom: 100),
              children: [
                const Text(
                  'My Patients',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'You can view medications and dispense history (read-only).',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Center(child: CircularProgressIndicator(color: _accent)),
                  )
                else if (_patients.isEmpty)
                  _glass(
                    padding: const EdgeInsets.all(24),
                    child: const Column(
                      children: [
                        Icon(Icons.group_add_outlined, color: _accent, size: 40),
                        SizedBox(height: 12),
                        Text(
                          'No patients linked yet.',
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Ask the patient for their invite code, then tap "Link Patient".',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                else
                  ..._patients.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _glass(
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          leading: const CircleAvatar(
                            backgroundColor: _accent,
                            child: Icon(Icons.person, color: Colors.white),
                          ),
                          title: Text(
                            (p['full_name'] ?? 'Patient').toString(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            [
                              p['age_gender'],
                              p['phone_number'],
                            ]
                                .where((e) =>
                                    e != null && e.toString().isNotEmpty)
                                .join('  •  '),
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.link_off_rounded,
                                color: Colors.white38),
                            onPressed: () => _unlink(p),
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PatientDetailPage(
                                patientId: p['id'] as String,
                                patientName:
                                    (p['full_name'] ?? 'Patient').toString(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ======================= BUTIRAN PESAKIT (BACA SAHAJA) =======================

class PatientDetailPage extends StatefulWidget {
  final String patientId;
  final String patientName;

  const PatientDetailPage({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  @override
  State<PatientDetailPage> createState() => _PatientDetailPageState();
}

class _PatientDetailPageState extends State<PatientDetailPage> {
  List<Map<String, dynamic>> _meds = [];
  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _alerts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        supabase
            .from('medications')
            .select('medication_name, dosage, slot_number, scheduled_time')
            .eq('user_id', widget.patientId)
            .order('slot_number', ascending: true),
        supabase
            .from('pill_logs')
            .select('medication_name, status, dispensed_at')
            .eq('user_id', widget.patientId)
            .order('dispensed_at', ascending: false)
            .limit(30),
      ]);
      // Missed dose alerts (hidden if the table/policy is not set up yet)
      List<Map<String, dynamic>> alerts = [];
      try {
        final rows = await supabase
            .from('missed_dose_alerts')
            .select('medication_name, alert_date, created_at')
            .eq('user_id', widget.patientId)
            .order('created_at', ascending: false)
            .limit(10);
        alerts = List<Map<String, dynamic>>.from(rows);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _alerts = alerts;
        _meds = List<Map<String, dynamic>>.from(results[0]);
        _logs = List<Map<String, dynamic>>.from(results[1]);
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load data.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isRealMed(Map<String, dynamic> m) {
    final n = m['medication_name']?.toString().trim() ?? '';
    return n.isNotEmpty && n != 'Empty' && n != 'Unassigned';
  }

  @override
  Widget build(BuildContext context) {
    final meds = _meds.where(_isRealMed).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        title: Text(widget.patientName),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: _bgDecoration,
        child: RefreshIndicator(
          color: _accent,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(child: CircularProgressIndicator(color: _accent)),
                )
              else if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.redAccent))
              else ...[
                if (_alerts.isNotEmpty) ...[
                  const Text('Missed Dose Alerts',
                      style: TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  ..._alerts.map(
                    (a) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _glass(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Colors.orangeAccent),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${a['medication_name']} was not taken',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14),
                              ),
                            ),
                            Text(
                              a['created_at'] != null
                                  ? DateTime.parse(a['created_at'].toString())
                                      .toLocal()
                                      .toString()
                                      .substring(0, 16)
                                  : '',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                const Text('Medication Schedule',
                    style: TextStyle(
                        color: _accent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                if (meds.isEmpty)
                  _glass(
                    child: const Text('No medications registered.',
                        style: TextStyle(color: Colors.white54)),
                  )
                else
                  ...meds.map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _glass(
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _accent.withValues(alpha: 0.2),
                            child: Text('S${m['slot_number']}',
                                style: const TextStyle(
                                    color: _accent, fontSize: 12)),
                          ),
                          title: Text(
                            (m['medication_name'] ?? '').toString(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            (m['dosage'] ?? '').toString(),
                            style: const TextStyle(color: Colors.white54),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              border: Border.all(color: _accent),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _fmtTime(m['scheduled_time']),
                              style: const TextStyle(
                                  color: _accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                const Text('Dispense History',
                    style: TextStyle(
                        color: _accent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                if (_logs.isEmpty)
                  _glass(
                    child: const Text('No dispense records yet.',
                        style: TextStyle(color: Colors.white54)),
                  )
                else
                  ..._logs.map((log) {
                    final status = log['status']?.toString() ?? '';
                    final time = log['dispensed_at'] != null
                        ? DateTime.parse(log['dispensed_at'].toString())
                            .toLocal()
                            .toString()
                            .substring(0, 16)
                        : '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _glass(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (log['medication_name'] ?? 'Medication')
                                        .toString(),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14),
                                  ),
                                  const SizedBox(height: 2),
                                  Text('Status: $status',
                                      style: const TextStyle(
                                          color: _accent, fontSize: 11)),
                                ],
                              ),
                            ),
                            Text(time,
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 10)),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}