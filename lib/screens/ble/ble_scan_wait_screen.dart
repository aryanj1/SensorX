import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:blu/services/cache_service.dart';
import 'package:blu/screens/home/home_screen.dart';

class BleScanWaitScreen extends StatefulWidget {
  final TTLFileCache cache;
  const BleScanWaitScreen({super.key, required this.cache});

  @override
  State<BleScanWaitScreen> createState() => _BleScanWaitScreenState();
}

class _BleScanWaitScreenState extends State<BleScanWaitScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _requestPermissionsAndWait();
  }

  Future<void> _requestPermissionsAndWait() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
    _timer = Timer(const Duration(seconds: 4), _navigate);
  }

  void _navigate() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => BLEScannerScreen(cache: widget.cache),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black,
              Color(0xFF3B0000),
              Color(0xFF6B0000),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Starting to Scan for\nBluetooth Devices',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              SizedBox(height: 32),
              CircularProgressIndicator(
                color: Colors.red,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
