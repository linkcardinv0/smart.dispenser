import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilePage extends StatelessWidget {
  final User? user;
  final String patientName;
  final String phoneNumber;
  final String patientAgeGender;
  final String emergencyContact;
  final String attendingDoctor;
  final String medicalConditions;
  final VoidCallback onEditPressed;

  const ProfilePage({
    super.key,
    required this.user,
    required this.patientName,
    required this.phoneNumber,
    required this.patientAgeGender,
    required this.emergencyContact,
    required this.attendingDoctor,
    required this.medicalConditions,
    required this.onEditPressed,
  });

  @override
  Widget build(BuildContext context) {
    final String email = user?.email ?? 'user@example.com';

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF0284C7)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 70, left: 20, right: 20, bottom: 20),
          child: Column(
            children: [
              // 1. Kad Header Profil
              _buildGlassContainer(
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 40,
                      backgroundColor: Color(0xFF00B4D8),
                      child: Icon(Icons.person, size: 48, color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      patientName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: const TextStyle(color: Color(0xFF00B4D8), fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: onEditPressed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00B4D8),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Edit Profile Details'),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 2. Kad Maklumat Peribadi & Kesihatan
              _buildGlassContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Personal & Medical Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00B4D8),
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 20),
                    _buildPatientInfoRow('Nama Penuh', patientName),
                    const SizedBox(height: 10),
                    _buildPatientInfoRow('Nombor Telefon', phoneNumber),
                    const SizedBox(height: 10),
                    _buildPatientInfoRow('Umur / Jantina', patientAgeGender),
                    const SizedBox(height: 10),
                    _buildPatientInfoRow('No. Kecemasan', emergencyContact),
                    const SizedBox(height: 10),
                    _buildPatientInfoRow('Doktor', attendingDoctor),
                    const SizedBox(height: 10),
                    _buildPatientInfoRow('Masalah Kesihatan', medicalConditions),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassContainer({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
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

  Widget _buildPatientInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white54,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}