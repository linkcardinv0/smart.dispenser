import 'dart:ui';
import 'package:flutter/material.dart';
import 'main.dart'; // Mengakses instance global 'supabase'

class PillLogsSheet extends StatelessWidget {
  const PillLogsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.9),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: const Color(0xFF00B4D8).withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Sheet
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.history_rounded, color: Color(0xFF00B4D8), size: 24),
                      SizedBox(width: 10),
                      Text(
                        'Dispensing History Logs',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white60),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 20),

              // StreamBuilder dari jadual 'pill_logs' Supabase
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: supabase
                      .from('pill_logs')
                      .stream(primaryKey: ['id'])
                      .eq('user_id', user?.id ?? '')
                      .order('dispensed_at', ascending: false),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error loading logs: ${snapshot.error}',
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      );
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Color(0xFF00B4D8)),
                      );
                    }

                    final logs = snapshot.data ?? [];

                    if (logs.isEmpty) {
                      return const Center(
                        child: Text(
                          'No dispensing history recorded yet.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        final medName = log['medication_name']?.toString() ?? 'Medication';
                        final statusStr = log['status']?.toString() ?? 'DISPENSED';
                        final String timeStr = log['dispensed_at'] != null
                            ? DateTime.parse(log['dispensed_at'].toString())
                                .toLocal()
                                .toString()
                                .substring(0, 16)
                            : 'Just now';

                        final bool isVision = statusStr.contains('Vision') || statusStr.contains('TAKEN');

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isVision
                                  ? const Color(0xFF00B4D8).withValues(alpha: 0.3)
                                  : Colors.orangeAccent.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: isVision
                                    ? const Color(0xFF00B4D8).withValues(alpha: 0.2)
                                    : Colors.orangeAccent.withValues(alpha: 0.2),
                                child: Icon(
                                  isVision ? Icons.remove_red_eye : Icons.touch_app,
                                  color: isVision
                                      ? const Color(0xFF00B4D8)
                                      : Colors.orangeAccent,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      medName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Status: $statusStr',
                                      style: TextStyle(
                                        color: isVision
                                            ? const Color(0xFF00B4D8)
                                            : Colors.orangeAccent,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                timeStr,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}