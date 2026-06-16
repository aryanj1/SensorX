import 'package:flutter/material.dart';

import 'package:blu/screens/splash/splash_screen.dart';

/// Top-level RouteObserver. Import this in any screen that needs RouteAware.
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

class App extends StatelessWidget {
  const App({super.key});

  static final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
    ThemeMode.light,
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: App.themeModeNotifier,
      builder: (_, mode, __) => MaterialApp(
        title: 'X-Survey',
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
        navigatorObservers: [routeObserver],
        home: const SplashScreen(),
      ),
    );
  }
}
