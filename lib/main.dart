import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:firebase_core/firebase_core.dart';

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
import 'fcm_service.dart';

// Global instance Supabase & Navigator Key
final supabase = Supabase.instance.client;
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Inisialisasi pangkalan data timezone
  tz.initializeTimeZones();
  try {
    final String timeZoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneName));
  } catch (e) {
    // Fallback jika gagal dapatkan zon masa peranti
    tz.setLocalLocation(tz.getLocation('Asia/Kuala_Lumpur'));
  }

  // 2. Inisialisasi Supabase
  await Supabase.initialize(
    url: 'https://avaeybsttlviabcuczxc.supabase.co',
    publishableKey: 'sb_publishable_ZVd9xk054Cwt76QAKIWnoA_BJYz4Bog',
  );

  // 3. Inisialisasi Firebase & FCM Service (Bungkus dalam try-catch elak layar putih jika run di platform lain)
  try {
    await Firebase.initializeApp();
    await FcmService().init();
  } catch (e) {
    debugPrint("Ralat Inisialisasi Firebase / FCM: $e");
  }

  // 4. Inisialisasi NotificationService Tempatan
  try {
    await NotificationService().init(navigatorKey);
  } catch (e) {
    debugPrint("Ralat Inisialisasi NotificationService: $e");
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
            return const DashboardScreen();
          }
          return const LoginPage();
        },
      ),
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
              _buildGlassContainer(
                borderColor: const Color(0xFF00B4D8).withValues(alpha: 0.5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.notifications_active_outlined, color: Color(0xFF00B4D8), size: 18),
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
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orangeAccent, width: 0.8),
                          ),
                          child: const Text(
                            'DUE 08:00 AM',
                            style: TextStyle(
                              color: Colors.orangeAccent,
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
                          child: const Icon(Icons.medication_rounded, color: Color(0xFF00B4D8), size: 28),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Paracetamol (Slot 1)',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '1 Tablet after meal • 500mg',
                                style: TextStyle(color: Colors.white60, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          NotificationService().triggerInstantAlarmTest(
                            context: context,
                            medicationName: 'Paracetamol',
                            slotNumber: 1,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00B4D8),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        icon: const Icon(Icons.alarm, size: 18),
                        label: const Text(
                          'TRIGGER ALARM TEST',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
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