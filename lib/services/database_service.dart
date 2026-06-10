import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'package:blu/models/measurement.dart';
import 'package:blu/models/reading.dart';
import 'package:blu/models/survey.dart';

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
      version: 1,
      onCreate: _onCreate,
      onOpen: _onOpen,
    );
  }

  Future<void> _onOpen(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE surveys (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        name          TEXT NOT NULL,
        surveyor_name TEXT NOT NULL,
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
  }

  Database get _database => _db!;

  // ---------------------------------------------------------------------------
  // Survey CRUD
  // ---------------------------------------------------------------------------

  Future<int> insertSurvey(Survey survey) async {
    return _database.insert('surveys', survey.toMap());
  }

  Future<List<Survey>> getAllSurveys() async {
    final rows = await _database.query(
      'surveys',
      orderBy: 'created_at DESC',
    );
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
    return _database.delete(
      'surveys',
      where: 'id = ?',
      whereArgs: [id],
    );
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
    return _database.delete(
      'measurements',
      where: 'id = ?',
      whereArgs: [id],
    );
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
}
