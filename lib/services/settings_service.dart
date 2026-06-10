import 'package:shared_preferences/shared_preferences.dart';

/// Persists user-level settings via SharedPreferences.
/// Uses static methods — no singleton required.
class SettingsService {
  SettingsService._();

  static const _keySurveyorName = 'surveyor_name';

  /// Returns the persisted surveyor name, defaulting to "Not Defined".
  static Future<String> getSurveyorName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySurveyorName) ?? 'Not Defined';
  }

  /// Persists [name] as the surveyor name.
  static Future<void> setSurveyorName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySurveyorName, name);
  }
}
