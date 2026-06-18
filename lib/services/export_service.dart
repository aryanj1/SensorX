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

    // Create media/ subdirectory
    final mediaDir = Directory(p.join(stagingDir.path, 'media'));
    await mediaDir.create(recursive: true);

    // Copy media files into media/ and build destNames map
    // destNames maps source file path -> renamed filename in media/ folder
    final Map<String, String> destNames = {};
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
        destNames[mf.path] = destName;
        await srcFile.copy(p.join(mediaDir.path, destName));
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
        destNames[lm.mediaPath!] = destName;
        await srcFile.copy(p.join(mediaDir.path, destName));
      }
    }

    // Build main survey CSV (after media copy so destNames is populated)
    final mainCsvSb = StringBuffer();
    mainCsvSb.writeln(
      'Surveyor Name,Survey Name,Measurement Name,Ethane (ppm),Methane (ppm),'
      'Latitude,Longitude,Timestamp,leak_marked,notes,media_exists,'
      'leak_marked_notes,leak_marked_media',
    );
    for (final m in measurements) {
      final readings = readingsMap[m.id!] ?? [];
      final notesForM = notesMap[m.id!] ?? [];
      final mediaForM = mediaMap[m.id!] ?? [];
      final leakForM = leakMap[m.id!] ?? [];

      // Per-row event arrays — default all to empty/no.
      final leakMarkedArr = List.filled(readings.length, 'no');
      final notesArr = List.filled(readings.length, '');
      final mediaExistsArr = List.filled(readings.length, 'no');
      final leakNotesArr = List.filled(readings.length, '');
      final leakMediaArr = List.filled(readings.length, '');

      // Map each event to exactly ONE reading row.
      for (final n in notesForM) {
        final nTime = DateTime.tryParse(n.createdAt);
        if (nTime == null || readings.isEmpty) continue;
        final idx = _findTargetReadingIndex(nTime, readings);
        notesArr[idx] = _esc(n.text);
      }
      for (final mf in mediaForM) {
        final mTime = DateTime.tryParse(mf.timestamp);
        if (mTime == null || readings.isEmpty) continue;
        final idx = _findTargetReadingIndex(mTime, readings);
        mediaExistsArr[idx] = 'yes';
      }
      for (final lm in leakForM) {
        final lmTime = DateTime.tryParse(lm.timestamp);
        if (lmTime == null || readings.isEmpty) continue;
        final idx = _findTargetReadingIndex(lmTime, readings);
        leakMarkedArr[idx] = 'yes';
        if (lm.note != null && lm.note!.isNotEmpty) {
          leakNotesArr[idx] = _esc(lm.note!);
        }
        if (lm.mediaPath != null) {
          leakMediaArr[idx] = _esc(
            destNames[lm.mediaPath!] ?? p.basename(lm.mediaPath!),
          );
        }
      }

      for (var i = 0; i < readings.length; i++) {
        final r = readings[i];
        mainCsvSb.writeln(
          [
            _esc(survey.surveyorName),
            _esc(survey.name),
            _esc(m.name),
            r.ethanePpm.toString(),
            r.methanePpm.toString(),
            r.latitude?.toString() ?? '',
            r.longitude?.toString() ?? '',
            _esc(r.gpsUtc),
            leakMarkedArr[i],
            notesArr[i],
            mediaExistsArr[i],
            leakNotesArr[i],
            leakMediaArr[i],
          ].join(','),
        );
      }
    }
    final mainCsvFilename = 'survey_${safeNameLower}_$stamp.csv';
    await File(
      p.join(stagingDir.path, mainCsvFilename),
    ).writeAsString(mainCsvSb.toString());

    // Create ZIP and clean up
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

  /// Returns the index of the single reading row that an event at [eventTime]
  /// should be applied to.
  ///
  /// Rule: prefer the first reading whose timestamp is >= eventTime (first
  /// reading that started after the event). If no such reading exists, fall
  /// back to the closest earlier reading.
  ///
  /// Readings must be sorted ascending by timestamp (guaranteed by the DB
  /// ORDER BY clause in getReadingsForMeasurement).
  static int _findTargetReadingIndex(
    DateTime eventTime,
    List<Reading> readings,
  ) {
    // First reading at or after event time.
    for (var i = 0; i < readings.length; i++) {
      final rTime = DateTime.tryParse(readings[i].gpsUtc);
      if (rTime == null) continue;
      if (!rTime.isBefore(eventTime)) return i;
    }
    // No later reading — find closest earlier reading.
    var bestIdx = 0;
    var bestDiffMs = 999999999;
    for (var i = 0; i < readings.length; i++) {
      final rTime = DateTime.tryParse(readings[i].gpsUtc);
      if (rTime == null) continue;
      final diff = eventTime.difference(rTime).inMilliseconds.abs();
      if (diff < bestDiffMs) {
        bestDiffMs = diff;
        bestIdx = i;
      }
    }
    return bestIdx;
  }
}
