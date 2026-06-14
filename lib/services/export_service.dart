import 'dart:io';

import 'package:flutter_archive/flutter_archive.dart';
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
      'GPS UTC,Measurement Name,Error Code,Methane (ppm),Ethane (ppm),Latitude,Longitude',
    );
    for (final (m, r) in pairs) {
      sb.writeln(
        [
          _esc(r.gpsUtc),
          _esc(m.name),
          r.errorCode.toString(),
          r.methanePpm.toString(),
          r.ethanePpm.toString(),
          r.latitude?.toString() ?? '',
          r.longitude?.toString() ?? '',
        ].join(','),
      );
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

  static Future<String> exportSurveyZip(int surveyId) async {
    final db = await DatabaseService.instance();
    final survey = await db.getSurveyById(surveyId);
    if (survey == null) throw 'Survey not found';

    // CSV — may throw if no readings
    String? csvPath;
    try {
      csvPath = await buildCsv(surveyId);
    } catch (_) {
      csvPath = null;
    }

    final mediaFiles = await db.getMediaFilesForSurvey(surveyId);

    if (csvPath == null && mediaFiles.isEmpty) {
      throw 'No readings or media available to export';
    }

    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final safeName = survey.name
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '');
    final zipFilename = 'survey_${safeName}_$stamp.zip';

    final tempDir = await getTemporaryDirectory();
    final stagingDir = Directory(
      p.join(tempDir.path, 'zip_staging_${surveyId}_$stamp'),
    );
    if (await stagingDir.exists()) await stagingDir.delete(recursive: true);
    await stagingDir.create(recursive: true);

    // Copy CSV
    if (csvPath != null) {
      await File(csvPath).copy(p.join(stagingDir.path, p.basename(csvPath)));
    }

    // Copy media files + write media.csv
    if (mediaFiles.isNotEmpty) {
      final mediaCsvSb = StringBuffer();
      mediaCsvSb.writeln(
        'measurement_id,type,path,timestamp,latitude,longitude',
      );
      for (final mf in mediaFiles) {
        final srcFile = File(mf.path);
        if (await srcFile.exists()) {
          final relDir = p.join('media', 'measurement_${mf.measurementId}');
          final destMediaDir = Directory(p.join(stagingDir.path, relDir));
          if (!await destMediaDir.exists()) {
            await destMediaDir.create(recursive: true);
          }
          await srcFile.copy(p.join(destMediaDir.path, p.basename(mf.path)));
        }
        mediaCsvSb.writeln(
          [
            mf.measurementId.toString(),
            _esc(mf.type),
            _esc(mf.path),
            _esc(mf.timestamp),
            mf.latitude?.toString() ?? '',
            mf.longitude?.toString() ?? '',
          ].join(','),
        );
      }
      await File(
        p.join(stagingDir.path, 'media.csv'),
      ).writeAsString(mediaCsvSb.toString());
    }

    // Create ZIP
    final zipFile = File(p.join(tempDir.path, zipFilename));
    await ZipFile.createFromDirectory(
      sourceDir: stagingDir,
      zipFile: zipFile,
      recurseSubDirs: true,
    );

    // Clean up staging dir
    await stagingDir.delete(recursive: true);

    return zipFile.path;
  }

  static String _esc(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }
}
