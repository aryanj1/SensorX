import 'package:flutter/material.dart';

import 'package:blu/screens/home/home_screen.dart';

class App extends StatelessWidget {
  const App({super.key});

  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier(ThemeMode.light);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: App.themeModeNotifier,
      builder: (_, mode, __) => MaterialApp(
        title: 'blu',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: mode,
        home: const HomeScreen(),
      ),
    );
  }
}
