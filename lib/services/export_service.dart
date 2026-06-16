import 'dart:io';

import 'package:flutter_archive/flutter_archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database_service.dart';
import '../models/leak_mark.dart';
import '../models/measurement.dart';
import '../models/media_file.dart';
import '../models/note.dart';
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

    final measurements = await db.getMeasurementsForSurvey(surveyId);

    // Build maps keyed by measurement.id
    final Map<int, List<Reading>> readingsMap = {};
    final Map<int, List<Note>> notesMap = {};
    final Map<int, List<MediaFile>> mediaMap = {};
    final Map<int, List<LeakMark>> leakMap = {};
    for (final m in measurements) {
      readingsMap[m.id!] = await db.getReadingsForMeasurement(m.id!);
      notesMap[m.id!] = await db.getNotesForMeasurement(m.id!);
      mediaMap[m.id!] = await db.getMediaFilesForMeasurement(m.id!);
      leakMap[m.id!] = await db.getLeakMarksForMeasurement(m.id!);
    }

    // Guard: no data at all
    final hasAnyReadings =
        measurements.isNotEmpty && readingsMap.values.any((r) => r.isNotEmpty);
    if (!hasAnyReadings &&
        notesMap.values.every((n) => n.isEmpty) &&
        mediaMap.values.every((mf) => mf.isEmpty) &&
        leakMap.values.every((lk) => lk.isEmpty)) {
      throw 'No data available to export';
    }

    // Measurement name lookup
    final Map<int, String> measNameById = {
      for (final m in measurements) m.id!: m.name,
    };

    final now = DateTime.now();
    final stamp = '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final safeSurveyName = survey.name.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    final safeNameLower = survey.name
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^a-z0-9_]'), '');
    final zipFilename = 'survey_${safeNameLower}_$stamp.zip';

    final tempDir = await getTemporaryDirectory();
    final stagingDir = Directory(
      p.join(tempDir.path, 'zip_staging_${surveyId}_$stamp'),
    );
    if (await stagingDir.exists()) await stagingDir.delete(recursive: true);
    await stagingDir.create(recursive: true);

    // 4c. Build main survey CSV
    final mainCsvSb = StringBuffer();
    mainCsvSb.writeln(
      'GPS UTC,Measurement Name,Error Code,Methane (ppm),Ethane (ppm),'
      'Latitude,Longitude,notes,media_exists,leak_marked',
    );
    for (final m in measurements) {
      final readings = readingsMap[m.id!] ?? [];
      final notesForM = notesMap[m.id!] ?? [];
      final mediaForM = mediaMap[m.id!] ?? [];
      final leakForM = leakMap[m.id!] ?? [];
      final notesJoined = notesForM.map((n) => n.text).join(' | ');
      final mediaExists = mediaForM.isNotEmpty ? 'yes' : 'no';
      for (final r in readings) {
        mainCsvSb.writeln(
          [
            _esc(r.gpsUtc),
            _esc(m.name),
            r.errorCode.toString(),
            r.methanePpm.toString(),
            r.ethanePpm.toString(),
            r.latitude?.toString() ?? '',
            r.longitude?.toString() ?? '',
            _esc(notesJoined),
            mediaExists,
            _leakMarkedForRow(r, leakForM),
          ].join(','),
        );
      }
    }
    final mainCsvFilename = 'survey_${safeNameLower}_$stamp.csv';
    await File(
      p.join(stagingDir.path, mainCsvFilename),
    ).writeAsString(mainCsvSb.toString());

    // 4d. notes.csv
    final allNotes = notesMap.values.expand((n) => n).toList();
    if (allNotes.isNotEmpty) {
      final notesCsvSb = StringBuffer();
      notesCsvSb.writeln(
        'Survey Name,Measurement Name,Timestamp,Latitude,Longitude,Note',
      );
      for (final m in measurements) {
        final notesForM = notesMap[m.id!] ?? [];
        for (final n in notesForM) {
          notesCsvSb.writeln(
            [
              _esc(survey.name),
              _esc(m.name),
              _esc(n.createdAt),
              '',
              '',
              _esc(n.text),
            ].join(','),
          );
        }
      }
      await File(
        p.join(stagingDir.path, 'notes.csv'),
      ).writeAsString(notesCsvSb.toString());
    }

    // 4e. media.csv
    final allMedia = mediaMap.values.expand((mf) => mf).toList();
    if (allMedia.isNotEmpty) {
      final mediaCsvSb = StringBuffer();
      mediaCsvSb.writeln(
        'Survey Name,Measurement Name,Timestamp,Latitude,Longitude',
      );
      for (final m in measurements) {
        final mediaForM = mediaMap[m.id!] ?? [];
        for (final mf in mediaForM) {
          mediaCsvSb.writeln(
            [
              _esc(survey.name),
              _esc(m.name),
              _esc(mf.timestamp),
              mf.latitude?.toString() ?? '',
              mf.longitude?.toString() ?? '',
            ].join(','),
          );
        }
      }
      await File(
        p.join(stagingDir.path, 'media.csv'),
      ).writeAsString(mediaCsvSb.toString());
    }

    // 4f. leak_marked.csv
    final allLeaks = leakMap.values.expand((lk) => lk).toList();
    if (allLeaks.isNotEmpty) {
      final leakCsvSb = StringBuffer();
      leakCsvSb.writeln(
        'Survey Name,Measurement Name,Timestamp,Latitude,Longitude,Note',
      );
      for (final m in measurements) {
        final leakForM = leakMap[m.id!] ?? [];
        for (final lm in leakForM) {
          leakCsvSb.writeln(
            [
              _esc(survey.name),
              _esc(m.name),
              _esc(lm.timestamp),
              lm.latitude?.toString() ?? '',
              lm.longitude?.toString() ?? '',
              _esc(lm.note ?? ''),
            ].join(','),
          );
        }
      }
      await File(
        p.join(stagingDir.path, 'leak_marked.csv'),
      ).writeAsString(leakCsvSb.toString());
    }

    // 4g. Copy media files
    for (final m in measurements) {
      final mediaForM = mediaMap[m.id!] ?? [];
      final safeMeasName = m.name.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
      var mediaIndex = 0;
      for (final mf in mediaForM) {
        final srcFile = File(mf.path);
        if (!srcFile.existsSync()) continue;
        mediaIndex++;
        final type = mf.type;
        final ext = p.extension(mf.path).replaceFirst('.', '').toLowerCase();
        final tsRaw = mf.timestamp
            .replaceAll(RegExp(r'[:\-T]'), '')
            .replaceAll('.', '')
            .substring(0, 15);
        final index = mediaIndex.toString().padLeft(3, '0');
        final destName =
            '${safeSurveyName}_${safeMeasName}_${tsRaw}_${type}_$index.$ext';
        await srcFile.copy(p.join(stagingDir.path, destName));
      }

      final leakForM = leakMap[m.id!] ?? [];
      var leakMediaIndex = 0;
      for (final lm in leakForM) {
        if (lm.mediaPath == null) continue;
        final srcFile = File(lm.mediaPath!);
        if (!srcFile.existsSync()) continue;
        leakMediaIndex++;
        final ext =
            p.extension(lm.mediaPath!).replaceFirst('.', '').toLowerCase();
        final tsRaw = lm.timestamp
            .replaceAll(RegExp(r'[:\-T]'), '')
            .replaceAll('.', '')
            .substring(0, 15);
        final safeMeasNameLocal = (measNameById[lm.measurementId] ?? 'unknown')
            .replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
        final index = leakMediaIndex.toString().padLeft(3, '0');
        final destName =
            '${safeSurveyName}_${safeMeasNameLocal}_${tsRaw}_leak_photo_$index.$ext';
        await srcFile.copy(p.join(stagingDir.path, destName));
      }
    }

    // 4h. Create ZIP and clean up
    final zipFile = File(p.join(tempDir.path, zipFilename));
    await ZipFile.createFromDirectory(
      sourceDir: stagingDir,
      zipFile: zipFile,
      recurseSubDirs: true,
    );
    await stagingDir.delete(recursive: true);

    return zipFile.path;
  }

  static String _esc(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  /// Returns 'yes' if any leak mark occurred within [_leakToleranceSeconds]
  /// of the reading's GPS UTC timestamp, otherwise 'no'.
  static const _leakToleranceSeconds = 60;

  static String _leakMarkedForRow(Reading r, List<LeakMark> leaks) {
    if (leaks.isEmpty) return 'no';
    final rTime = DateTime.tryParse(r.gpsUtc);
    if (rTime == null) return 'no';
    for (final lm in leaks) {
      final lmTime = DateTime.tryParse(lm.timestamp);
      if (lmTime == null) continue;
      if (rTime.difference(lmTime).abs().inSeconds <= _leakToleranceSeconds) {
        return 'yes';
      }
    }
    return 'no';
  }
}
