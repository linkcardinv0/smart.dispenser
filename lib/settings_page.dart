import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main.dart'; // Mengakses instance global 'supabase'
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'web_push_service.dart';
import 'notification_service.dart';

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

  late final Future<String?> _inviteFuture = _loadInviteCode();

  Future<String?> _loadInviteCode() async {
    if (widget.user == null) return null;
    try {
      final r = await supabase.rpc('get_my_invite_code');
      return r as String?;
    } catch (_) {
      return null;
    }
  }

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
                  leading: const Icon(Icons.notifications_active,
                      color: Color(0xFF00B4D8)),
                  title: const Text('Enable Phone Reminders',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                    'Tap once to receive medication alerts on this device',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  onTap: () async {
                    bool ok;
                    if (kIsWeb) {
                      // Mesti panggilan pertama dalam tap (syarat iOS)
                      ok = await enableWebPush();
                    } else {
                      try {
                        await NotificationService().syncFromDatabase();
                        ok = true;
                      } catch (_) {
                        ok = false;
                      }
                    }
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(ok
                          ? 'Reminders enabled on this device'
                          : 'Not enabled. On iPhone, first Add to Home Screen, open the app from the icon, then try again.'),
                      backgroundColor: const Color(0xFF00B4D8),
                      behavior: SnackBarBehavior.floating,
                    ));
                  },
                ),
              ),
              const SizedBox(height: 16),
              FutureBuilder<String?>(
                future: _inviteFuture,
                builder: (context, snap) {
                  final code = snap.data;
                  if (code == null || code.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildGlassContainer(
                      child: ListTile(
                        leading: const Icon(Icons.group_add_rounded,
                            color: Color(0xFF00B4D8)),
                        title: const Text('Kod Jemputan Penjaga',
                            style: TextStyle(color: Colors.white)),
                        subtitle: Text(
                          code,
                          style: const TextStyle(
                            color: Color(0xFF00B4D8),
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy_rounded,
                              color: Colors.white54),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: code));
                            if (!context.mounted) return;
                           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Kod disalin'),
                            backgroundColor: Color(0xFF00B4D8),
                            behavior: SnackBarBehavior.floating,
                            ));
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
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