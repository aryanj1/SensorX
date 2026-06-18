import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:blu/services/threshold_notification_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThresholdNotificationService.init();
  await Permission.notification.request();
  runApp(const App());
}
