import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:blu/constants/sensor_facts.dart';
import 'package:blu/screens/home/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _progress;
  late String _randomFact;

  @override
  void initState() {
    super.initState();
    _randomFact = kSensorFacts[math.Random().nextInt(kSensorFacts.length)];
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    _progress = _ctrl.drive(Tween<double>(begin: 0, end: 1));
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Fullscreen background PNG ─────────────────────────
          Image.asset(
            'assets/images/splash_logo.png',
            fit: BoxFit.cover,
          ),
          // ── Loading bar + fact: below logo, inside radial circle
          Align(
            alignment: const Alignment(0, 0.45),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _progress,
                    builder: (_, __) => SizedBox(
                      height: 3,
                      child: LinearProgressIndicator(
                        value: _progress.value,
                        backgroundColor: Colors.white24,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _randomFact,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 13,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
