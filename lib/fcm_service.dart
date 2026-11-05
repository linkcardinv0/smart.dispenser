import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Top-level function untuk mengendalikan push notification semasa app ditutup (Background)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("FCM Background Message: ${message.notification?.title}");
}

class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Inisialisasi FCM & Notifikasi Tempatan
  Future<void> init() async {
    // 1. Daftarkan handler latar belakang
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 2. Minta kebenaran push notification
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('Kebenaran FCM diberikan.');

      // 3. Sediakan saluran notifikasi tempatan untuk paparan semasa app aktif
      await _setupLocalNotifications();

      // 4. Dengarkan mesej yang masuk semasa app aktif (Foreground)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _showForegroundNotification(message);
      });

      // 5. Simpan token ke Supabase
      await syncTokenToSupabase();

      // 6. Dengarkan pembaharuan token secara automatik
      _messaging.onTokenRefresh.listen((newToken) async {
        await _saveTokenToSupabase(newToken);
      });
    }
  }

  /// Sediakan saluran notifikasi Android
  Future<void> _setupLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);

    await _localNotifications.initialize(initSettings);

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'fcm_medication_channel',
      'Peringatan Makan Ubat',
      description: 'Saluran push notification untuk peringatan ubat',
      importance: Importance.max,
      playSound: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Paparkan notifikasi di skrin apabila app sedang dibuka
  void _showForegroundNotification(RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'fcm_medication_channel',
            'Peringatan Makan Ubat',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
          ),
        ),
      );
    }
  }

  /// Simpan atau kemaskini FCM token semasa ke Supabase
  Future<void> syncTokenToSupabase() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    String? token = await _messaging.getToken();
    if (token != null) {
      await _saveTokenToSupabase(token);
    }
  }

  /// Pelaksanaan simpan token ke jadual `fcm_tokens`
  Future<void> _saveTokenToSupabase(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      await Supabase.instance.client.from('fcm_tokens').upsert(
        {
          'user_id': user.id,
          'token': token,
          'device_name': defaultTargetPlatform.name,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'token',
      );
      debugPrint("FCM Token berjaya dikemaskini dalam Supabase");
    } catch (e) {
      debugPrint("Gagal menyimpan FCM Token ke Supabase: $e");
    }
  }
}