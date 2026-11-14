import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

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
        'medication_alarm_channel_v3',
        'Medication Alarm Channel',
        description: 'Daily medication reminders',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await androidImplementation.createNotificationChannel(channel);
      await androidImplementation.requestNotificationsPermission();
    }
  }

  /// Menjadualkan notifikasi ubat setiap hari pada masa yang dipilih.
  Future<void> scheduleMedicationAlarm({
    required int id,
    required String medicationName,
    required int slotNumber,
    required DateTime scheduledTime,
  }) async {
    final androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      var notificationsEnabled =
          await androidImplementation.areNotificationsEnabled() ?? false;
      if (!notificationsEnabled) {
        await androidImplementation.requestNotificationsPermission();
        notificationsEnabled =
            await androidImplementation.areNotificationsEnabled() ?? false;
      }
      if (!notificationsEnabled) {
        throw StateError(
          'Kebenaran notifikasi dimatikan. Hidupkan notifikasi aplikasi '
          'SmartDispense AI di tetapan telefon.',
        );
      }

      var canScheduleExact =
          await androidImplementation.canScheduleExactNotifications() ?? true;
      if (!canScheduleExact) {
        await androidImplementation.requestExactAlarmsPermission();
        canScheduleExact =
            await androidImplementation.canScheduleExactNotifications() ??
                false;
      }
      if (!canScheduleExact) {
        throw StateError(
          'Kebenaran penggera tepat belum diberikan. Benarkan penggera tepat '
          'untuk SmartDispense AI di tetapan telefon.',
        );
      }
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'medication_alarm_channel_v3',
      'Medication Alarm Channel',
      channelDescription: 'Daily medication reminders',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      autoCancel: true,
      playSound: true,
    );

    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);

    final location = tz.local;
    var tzScheduledTime = tz.TZDateTime.from(
      scheduledTime,
      location,
    );

    if (tzScheduledTime.isBefore(tz.TZDateTime.now(location))) {
      tzScheduledTime = tzScheduledTime.add(const Duration(days: 1));
    }

    await _notificationsPlugin.cancel(id);
    await _notificationsPlugin.zonedSchedule(
      id,
      '⏰ MASA MAKAN UBAT!',
      'Sila ambil $medicationName dari Slot $slotNumber',
      tzScheduledTime,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: '$medicationName|Slot $slotNumber',
    );
  }

  Future<void> cancelMedicationAlarm({required int id}) =>
      _notificationsPlugin.cancel(id);

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
