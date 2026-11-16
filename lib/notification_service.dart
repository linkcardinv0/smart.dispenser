import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'medication_alarm_channel_v3';
  static const String _channelName = 'Medication Alarm Channel';

  Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          navigatorKey.currentState?.pushNamed(
            '/alarm',
            arguments: response.payload,
          );
        }
      },
    );

    final androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Daily medication reminders',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await androidImplementation.createNotificationChannel(channel);
      await androidImplementation.requestNotificationsPermission();
    }
  }

  /// Pastikan kebenaran notifikasi & penggera tepat diberikan.
  /// Melempar StateError jika masih belum dibenarkan.
  Future<void> _ensurePermissions() async {
    final androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation == null) return;

    var notificationsEnabled =
        await androidImplementation.areNotificationsEnabled() ?? false;
    if (!notificationsEnabled) {
      await androidImplementation.requestNotificationsPermission();
      notificationsEnabled =
          await androidImplementation.areNotificationsEnabled() ?? false;
    }
    if (!notificationsEnabled) {
      throw StateError(
        'Notification permission is turned off. Enable notifications for the '
        'SmartDispense AI app in your phone settings.',
      );
    }

    var canScheduleExact =
        await androidImplementation.canScheduleExactNotifications() ?? true;
    if (!canScheduleExact) {
      await androidImplementation.requestExactAlarmsPermission();
      canScheduleExact =
          await androidImplementation.canScheduleExactNotifications() ?? false;
    }
    if (!canScheduleExact) {
      throw StateError(
        'Exact alarm permission has not been granted. Allow "Alarms & '
        'reminders" for SmartDispense AI in your phone settings.',
      );
    }
  }

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Daily medication reminders',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      fullScreenIntent: true,
      autoCancel: true,
      playSound: true,
      enableVibration: true,
    ),
  );

  /// Menjadualkan notifikasi ubat setiap hari pada masa yang dipilih.
  Future<void> scheduleMedicationAlarm({
    required int id,
    required String medicationName,
    required int slotNumber,
    required DateTime scheduledTime,
    bool checkPermissions = true,
  }) async {
    if (checkPermissions) await _ensurePermissions();

    final location = tz.local;
    final now = tz.TZDateTime.now(location);

    // Bina masa menggunakan zon masa tempatan (bukan DateTime biasa)
    var tzScheduledTime = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day,
      scheduledTime.hour,
      scheduledTime.minute,
    );

    // Jika masa hari ini sudah lepas, mulakan esok
    if (!tzScheduledTime.isAfter(now)) {
      tzScheduledTime = tzScheduledTime.add(const Duration(days: 1));
    }

    await _notificationsPlugin.cancel(id);
    await _notificationsPlugin.zonedSchedule(
      id,
      '⏰ TIME TO TAKE YOUR MEDICATION!',
      'Please take $medicationName from Slot $slotNumber',
      tzScheduledTime,
      _details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: '$medicationName|Slot $slotNumber',
    );

    debugPrint('Alarm slot $slotNumber ($medicationName) scheduled: '
        '$tzScheduledTime');
  }

  Future<void> cancelMedicationAlarm({required int id}) =>
      _notificationsPlugin.cancel(id);

  /// Baca jadual `medications` dari Supabase dan jadualkan semula SEMUA alarm.
  /// Panggil: selepas log masuk / app dibuka, selepas simpan ubat, selepas tukar masa.
  Future<void> syncFromDatabase() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final rows = await Supabase.instance.client
        .from('medications')
        .select()
        .eq('user_id', user.id);

    bool isRealMed(Map<String, dynamic> m) {
      final n = m['medication_name']?.toString().trim() ?? '';
      return n.isNotEmpty && n != 'Empty' && n != 'Unassigned';
    }

    // Satu baris terbaik bagi setiap slot (utamakan yang ada nama ubat)
    final Map<int, Map<String, dynamic>> bySlot = {};
    for (final raw in rows) {
      final m = Map<String, dynamic>.from(raw as Map);
      final slot = m['slot_number'];
      if (slot is! int) continue;
      final current = bySlot[slot];
      if (current == null || isRealMed(m) || !isRealMed(current)) {
        bySlot[slot] = m;
      }
    }

    await _ensurePermissions();

    for (final entry in bySlot.entries) {
      final slot = entry.key;
      final m = entry.value;
      final id = 1000 + slot;
      final timeStr = m['scheduled_time']?.toString();

      if (!isRealMed(m) || timeStr == null || !timeStr.contains(':')) {
        await cancelMedicationAlarm(id: id);
        continue;
      }

      try {
        final parts = timeStr.split(':');
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        await scheduleMedicationAlarm(
          id: id,
          medicationName: m['medication_name'].toString().trim(),
          slotNumber: slot,
          scheduledTime: DateTime(2000, 1, 1, hour, minute),
          checkPermissions: false,
        );
      } catch (e) {
        debugPrint('Failed to schedule alarm for slot $slot: $e');
      }
    }
  }

  /// UJIAN: bunyikan alarm dalam [seconds] saat dari sekarang.
  /// Berguna untuk menguji kebenaran/bateri telefon.
  Future<void> scheduleTestAlarm({int seconds = 60}) async {
    await _ensurePermissions();
    final when = tz.TZDateTime.now(tz.local).add(Duration(seconds: seconds));
    await _notificationsPlugin.zonedSchedule(
      9999,
      '⏰ ALARM TEST',
      'If you can see this, the alarm is working.',
      when,
      _details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'Alarm Test|Test',
    );
  }

  /// Hantar SMS Notifikasi
  Future<void> sendSMSNotification({
    required String phoneNumber,
    required String message,
  }) async {
    final Uri smsUri = Uri(
      scheme: 'sms',
      path: phoneNumber,
      queryParameters: <String, String>{
        'body': message,
      },
    );

    try {
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
      } else {
        debugPrint("Could not open the SMS app");
      }
    } catch (e) {
      debugPrint("Failed to send SMS: $e");
    }
  }
}