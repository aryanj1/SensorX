import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class ThresholdNotificationService {
  static const _channelId = 'blu_threshold_alert';
  static const _notificationId = 1001;

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
    );
    await _plugin.initialize(settings);
    const channel = AndroidNotificationChannel(
      _channelId,
      'Threshold Alerts',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  static Future<void> showAlert(double ppm) async {
    await _plugin.cancel(_notificationId);
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Threshold Alerts',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _plugin.show(
      _notificationId,
      'X-ACT Alert \u{1F6A8}',
      'Threshold ${ppm.toStringAsFixed(0)}(ppm) crossed. Review ASAP!',
      details,
    );
  }
}
