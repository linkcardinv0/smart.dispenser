import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main.dart'; // Mengakses instance global 'supabase'

class SettingsPage extends StatefulWidget {
  final User? user;

  const SettingsPage({super.key, required this.user});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _pushNotifications = true;
  bool _soundAlerts = true;
  bool _biometricUnlock = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF0284C7)],
          begin: Alignment.bottomRight,
          end: Alignment.topLeft,
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 70, left: 20, right: 20, bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Settings & Preferences',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              _buildGlassContainer(
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _pushNotifications,
                      activeThumbColor: const Color(0xFF00B4D8),
                      title: const Text('Push Notifications', style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Reminders for pill dispensing', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      onChanged: (val) => setState(() => _pushNotifications = val),
                    ),
                    const Divider(color: Colors.white12),
                    SwitchListTile(
                      value: _soundAlerts,
                      activeThumbColor: const Color(0xFF00B4D8),
                      title: const Text('Sound Alerts', style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Play sound on low pill inventory', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      onChanged: (val) => setState(() => _soundAlerts = val),
                    ),
                    const Divider(color: Colors.white12),
                    SwitchListTile(
                      value: _biometricUnlock,
                      activeThumbColor: const Color(0xFF00B4D8),
                      title: const Text('Biometric Security', style: TextStyle(color: Colors.white)),
                      subtitle: const Text('Require FaceID / Fingerprint', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      onChanged: (val) => setState(() => _biometricUnlock = val),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildGlassContainer(
                child: ListTile(
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: const Text('Log Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    widget.user?.email ?? '',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  onTap: () async {
                    await supabase.auth.signOut();
                  },
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
}