import 'package:flutter/material.dart';
import 'notification_service.dart';

class AlarmScreen extends StatelessWidget {
  const AlarmScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final payload = ModalRoute.of(context)?.settings.arguments as String? ?? '';
    final parts = payload.split('|');
    final medName = parts.isNotEmpty ? parts[0] : 'Medication';
    final slotInfo = parts.length > 1 ? parts[1] : '';

    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                children: [
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00B4D8).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.alarm_on_rounded,
                      size: 80,
                      color: Color(0xFF00B4D8),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'SMART DISPENSE ALARM',
                    style: TextStyle(
                      color: Color(0xFF00B4D8),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    medName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    slotInfo,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00B4D8),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () {
                        NotificationService().stopAlarm();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.check_circle_rounded, size: 28),
                      label: const Text(
                        'TAKE DOSE NOW',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      NotificationService().stopAlarm();
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Dismiss Alarm',
                      style: TextStyle(color: Colors.white60, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}