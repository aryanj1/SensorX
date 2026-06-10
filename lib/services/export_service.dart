import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database_service.dart';
import '../models/measurement.dart';
import '../models/reading.dart';

class ExportService {
  ExportService._();

  static Future<String> buildCsv(int surveyId) async {
    final db = await DatabaseService.instance();

    final survey = await db.getSurveyById(surveyId);
    if (survey == null) throw 'Survey not found';

    final measurements = await db.getMeasurementsForSurvey(surveyId);

    // Collect all (measurement, reading) pairs
    final List<(Measurement, Reading)> pairs = [];
    for (final m in measurements) {
      if (m.id == null) continue;
      final readings = await db.getReadingsForMeasurement(m.id!);
      for (final r in readings) {
        pairs.add((m, r));
      }
    }

    if (pairs.isEmpty) throw 'No SQLite readings available to export';

    // Build CSV
    final sb = StringBuffer();
    sb.writeln(
        'GPS UTC,Measurement Name,Error Code,Methane (ppm),Ethane (ppm),Latitude,Longitude');
    for (final (m, r) in pairs) {
      sb.writeln([
        _esc(r.gpsUtc),
        _esc(m.name),
        r.errorCode.toString(),
        r.methanePpm.toString(),
        r.ethanePpm.toString(),
        r.latitude?.toString() ?? '',
        r.longitude?.toString() ?? '',
      ].join(','));
    }

    // Build filename
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final safeName = survey.name
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '');
    final filename = 'survey_${safeName}_$stamp.csv';

    final dir = await getTemporaryDirectory();
    final filePath = p.join(dir.path, filename);
    await File(filePath).writeAsString(sb.toString());
    return filePath;
  }

  static String _esc(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }
}
