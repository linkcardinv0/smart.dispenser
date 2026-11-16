import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main.dart'; // Rujukan instance 'supabase'
import 'web_push_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ageController = TextEditingController();
  bool _isLoading = false;
  bool _isSignUp = false;
  String _role = 'patient'; // 'patient' atau 'caregiver'

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _handleAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnackBar('Sila isi e-mel dan kata laluan.');
      return;
    }

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final age = int.tryParse(_ageController.text.trim());

    if (_isSignUp) {
      if (name.isEmpty || phone.isEmpty) {
        _showSnackBar('Sila isi nama dan nombor telefon.');
        return;
      }
      if (_role == 'patient' && age == null) {
        _showSnackBar('Sila isi umur pesakit.');
        return;
      }
      if (age != null && (age < 1 || age > 120)) {
        _showSnackBar('Sila masukkan umur yang sah.');
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      if (_isSignUp) {
        // Pendaftaran Supabase Auth
        // Maklumat profil dihantar sebagai metadata. Trigger pangkalan data
        // menyalinnya ke jadual 'profiles' (berfungsi walaupun e-mel belum disahkan).
        final AuthResponse res = await supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'full_name': name,
            'phone_number': phone,
            'age_gender': age != null ? '$age yrs' : null,
            'role': _role,
          },
        );

        if (res.user != null) {
          // 🟢 Sambung semula langganan Web Push peranti ini selepas mendaftar
          await syncWebPushSubscription();
        }

        _showSnackBar('Pendaftaran berjaya! Sila semak e-mel pengesahan jika ada.');
      } else {
        // Log Masuk Supabase Auth
        final AuthResponse res = await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );

        if (res.user != null) {
          // 🟢 Sambung semula langganan Web Push peranti ini selepas log masuk
          await syncWebPushSubscription();
        }
      }
    } on AuthException catch (error) {
      _showSnackBar(error.message);
    } catch (error) {
      _showSnackBar('Ralat tidak dijangka berlaku.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: const Color(0xFF00B4D8),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _roleChip(String value, String label, IconData icon) {
    final selected = _role == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _role = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF00B4D8).withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFF00B4D8)
                  : Colors.white.withValues(alpha: 0.15),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: selected ? const Color(0xFF00B4D8) : Colors.white54),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF00B4D8)),
        prefixIcon: Icon(icon, color: const Color(0xFF00B4D8)),
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
    return Scaffold(
      body: Container(
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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.medication_liquid_rounded,
                          size: 64,
                          color: Color(0xFF00B4D8),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'SmartDispense AI',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isSignUp ? 'Daftar Akaun Baharu' : 'Log Masuk Akses Dispenser',
                          style: const TextStyle(color: Colors.white60, fontSize: 13),
                        ),
                        const SizedBox(height: 28),
                        if (_isSignUp) ...[
                          Row(
                            children: [
                              _roleChip('patient', 'Pesakit',
                                  Icons.personal_injury_outlined),
                              const SizedBox(width: 12),
                              _roleChip('caregiver', 'Penjaga',
                                  Icons.volunteer_activism_outlined),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildField(
                            controller: _nameController,
                            label: 'Nama Penuh',
                            icon: Icons.person_outline_rounded,
                            keyboardType: TextInputType.name,
                          ),
                          const SizedBox(height: 16),
                          _buildField(
                            controller: _phoneController,
                            label: 'Nombor Telefon',
                            icon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 16),
                          _buildField(
                            controller: _ageController,
                            label: _role == 'patient' ? 'Umur' : 'Umur (pilihan)',
                            icon: Icons.cake_outlined,
                            keyboardType: TextInputType.number,
                            formatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(3),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'E-mel',
                            labelStyle: const TextStyle(color: Color(0xFF00B4D8)),
                            prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF00B4D8)),
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
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Kata Laluan',
                            labelStyle: const TextStyle(color: Color(0xFF00B4D8)),
                            prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF00B4D8)),
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
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleAuth,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00B4D8),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : Text(
                                    _isSignUp ? 'DAFTAR' : 'LOG MASUK',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () {
                            setState(() => _isSignUp = !_isSignUp);
                          },
                          child: Text(
                            _isSignUp
                                ? 'Sudah ada akaun? Log Masuk'
                                : 'Belum ada akaun? Daftar Sini',
                            style: const TextStyle(color: Color(0xFF00B4D8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}