import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart'; // Ditambah untuk semakan kIsWeb
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

import 'login_page.dart';
import 'add_medication_page.dart';
import 'dispenser_status_page.dart';
import 'reminders_page.dart';
import 'profile_page.dart';
import 'settings_page.dart';
import 'drugs_header_bar.dart';
import 'ai_chat_sheet.dart';
import 'pill_logs_sheet.dart';
import 'notification_service.dart';
import 'alarm_screen.dart';
import 'caregiver_dashboard.dart';

// Global instance Supabase & Navigator Key
final supabase = Supabase.instance.client;
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ============================================================
// TETAPAN LOG PIL  (UBAH IKUT SKEMA SUPABASE KAU)
// ============================================================
const String kLogsTable = 'pill_logs';
const String kLogsUserColumn = 'user_id';
const String kLogsNameColumn = 'medication_name';
const String kLogsStatusColumn = 'status';
const String kLogsTimeColumn = 'dispensed_at';
// Status yang mengandungi kata kunci ini dikira "dah diambil/dikeluarkan"
// (huruf besar kecil tak penting). Status lalai log = 'DISPENSED'.
const List<String> kTakenKeywords = ['DISPENSED', 'TAKEN', 'VISION'];
// Log dikira untuk dos tertentu jika masanya dalam tetingkap ini
// berbanding masa jadual dos tersebut.
const Duration kTakenWindowBefore = Duration(minutes: 60);
const Duration kTakenWindowAfter = Duration(hours: 3);
// Berapa lama selepas masa dos, ia masih dipaparkan sebagai OVERDUE
const Duration kOverdueGrace = Duration(minutes: 60);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Inisialisasi pangkalan data timezone
  tz.initializeTimeZones();
  if (!kIsWeb) {
    try {
      final String timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (e) {
      // Fallback jika gagal dapatkan zon masa peranti
      tz.setLocalLocation(tz.getLocation('Asia/Kuala_Lumpur'));
    }
  } else {
    // Tetapan zon masa lalai untuk pelayar Web
    tz.setLocalLocation(tz.getLocation('Asia/Kuala_Lumpur'));
  }

  // 2. Inisialisasi Supabase (Disokong sepenuhnya pada Web & Mobile)
  await Supabase.initialize(
    url: 'https://avaeybsttlviabcuczxc.supabase.co',
    publishableKey: 'sb_publishable_ZVd9xk054Cwt76QAKIWnoA_BJYz4Bog',
  );

  // Notifikasi tempatan (HANYA untuk app Android native). Web guna Web Push dari Supabase.
  if (!kIsWeb) {
    // 3. Inisialisasi NotificationService Tempatan (alarm Android)
    try {
      await NotificationService().init(navigatorKey);
    } catch (e) {
      debugPrint("Ralat Inisialisasi NotificationService: $e");
    }
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartDispense AI',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      routes: {
        '/alarm': (context) => const AlarmScreen(),
      },
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00B4D8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0B1120),
      ),
      home: StreamBuilder<AuthState>(
        stream: supabase.auth.onAuthStateChange,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: Color(0xFF00B4D8)),
              ),
            );
          }
          final session =
              snapshot.data?.session ?? supabase.auth.currentSession;
          if (session != null) {
            return const RoleGate();
          }
          return const LoginPage();
        },
      ),
    );
  }
}

/// Pilih skrin ikut peranan akaun (patient / caregiver) dalam jadual 'profiles'.
class RoleGate extends StatefulWidget {
  const RoleGate({super.key});

