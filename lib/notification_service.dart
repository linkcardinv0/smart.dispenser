import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
      
  final AudioPlayer _audioPlayer = AudioPlayer();

  Future<void> init(GlobalKey<NavigatorState> navigatorKey) async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _stopAlarmSound();
        if (response.payload != null) {
          navigatorKey.currentState?.pushNamed(
            '/alarm',
            arguments: response.payload,
          );
        }
      },
    );

    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'medication_alarm_channel_v3',
        'Medication Alarm Channel',
        description: 'High priority full-screen alarms for pill dispensing',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      await androidImplementation.createNotificationChannel(channel);
      await androidImplementation.requestNotificationsPermission();
      await androidImplementation.requestExactAlarmsPermission();
    }
  }

  /// Menjadualkan Penggera Tepat Pada Masa Hadapan (Pengendalian Selamat Zon Masa)
  Future<void> scheduleMedicationAlarm({
    required int id,
    required String medicationName,
    required int slotNumber,
    required DateTime scheduledTime,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'medication_alarm_channel_v3',
      'Medication Alarm Channel',
      channelDescription: 'High priority full-screen alarms for pill dispensing',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      ongoing: true,
      autoCancel: false,
      playSound: true,
    );

    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);

    // Ambil lokasi zon masa semasa (secara selamat)
    final location = tz.local;

    var tzScheduledTime = tz.TZDateTime.from(
      scheduledTime,
      location,
    );

    // Jika masa yang dijadualkan sudah berlalu untuk hari ini, anjakkan ke hari esok secara automatik
    if (tzScheduledTime.isBefore(tz.TZDateTime.now(location))) {
      tzScheduledTime = tzScheduledTime.add(const Duration(days: 1));
    }

    await _notificationsPlugin.zonedSchedule(
      id,
      '⏰ MASA MAKAN UBAT!',
      'Sila ambil $medicationName dari Slot $slotNumber',
      tzScheduledTime,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: '$medicationName|Slot $slotNumber',
    );
  }

  /// Ujian Penggera Serta-merta (Untuk Butang TEST)
  Future<void> triggerInstantAlarmTest({
    required BuildContext context,
    required String medicationName,
    required int slotNumber,
  }) async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(
        UrlSource('https://actions.google.com/sounds/v1/alarms/alarm_clock.ogg'),
      );
    } catch (e) {
      debugPrint("Gagal memainkan bunyi: $e");
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'medication_alarm_channel_v3',
      'Medication Alarm Channel',
      channelDescription: 'High priority full-screen alarms for pill dispensing',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      ongoing: true,
      autoCancel: false,
      playSound: true,
    );

    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      888,
      '⏰ MASA MAKAN UBAT!',
      'Sila ambil $medicationName dari Slot $slotNumber',
      notificationDetails,
      payload: '$medicationName|Slot $slotNumber',
    );

    if (context.mounted) {
      Navigator.pushNamed(
        context,
        '/alarm',
        arguments: '$medicationName|Slot $slotNumber',
      );
    }
  }

  void stopAlarm() {
    _stopAlarmSound();
    _notificationsPlugin.cancel(888);
    _notificationsPlugin.cancelAll();
  }

  void _stopAlarmSound() {
    try {
      _audioPlayer.stop();
    } catch (e) {
      debugPrint("Gagal menghentikan bunyi: $e");
    }
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
        debugPrint("Gagal membuka aplikasi SMS");
      }
    } catch (e) {
      debugPrint("Gagal menghantar SMS: $e");
    }
  }
}