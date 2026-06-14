import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:blu/models/measurement.dart';
import 'package:blu/models/media_file.dart';
import 'package:blu/models/reading.dart';
import 'package:blu/models/survey.dart';
import 'package:blu/models/surveyor.dart';

class DatabaseService {
  DatabaseService._();

  static DatabaseService? _instance;
  static Database? _db;

  static Future<DatabaseService> instance() async {
    if (_instance != null) return _instance!;
    _instance = DatabaseService._();
    _db = await _instance!._openDatabase();
    return _instance!;
  }

  Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'blu_surveys.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
    );
  }

  Future<void> _onOpen(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE surveyors (
        id   INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    ''');

    await db.execute('''
      CREATE TABLE surveys (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        name          TEXT NOT NULL,
        surveyor_name TEXT NOT NULL,
        surveyor_id   INTEGER REFERENCES surveyors(id) ON DELETE CASCADE,
        created_at    TEXT NOT NULL,
        device_id     TEXT,
        device_name   TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE measurements (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        survey_id  INTEGER NOT NULL REFERENCES surveys(id) ON DELETE CASCADE,
        name       TEXT NOT NULL,
        status     TEXT NOT NULL DEFAULT 'idle',
        started_at TEXT,
        stopped_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE readings (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        measurement_id  INTEGER NOT NULL REFERENCES measurements(id) ON DELETE CASCADE,
        gps_utc         TEXT NOT NULL,
        error_code      INTEGER NOT NULL,
        methane_ppm     REAL NOT NULL,
        ethane_ppm      REAL NOT NULL,
        latitude        REAL,
        longitude       REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE media_files (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        measurement_id  INTEGER NOT NULL REFERENCES measurements(id) ON DELETE CASCADE,
        path            TEXT NOT NULL,
        type            TEXT NOT NULL,
        timestamp       TEXT NOT NULL,
        latitude        REAL,
        longitude       REAL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Step 1: create surveyors table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS surveyors (
          id   INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE
        )
      ''');

      // Step 2: add surveyor_id column to surveys
      await db.execute(
        'ALTER TABLE surveys ADD COLUMN surveyor_id INTEGER REFERENCES surveyors(id)',
      );

      // Step 3: treat NULL/empty surveyor_name as 'Not Defined'
      await db.execute(
        "UPDATE surveys SET surveyor_name = 'Not Defined' "
        "WHERE surveyor_name IS NULL OR surveyor_name = ''",
      );

      // Step 4: insert one surveyor row per distinct surveyor_name
      await db.execute(
        'INSERT OR IGNORE INTO surveyors (name) '
        'SELECT DISTINCT surveyor_name FROM surveys',
      );

      // Step 5: back-fill surveyor_id
      await db.execute(
        'UPDATE surveys '
        'SET surveyor_id = (SELECT id FROM surveyors WHERE surveyors.name = surveys.surveyor_name) '
        'WHERE surveyor_id IS NULL',
      );
    }

    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS media_files (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          measurement_id  INTEGER NOT NULL REFERENCES measurements(id) ON DELETE CASCADE,
          path            TEXT NOT NULL,
          type            TEXT NOT NULL,
          timestamp       TEXT NOT NULL,
          latitude        REAL,
          longitude       REAL
        )
      ''');
    }
  }

  Database get _database => _db!;

  // ---------------------------------------------------------------------------
  // Surveyor CRUD
  // ---------------------------------------------------------------------------

  Future<int> insertSurveyor(Surveyor surveyor) async {
    return _database.insert('surveyors', {'name': surveyor.name});
  }

  Future<List<Surveyor>> getAllSurveyors() async {
    final rows = await _database.query('surveyors', orderBy: 'name ASC');
    return rows.map(Surveyor.fromMap).toList();
  }

  Future<List<Survey>> getSurveysForSurveyor(int surveyorId) async {
    final rows = await _database.query(
      'surveys',
      where: 'surveyor_id = ?',
      whereArgs: [surveyorId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Survey.fromMap).toList();
  }

  Future<void> deleteSurveyor(int id) async {
    // Manually cascade because ALTER TABLE ADD COLUMN cannot carry ON DELETE CASCADE.
    final db = _database;
    await db.transaction((txn) async {
      // Find all survey ids belonging to this surveyor so we can cascade to measurements/readings.
      final surveyRows = await txn.query(
        'surveys',
        columns: ['id'],
        where: 'surveyor_id = ?',
        whereArgs: [id],
      );
      for (final row in surveyRows) {
        final surveyId = row['id'] as int;
        final measurementRows = await txn.query(
          'measurements',
          columns: ['id'],
          where: 'survey_id = ?',
          whereArgs: [surveyId],
        );
        for (final mRow in measurementRows) {
          await txn.delete(
            'readings',
            where: 'measurement_id = ?',
            whereArgs: [mRow['id']],
          );
        }
        await txn.delete(
          'measurements',
          where: 'survey_id = ?',
          whereArgs: [surveyId],
        );
      }
      await txn.delete('surveys', where: 'surveyor_id = ?', whereArgs: [id]);
      await txn.delete('surveyors', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ---------------------------------------------------------------------------
  // Survey CRUD
  // ---------------------------------------------------------------------------

  Future<int> insertSurvey(Survey survey) async {
    return _database.insert('surveys', survey.toMap());
  }

  Future<List<Survey>> getAllSurveys() async {
    final rows = await _database.query('surveys', orderBy: 'created_at DESC');
    return rows.map(Survey.fromMap).toList();
  }

  Future<Survey?> getSurveyById(int id) async {
    final rows = await _database.query(
      'surveys',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Survey.fromMap(rows.first);
  }

  Future<int> updateSurvey(Survey survey) async {
    assert(survey.id != null, 'Cannot update a Survey without an id');
    return _database.update(
      'surveys',
      survey.toMap(),
      where: 'id = ?',
      whereArgs: [survey.id],
    );
  }

  Future<int> deleteSurvey(int id) async {
    return _database.delete('surveys', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // Measurement CRUD
  // ---------------------------------------------------------------------------

  Future<int> insertMeasurement(Measurement measurement) async {
    return _database.insert('measurements', measurement.toMap());
  }

  Future<List<Measurement>> getMeasurementsForSurvey(int surveyId) async {
    final rows = await _database.query(
      'measurements',
      where: 'survey_id = ?',
      whereArgs: [surveyId],
      orderBy: 'id ASC',
    );
    return rows.map(Measurement.fromMap).toList();
  }

  Future<Measurement?> getMeasurementById(int id) async {
    final rows = await _database.query(
      'measurements',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Measurement.fromMap(rows.first);
  }

  Future<int> updateMeasurement(Measurement measurement) async {
    assert(measurement.id != null, 'Cannot update a Measurement without an id');
    return _database.update(
      'measurements',
      measurement.toMap(),
      where: 'id = ?',
      whereArgs: [measurement.id],
    );
  }

  Future<int> deleteMeasurement(int id) async {
    return _database.delete('measurements', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // Reading CRUD
  // ---------------------------------------------------------------------------

  Future<int> insertReading(Reading reading) async {
    return _database.insert('readings', reading.toMap());
  }

  Future<List<Reading>> getReadingsForMeasurement(int measurementId) async {
    final rows = await _database.query(
      'readings',
      where: 'measurement_id = ?',
      whereArgs: [measurementId],
      orderBy: 'id ASC',
    );
    return rows.map(Reading.fromMap).toList();
  }

  Future<int> deleteReadingsForMeasurement(int measurementId) async {
    return _database.delete(
      'readings',
      where: 'measurement_id = ?',
      whereArgs: [measurementId],
    );
  }

  Future<int> getReadingCountForMeasurement(int measurementId) async {
    final result = await _database.rawQuery(
      'SELECT COUNT(*) AS cnt FROM readings WHERE measurement_id = ?',
      [measurementId],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // MediaFile CRUD
  // ---------------------------------------------------------------------------

  Future<int> insertMediaFile(MediaFile file) async {
    return _database.insert('media_files', file.toMap());
  }

  Future<List<MediaFile>> getMediaFilesForMeasurement(int measurementId) async {
    final rows = await _database.query(
      'media_files',
      where: 'measurement_id = ?',
      whereArgs: [measurementId],
      orderBy: 'id ASC',
    );
    return rows.map(MediaFile.fromMap).toList();
  }

  Future<List<MediaFile>> getMediaFilesForSurvey(int surveyId) async {
    final rows = await _database.rawQuery(
      '''
      SELECT mf.* FROM media_files mf
      INNER JOIN measurements m ON mf.measurement_id = m.id
      WHERE m.survey_id = ?
      ORDER BY mf.id ASC
    ''',
      [surveyId],
    );
    return rows.map(MediaFile.fromMap).toList();
  }
}