  @override
  State<RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<RoleGate> {
  late final Future<String> _roleFuture = _loadRole();

  Future<String> _loadRole() async {
    final user = supabase.auth.currentUser;
    if (user == null) return 'patient';
    try {
      final data = await supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      return (data?['role'] as String?) ?? 'patient';
    } catch (e) {
      debugPrint('Gagal baca peranan: $e');
      return 'patient';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _roleFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF00B4D8)),
            ),
          );
        }
        return snapshot.data == 'caregiver'
            ? const CaregiverDashboard()
            : const DashboardScreen();
      },
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  bool _isLoadingProfile = true;

  // Patient Profile State
  String _patientName = 'John Doe';
  String _phoneNumber = '+1 (555) 012-3456';
  String _patientAgeGender = '68 yrs / Male';
  String _emergencyContact = '+1 (555) 019-2834';
  String _attendingDoctor = 'Dr. Robert Chen (Cardiology)';
  String _medicalConditions = 'Hypertension, Type 2 Diabetes';

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
    _syncAlarms();
  }

  /// Jadualkan semula semua alarm ubat setiap kali dashboard dibuka
  /// (selepas log masuk, app dibuka semula, reboot, kemas kini app).
  Future<void> _syncAlarms() async {
    if (kIsWeb) return;
    try {
      await NotificationService().syncFromDatabase();
    } catch (e) {
      debugPrint('Gagal menyegerakkan alarm: $e');
    }
  }

  /// Fetch user profile from Supabase Database
  Future<void> _fetchUserProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final data = await supabase
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();

        if (data != null && mounted) {
          setState(() {
            _patientName = data['full_name'] ?? _patientName;
            _phoneNumber = data['phone_number'] ?? _phoneNumber;
            _patientAgeGender = data['age_gender'] ?? _patientAgeGender;
            _emergencyContact = data['emergency_contact'] ?? _emergencyContact;
            _attendingDoctor = data['attending_doctor'] ?? _attendingDoctor;
            _medicalConditions = data['medical_conditions'] ?? _medicalConditions;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching profile: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingProfile = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() {
      _currentIndex = index;
    });
  }

  /// Show Edit Dialog and Save directly to Supabase
  void _showEditProfileDialog() {
    final nameController = TextEditingController(text: _patientName);
    final phoneController = TextEditingController(text: _phoneNumber);
    final ageGenderController = TextEditingController(text: _patientAgeGender);
    final contactController = TextEditingController(text: _emergencyContact);
    final doctorController = TextEditingController(text: _attendingDoctor);
    final conditionsController = TextEditingController(text: _medicalConditions);

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Edit Patient Profile',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildGlassTextField(nameController, 'Full Name'),
                      const SizedBox(height: 12),
                      _buildGlassTextField(phoneController, 'User Phone Number'),
                      const SizedBox(height: 12),
                      _buildGlassTextField(ageGenderController, 'Age / Gender'),
                      const SizedBox(height: 12),
                      _buildGlassTextField(contactController, 'Emergency Contact'),
                      const SizedBox(height: 12),
                      _buildGlassTextField(doctorController, 'Attending Doctor'),
                      const SizedBox(height: 12),
                      _buildGlassTextField(conditionsController, 'Medical Conditions'),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('CANCEL', style: TextStyle(color: Colors.white60)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00B4D8).withValues(alpha: 0.8),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () async {
                              final name = nameController.text.trim();
                              final phone = phoneController.text.trim();
                              final ageGender = ageGenderController.text.trim();
                              final contact = contactController.text.trim();
                              final doctor = doctorController.text.trim();
                              final conditions = conditionsController.text.trim();

                              setState(() {
                                _patientName = name;
                                _phoneNumber = phone;
                                _patientAgeGender = ageGender;
                                _emergencyContact = contact;
                                _attendingDoctor = doctor;
                                _medicalConditions = conditions;
                              });

                              final user = supabase.auth.currentUser;
                              if (user != null) {
                                try {
                                  await supabase.from('profiles').upsert({
                                    'id': user.id,
                                    'full_name': name,
                                    'phone_number': phone,
                                    'age_gender': ageGender,
                                    'emergency_contact': contact,
                                    'attending_doctor': doctor,
                                    'medical_conditions': conditions,
                                    'updated_at': DateTime.now().toIso8601String(),
                                  });
                                } catch (e) {
                                  debugPrint("Error saving profile: $e");
                                }
                              }

                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                            child: const Text('SAVE'),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGlassTextField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF00B4D8)),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.25),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF00B4D8)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    if (_isLoadingProfile) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF00B4D8)),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: DrugsHeaderBar(
        onSignOut: () => supabase.auth.signOut(),
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        children: [
          _buildMainDashboardView(context, user),
          const DispenserStatusPage(),
          const RemindersPage(),
          ProfilePage(
            user: user,
            patientName: _patientName,
            phoneNumber: _phoneNumber,
            patientAgeGender: _patientAgeGender,
            emergencyContact: _emergencyContact,
            attendingDoctor: _attendingDoctor,
            medicalConditions: _medicalConditions,
            onEditPressed: _showEditProfileDialog,
          ),
          SettingsPage(user: user),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF00B4D8), Color(0xFF0077B6)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00B4D8).withValues(alpha: 0.5),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: const AIChatSheet(),
              ),
            );
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: const Icon(
            Icons.auto_awesome,
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _buildGlassQuickNavBar(),
    );
  }

  Widget _buildMainDashboardView(BuildContext context, User? user) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF0284C7)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 20, left: 16, right: 16, bottom: 20),
          child: Column(
            children: [
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.white24,
                      shape: BoxShape.circle,
                    ),
                    child: const CircleAvatar(
                      radius: 40,
                      backgroundColor: Color(0xFF00B4D8),
                      child: Icon(Icons.person, size: 48, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _patientName.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${user?.email ?? 'user@example.com'} | $_patientAgeGender',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00B4D8).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF00B4D8), width: 0.8),
                    ),
                    child: const Text(
                      'DISPENSER CONNECTED',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00B4D8),
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildGlassContainer(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 4,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.82,
                  children: [
                    _buildGridMenuItem(
                      icon: Icons.add_circle_outline_rounded,
                      label: 'Add Med',
                      badgeText: 'NEW',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AddMedicationPage(),
                          ),
                        );
                      },
                    ),
                    _buildGridMenuItem(
                      icon: Icons.view_carousel_rounded,
                      label: 'Cartridges',
                      onTap: () => _onTabTapped(1),
                    ),
                    _buildGridMenuItem(
                      icon: Icons.shield_outlined,
                      label: 'Safety AI',
                      badgeText: 'CHECK',
                      onTap: () => _onTabTapped(2),
                    ),
                    _buildGridMenuItem(
                      icon: Icons.history_rounded,
                      label: 'Pill Logs',
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (context) => const PillLogsSheet(),
                        );
                      },
                    ),
                    _buildGridMenuItem(
                      icon: Icons.alarm_rounded,
                      label: 'Schedules',
                      onTap: () => _onTabTapped(2),
                    ),
                    _buildGridMenuItem(
                      icon: Icons.contact_phone_outlined,
                      label: 'Emergency',
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: const Color(0xFF1E293B),
                            title: const Text('Emergency Contact', style: TextStyle(color: Colors.white)),
                            content: Text(
                              'Doctor: $_attendingDoctor\nEmergency Contact: $_emergencyContact\nConditions: $_medicalConditions',
                              style: const TextStyle(color: Colors.white70, height: 1.5),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('CLOSE', style: TextStyle(color: Color(0xFF00B4D8))),
                              )
                            ],
                          ),
                        );
                      },
                    ),
                    _buildGridMenuItem(
                      icon: Icons.person_outline_rounded,
                      label: 'Profile',
                      onTap: () => _onTabTapped(3),
                    ),
                    _buildGridMenuItem(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      onTap: () => _onTabTapped(4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Kad dos seterusnya: sync terus dengan jadual 'medications'
              _buildGlassContainer(
                borderColor: const Color(0xFF00B4D8).withValues(alpha: 0.5),
                child: const NextDoseCard(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGridMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? badgeText,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF00B4D8).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF00B4D8).withValues(alpha: 0.4),
                  ),
                ),
                child: Icon(icon, color: const Color(0xFF00B4D8), size: 24),
              ),
              if (badgeText != null)
                Positioned(
                  top: -6,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badgeText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassQuickNavBar() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavTabButton(index: 0, icon: Icons.home_rounded, label: 'Home'),
                  _buildNavTabButton(index: 1, icon: Icons.view_carousel_rounded, label: 'Slots'),
                  _buildNavTabButton(index: 2, icon: Icons.security_rounded, label: 'Safety'),
                  _buildNavTabButton(index: 3, icon: Icons.person_rounded, label: 'Profile'),
                  _buildNavTabButton(index: 4, icon: Icons.settings_rounded, label: 'Settings'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavTabButton({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _currentIndex == index;

    return InkWell(
      onTap: () => _onTabTapped(index),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00B4D8).withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: const Color(0xFF00B4D8).withValues(alpha: 0.6))
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF00B4D8) : Colors.white60,
              size: 20,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassContainer({
    required Widget child,
    Color? borderColor,
    EdgeInsetsGeometry? padding,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: borderColor ?? Colors.white.withValues(alpha: 0.18),
              width: 1.5,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ============================================================
// NEXT UPCOMING DOSE  (live dari 'medications' + log pil)
// ============================================================

class _NextDose {
  final Map<String, dynamic> med;
  final DateTime time;
  final bool overdue;
  const _NextDose({
    required this.med,
    required this.time,
    required this.overdue,
  });
}

class NextDoseCard extends StatefulWidget {
  const NextDoseCard({super.key});

  @override
  State<NextDoseCard> createState() => _NextDoseCardState();
}

class _NextDoseCardState extends State<NextDoseCard> {
  late final Stream<List<Map<String, dynamic>>> _medsStream;
  late final Stream<List<Map<String, dynamic>>> _logsStream;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    final uid = supabase.auth.currentUser?.id ?? '';
    _medsStream = supabase
        .from('medications')
        .stream(primaryKey: ['id']).eq('user_id', uid);
    _logsStream = supabase
        .from(kLogsTable)
        .stream(primaryKey: ['id']).eq(kLogsUserColumn, uid);

    // Refresh setiap 30 saat supaya label DUE/OVERDUE sentiasa tepat
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool _isRealMed(Map<String, dynamic> m) {
    final n = m['medication_name']?.toString().trim() ?? '';
    return n.isNotEmpty && n != 'Empty' && n != 'Unassigned';
  }

  bool _isToday(DateTime d, DateTime now) =>
      d.year == now.year && d.month == now.month && d.day == now.day;

  /// Log hari ini (masa tempatan) yang dikira sebagai dah diambil/dikeluarkan.
  List<({String name, DateTime time})> _todayTakenLogs(
      List<Map<String, dynamic>> logs, DateTime now) {
    final result = <({String name, DateTime time})>[];
    for (final log in logs) {
      final status =
          (log[kLogsStatusColumn]?.toString() ?? 'DISPENSED').toUpperCase();
      if (!kTakenKeywords.any(status.contains)) continue;

      final raw = log[kLogsTimeColumn]?.toString();
      final parsed = raw == null ? null : DateTime.tryParse(raw);
      if (parsed == null) continue;
      final local = parsed.toLocal();
      if (!_isToday(local, now)) continue;

      final name =
          (log[kLogsNameColumn]?.toString() ?? '').trim().toLowerCase();
      result.add((name: name, time: local));
    }
    return result;
  }

  /// Cari dos seterusnya:
  /// - dos hari ini yang dah diambil -> dikira esok
  /// - dos hari ini yang belum diambil & sudah lepas dalam tempoh grace -> OVERDUE
  /// - dos hari ini yang belum tiba -> hari ini
  /// - selain itu -> esok
  _NextDose? _findNextDose(
    List<Map<String, dynamic>> meds,
    List<Map<String, dynamic>> logs,
  ) {
    final now = DateTime.now();
    final todayLogs = _todayTakenLogs(logs, now);
    _NextDose? best;

    for (final m in meds) {
      if (!_isRealMed(m)) continue;

      final t = m['scheduled_time']?.toString();
      if (t == null || !t.contains(':')) continue;
      final parts = t.split(':'); // support "08:00" & "08:00:00"
      final h = int.tryParse(parts[0]);
      final min = int.tryParse(parts[1]);
      if (h == null || min == null) continue;

      final medName =
          (m['medication_name']?.toString() ?? '').trim().toLowerCase();
      final todayDt = DateTime(now.year, now.month, now.day, h, min);
      final alreadyTaken = todayLogs.any((l) =>
          l.name == medName &&
          l.time.isAfter(todayDt.subtract(kTakenWindowBefore)) &&
          l.time.isBefore(todayDt.add(kTakenWindowAfter)));

      DateTime candidate;
      bool overdue = false;

      if (alreadyTaken) {
        candidate = todayDt.add(const Duration(days: 1));
      } else if (!todayDt.isBefore(now)) {
        candidate = todayDt;
      } else if (now.difference(todayDt) <= kOverdueGrace) {
        candidate = todayDt;
        overdue = true;
      } else {
        candidate = todayDt.add(const Duration(days: 1));
      }

      if (best == null || candidate.isBefore(best.time)) {
        best = _NextDose(med: m, time: candidate, overdue: overdue);
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _medsStream,
      builder: (context, medsSnap) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _logsStream,
          builder: (context, logsSnap) {
            // Kalau table log tiada / error, teruskan tanpa tapis log
            final logs = logsSnap.hasError
                ? <Map<String, dynamic>>[]
                : (logsSnap.data ?? <Map<String, dynamic>>[]);
            final next = _findNextDose(medsSnap.data ?? [], logs);

            String dueLabel = 'NO SCHEDULE';
            String title = 'Tiada ubat dijadualkan';
            String subtitle = 'Tambah ubat & tetapkan masa di tab Safety';
            Color badgeColor = Colors.white54;

            if (next != null) {
              final now = DateTime.now();
              final timeStr =
                  TimeOfDay.fromDateTime(next.time).format(context);
              if (next.overdue) {
                dueLabel = 'OVERDUE $timeStr';
                badgeColor = Colors.redAccent;
              } else if (_isToday(next.time, now)) {
                dueLabel = 'DUE $timeStr';
                badgeColor = Colors.orangeAccent;
              } else {
                dueLabel = 'TOMORROW $timeStr';
                badgeColor = Colors.orangeAccent;
              }
              title =
                  '${next.med['medication_name']} (Slot ${next.med['slot_number']})';
              subtitle = next.med['dosage']?.toString() ?? '';
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.notifications_active_outlined,
                            color: Color(0xFF00B4D8), size: 18),
                        SizedBox(width: 8),
                        Text(
                          'NEXT UPCOMING DOSE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00B4D8),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: badgeColor, width: 0.8),
                      ),
                      child: Text(
                        dueLabel,
                        style: TextStyle(
                          color: badgeColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00B4D8).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.medication_rounded,
                          color: Color(0xFF00B4D8), size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}