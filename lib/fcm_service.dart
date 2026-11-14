import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Firebase Console -> Project settings -> Cloud Messaging ->
/// Web Push certificates -> "Key pair" (VAPID key). Diperlukan untuk web / iPhone.
const String kWebVapidKey = 'PASTE_YOUR_WEB_PUSH_CERTIFICATE_KEY';

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

  // Lazy: elak ralat jika Firebase belum diinisialisasi
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Dipanggil (web) apabila mesej tiba semasa app sedang dibuka.
  void Function(String title, String body)? onWebForeground;
  bool _webListening = false;
  bool _tokenRefreshListening = false;

  /// Inisialisasi FCM & Notifikasi Tempatan (Android / iOS app sahaja)
  Future<void> init() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('Kebenaran FCM diberikan.');

      await _setupLocalNotifications();

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _showForegroundNotification(message);
      });

      await syncTokenToSupabase();
      _listenTokenRefresh();
    }
  }

  /// WEB: dengar mesej semasa app dibuka (panggil sekali di main()).
  void listenWebForeground() {
    if (!kIsWeb || _webListening) return;
    _webListening = true;
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final n = message.notification;
      if (n != null) {
        onWebForeground?.call(n.title ?? '', n.body ?? '');
      }
    });
  }

  /// WEB / iPhone: MESTI dipanggil dari tekanan butang (syarat iOS Safari).
  Future<bool> enablePush() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        return false;
      }
      final token = await _messaging.getToken(
        vapidKey: kIsWeb ? kWebVapidKey : null,
      );
      if (token == null) return false;
      await _saveTokenToSupabase(token);
      _listenTokenRefresh();
      return true;
    } catch (e) {
      debugPrint('enablePush gagal: $e');
      return false;
    }
  }

  void _listenTokenRefresh() {
    if (_tokenRefreshListening) return;
    _tokenRefreshListening = true;
    _messaging.onTokenRefresh.listen((newToken) async {
      await _saveTokenToSupabase(newToken);
    });
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

  /// Simpan atau kemaskini FCM token semasa ke Supabase.
  /// Selamat dipanggil selepas log masuk (tidak melempar ralat).
  Future<void> syncTokenToSupabase() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      if (kIsWeb) {
        // Web: jangan minta kebenaran di sini. Hanya segerak jika sudah dibenarkan.
        final s = await _messaging.getNotificationSettings();
        if (s.authorizationStatus != AuthorizationStatus.authorized) return;
      }

      final token = await _messaging.getToken(
        vapidKey: kIsWeb ? kWebVapidKey : null,
      );
      if (token != null) {
        await _saveTokenToSupabase(token);
      }
    } catch (e) {
      debugPrint('syncTokenToSupabase gagal: $e');
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
          'device_name': kIsWeb ? 'web' : defaultTargetPlatform.name,
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