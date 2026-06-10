// Smoke test for the blu app.
//
// Uses sqflite_common_ffi so DatabaseService can open an in-memory DB on the
// host machine (no Android/iOS runtime needed).  SharedPreferences is mocked
// via its built-in test helper.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:blu/app.dart';

void main() {
  setUpAll(() {
    // Initialise the FFI implementation so sqflite works on the host machine.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    // Reset SharedPreferences to a clean state before each test.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const App());
    // The home screen should load; progress indicator is shown while DB loads.
    expect(find.byType(App), findsOneWidget);
  });
}
