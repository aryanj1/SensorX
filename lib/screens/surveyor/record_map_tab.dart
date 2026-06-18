import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:blu/services/threshold_notification_service.dart';

import 'package:blu/models/leak_mark.dart';
import 'package:blu/models/measurement.dart';
import 'package:blu/models/media_file.dart';
import 'package:blu/models/note.dart';
import 'package:blu/models/reading.dart';
import 'package:blu/models/survey.dart';
import 'package:blu/models/surveyor.dart';
import 'package:blu/screens/ble/ble_scan_wait_screen.dart';
import 'package:blu/services/ble_state.dart';
import 'package:blu/services/cache_service.dart';
import 'package:blu/services/database_service.dart';
import 'package:blu/services/storage_check_service.dart';
import 'package:blu/widgets/start_measurement_sheet.dart';

class RecordMapTab extends StatefulWidget {
  final Surveyor surveyor;
  final TTLFileCache? cache;

  const RecordMapTab({super.key, required this.surveyor, this.cache});

  @override
  State<RecordMapTab> createState() => RecordMapTabState();
}

class RecordMapTabState extends State<RecordMapTab>
    with WidgetsBindingObserver {
  static final _serviceUUID = Guid('4fafc201-1fb5-459e-8fcc-c5c9c331914b');
  static final _charUUID = Guid('beb5483e-36e1-4688-b7f5-ea07361b26a8');

  // GPS path filter constants
  static const double _kMaxAccuracyMetres = 30.0;
  static const double _kMaxSpeedMs = 15.0; // 54 km/h — rejects GPS jumps
  static const double _kMinDistanceMetres = 2.0; // suppresses stationary jitter

  // GPS path filter bookkeeping
  LatLng? _lastAcceptedPoint;
  DateTime? _lastAcceptedTime;

  // BLE
  StreamSubscription<BluetoothConnectionState>? _connSub;
  bool _bleConnected = false;
  String _latestMethane = '--';
  String _latestEthane = '--';

  // GPS / Map
  StreamSubscription<Position>? _positionStream;
  double? _lat;
  double? _lng;
  final MapController _mapController = MapController();
  List<LatLng> _routePoints = [];
  List<LatLng> _leakMarkerPoints = [];

  // Recording
  String _recordStatus = 'idle'; // idle | active | paused | stopped
  Measurement? _activeMeasurement;
  Survey? _activeSurvey;

  // Elapsed time
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;

  // Audio
  final AudioPlayer _player = AudioPlayer();
  bool _alarmEnabled = true;
  double _threshold = 50.0;
  DateTime? _lastAlarmTime;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  bool _alertDialogVisible = false;

  // Legacy CSV cache
  String? _sessionFile;
  static const _ttl = Duration(days: 14);
  static const _maxCacheBytes = 200 * 1024 * 1024;

  // Map interaction
  bool _userHasMovedMap = false;

  // Overlays
  bool _showAlarmOverlay = false;
  bool _showNotesOverlay = false;
  bool _showLeakOverlay = false;
  List<Note> _notes = [];
  final TextEditingController _noteCtrl = TextEditingController();

  // Leak overlay state
  final TextEditingController _leakNoteCtrl = TextEditingController();
  String? _leakPickedMediaPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initLocation();
    _connectBle();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
  }

  // ── GPS path filter helpers ───────────────────────────────────────────────

  bool _shouldAcceptPoint(Position pos) {
    final lat = pos.latitude;
    final lng = pos.longitude;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;
    if (pos.accuracy > _kMaxAccuracyMetres) return false;
    final candidate = LatLng(lat, lng);
    if (_lastAcceptedPoint != null && _lastAcceptedTime != null) {
      final distM = _haversineMetres(_lastAcceptedPoint!, candidate);
      if (distM < _kMinDistanceMetres) return false;
      final elapsedSec =
          DateTime.now().difference(_lastAcceptedTime!).inMilliseconds / 1000.0;
      if (elapsedSec > 0 && distM / elapsedSec > _kMaxSpeedMs) return false;
    }
    return true;
  }

  static double _haversineMetres(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(h.toDouble()));
  }

  // ── Location ──────────────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    await Geolocator.requestPermission();
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
      try {
        _mapController.move(LatLng(pos.latitude, pos.longitude), 16);
      } catch (_) {}
    } catch (_) {}

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
      if (!_userHasMovedMap) {
        try {
          _mapController.move(
            LatLng(pos.latitude, pos.longitude),
            _mapController.camera.zoom,
          );
        } catch (_) {}
      }
      if (_recordStatus == 'active') {
        if (_shouldAcceptPoint(pos)) {
          final accepted = LatLng(pos.latitude, pos.longitude);
          _lastAcceptedPoint = accepted;
          _lastAcceptedTime = DateTime.now();
          setState(() {
            _routePoints.add(accepted);
          });
        }
      }
    });
  }

  // ── BLE ───────────────────────────────────────────────────────────────────

  Future<void> _connectBle() async {
    final device = BleState.currentDevice;
    if (device == null) return;

    _connSub = device.connectionState.listen((s) {
      if (!mounted) return;
      final connected = s == BluetoothConnectionState.connected;
      setState(() {
        _bleConnected = connected;
        if (!connected) {
          _latestMethane = '--';
          _latestEthane = '--';
        }
      });
    });

    try {
      await device.connect(autoConnect: false);
      if (!mounted) return;
      setState(() => _bleConnected = true);
      await _startSessionFile(device);
      final services = await device.discoverServices();
      for (final svc in services) {
        for (final c in svc.characteristics) {
          if (svc.uuid == _serviceUUID && c.uuid == _charUUID) {
            await c.setNotifyValue(true);
            c.onValueReceived.listen(_onBleData);
            return;
          }
        }
      }
    } catch (_) {}
  }

  void _onBleData(List<int> value) async {
    final raw = _parseCSV(String.fromCharCodes(value).trim());
    if (raw.isEmpty) return;

    final gpsUtc = DateTime.now().toUtc().toIso8601String();

    if (!mounted) return;
    setState(() {
      _latestMethane = raw['Methane (ppm)'] ?? '--';
      _latestEthane = raw['Ethane (ppm)'] ?? '--';
    });

    // Always write to legacy CSV cache
    await _saveToCache(raw, gpsUtc);

    // SQLite insert only when actively recording
    if (_recordStatus == 'active' && _activeMeasurement?.id != null) {
      try {
        final db = await DatabaseService.instance();
        await db.insertReading(
          Reading(
            measurementId: _activeMeasurement!.id!,
            gpsUtc: gpsUtc,
            errorCode: int.tryParse(raw['Error Code'] ?? '0') ?? 0,
            methanePpm: double.tryParse(raw['Methane (ppm)'] ?? '0') ?? 0.0,
            ethanePpm: double.tryParse(raw['Ethane (ppm)'] ?? '0') ?? 0.0,
            latitude: _lat,
            longitude: _lng,
          ),
        );
      } catch (_) {}
    }

    final methane = double.tryParse(raw['Methane (ppm)'] ?? '0') ?? 0.0;
    if (_alarmEnabled && methane > _threshold) _triggerAlarm(methane);
  }

  Map<String, String> _parseCSV(String line) {
    final parts = line.split(',');
    if (parts.length != 4) return {};
    return {
      'Error Code': parts[1],
      'Methane (ppm)': parts[2],
      'Ethane (ppm)': parts[3],
    };
  }

  Future<void> _startSessionFile(BluetoothDevice device) async {
    final cache = widget.cache ?? BleState.currentCache;
    if (cache == null) return;
    final sess = await cache.nextSessionNumber();
    final devId = device.remoteId.str.replaceAll(':', '').toLowerCase();
    final last6 = devId.length >= 6 ? devId.substring(devId.length - 6) : devId;
    final now = DateTime.now().toUtc();
    final stamp =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}Z';
    _sessionFile =
        'survey_workspace_${last6}_session_${sess.toString().padLeft(3, '0')}_$stamp.csv';
    await cache.ensureHeader(
      basename: _sessionFile!,
      headerLine:
          'GPS UTC,Error Code,Methane (ppm),Ethane (ppm),Phone Latitude,Phone Longitude',
      ttl: _ttl,
      mime: 'text/csv',
      meta: {
        'schema': 'sensor_v1',
        'device_id': device.remoteId.str,
        'session_number': sess,
        'session_started_utc': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  Future<void> _saveToCache(Map<String, String> raw, String gpsUtc) async {
    final cache = widget.cache ?? BleState.currentCache;
    if (cache == null || _sessionFile == null) return;
    try {
      final line = [
        gpsUtc,
        raw['Error Code'] ?? '',
        raw['Methane (ppm)'] ?? '',
        raw['Ethane (ppm)'] ?? '',
        _lat?.toString() ?? '',
        _lng?.toString() ?? '',
      ].join(',');
      await cache.appendLine(
        basename: _sessionFile!,
        line: line,
        ttl: _ttl,
        mime: 'text/csv',
      );
      await cache.enforceMaxBytes(_maxCacheBytes);
    } catch (_) {}
  }

  void _triggerAlarm(double ppm) async {
    final now = DateTime.now();
    if (_lastAlarmTime != null &&
        now.difference(_lastAlarmTime!) < const Duration(seconds: 30)) {
      return;
    }
    _lastAlarmTime = now;
    try {
      await _player.play(AssetSource('alert.mp3'));
    } catch (_) {}
    if (_lifecycleState == AppLifecycleState.resumed) {
      _showThresholdDialog(ppm);
    } else {
      ThresholdNotificationService.showAlert(ppm);
    }
  }

  void _showThresholdDialog(double ppm) {
    if (!mounted || _alertDialogVisible) return;
    _alertDialogVisible = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Threshold Alert'),
        content: Text(
          'Threshold ${ppm.toStringAsFixed(0)}(ppm) crossed. Review ASAP!',
        ),
        actions: [
          TextButton(
            onPressed: () {
              _player.stop();
              setState(() => _alertDialogVisible = false);
              Navigator.of(ctx).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ── Recording controls ────────────────────────────────────────────────────

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> _showStartDialog() async {
    // Pre-load surveys for this surveyor
    final db = await DatabaseService.instance();
    final surveys = await db.getSurveysForSurveyor(widget.surveyor.id!);
    if (!mounted) return;

    final result = await showModalBottomSheet<StartMeasurementResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StartMeasurementSheet(surveys: surveys),
    );
    if (result == null || !mounted) return;

    // Resolve survey
    int surveyId;
    String surveyName;
    Survey targetSurvey;
    if (result.existingSurveyId != null) {
      targetSurvey = surveys.firstWhere((s) => s.id == result.existingSurveyId);
      surveyId = targetSurvey.id!;
      surveyName = targetSurvey.name;
    } else {
      // Check for duplicate survey name
      final exists = await db.surveyNameExistsForSurveyor(
        widget.surveyor.id!,
        result.newSurveyName!,
      );
      if (!mounted) return;
      if (exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Survey "${result.newSurveyName}" already exists'),
          ),
        );
        return;
      }
      surveyId = await db.insertSurvey(Survey(
        name: result.newSurveyName!,
        surveyorName: widget.surveyor.name,
        surveyorId: widget.surveyor.id,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));
      if (!mounted) return;
      surveyName = result.newSurveyName!;
      targetSurvey = Survey(
        id: surveyId,
        name: surveyName,
        surveyorName: widget.surveyor.name,
        surveyorId: widget.surveyor.id,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
    }

    // Duplicate measurement name check
    final measExists = await db.measurementNameExistsForSurvey(
      surveyId,
      result.measurementName,
    );
    if (!mounted) return;
    if (measExists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Measurement "${result.measurementName}" already exists in this survey',
          ),
        ),
      );
      return;
    }

    // Storage check
    final storageResult = await StorageCheckService.check(
      photos: result.expectedPhotos,
      videos: result.expectedVideos,
    );
    if (!mounted) return;

    if (storageResult.needsWarning) {
      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dCtx) => AlertDialog(
          title: const Text('Storage almost full'),
          content: const Text(
            'Storage is almost finished. Photos and videos may be lost if you continue.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Leave'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(dCtx, true),
              child: const Text('Continue anyway'),
            ),
          ],
        ),
      );
      if (!mounted || proceed != true) return;
    }

    // Create measurement and go active
    final startedAt = DateTime.now().toUtc().toIso8601String();
    final mId = await db.insertMeasurement(
      Measurement(
        surveyId: surveyId,
        name: result.measurementName,
        status: 'active',
        startedAt: startedAt,
        expectedJoints: result.expectedJoints,
        expectedPhotos: result.expectedPhotos,
        expectedVideos: result.expectedVideos,
      ),
    );

    if (!mounted) return;

    setState(() {
      _recordStatus = 'active';
      _activeSurvey = targetSurvey;
      _activeMeasurement = Measurement(
        id: mId,
        surveyId: surveyId,
        name: result.measurementName,
        status: 'active',
        startedAt: startedAt,
        expectedJoints: result.expectedJoints,
        expectedPhotos: result.expectedPhotos,
        expectedVideos: result.expectedVideos,
      );
    });
    _stopwatch
      ..reset()
      ..start();
    _startTicker();
  }

  Future<void> _pauseRecording() async {
    if (_activeMeasurement?.id == null) return;
    try {
      final db = await DatabaseService.instance();
      final updated = _activeMeasurement!.copyWith(status: 'paused');
      await db.updateMeasurement(updated);
      if (!mounted) return;
      setState(() {
        _recordStatus = 'paused';
        _activeMeasurement = updated;
      });
      _stopwatch.stop();
    } catch (_) {}
  }

  Future<void> _resumeRecording() async {
    if (_activeMeasurement?.id == null) return;
    try {
      final db = await DatabaseService.instance();
      final updated = _activeMeasurement!.copyWith(status: 'active');
      await db.updateMeasurement(updated);
      if (!mounted) return;
      setState(() {
        _recordStatus = 'active';
        _activeMeasurement = updated;
      });
      _stopwatch.start();
      _startTicker();
    } catch (_) {}
  }

  Future<void> _finishRecording() async {
    if (_activeMeasurement?.id == null) return;
    try {
      final db = await DatabaseService.instance();
      final updated = _activeMeasurement!.copyWith(
        status: 'stopped',
        stoppedAt: DateTime.now().toUtc().toIso8601String(),
      );
      await db.updateMeasurement(updated);
      if (!mounted) return;
      setState(() {
        _recordStatus = 'stopped';
        _activeMeasurement = updated;
      });
      _stopwatch.stop();
      _stopTicker();
    } catch (_) {}
  }

  void _resetForNewRecording() {
    _stopwatch.reset();
    _leakNoteCtrl.clear();
    _lastAcceptedPoint = null;
    _lastAcceptedTime = null;
    setState(() {
      _recordStatus = 'idle';
      _activeMeasurement = null;
      _activeSurvey = null;
      _routePoints = [];
      _leakMarkerPoints = [];
      _showLeakOverlay = false;
      _leakPickedMediaPath = null;
      _userHasMovedMap = false;
      _alertDialogVisible = false;
    });
  }

  // ── Public API for cross-tab measurement activation ───────────────────────

  Future<void> _loadRouteForMeasurement(int id) async {
    try {
      final db = await DatabaseService.instance();
      final readings = await db.getReadingsForMeasurement(id);
      final points = readings
          .where((r) => r.latitude != null && r.longitude != null)
          .map((r) => LatLng(r.latitude!, r.longitude!))
          .toList();
      if (mounted) setState(() => _routePoints = points);
    } catch (_) {}
  }

  Future<void> _loadLeakMarkersForMeasurement(int id) async {
    try {
      final db = await DatabaseService.instance();
      final leaks = await db.getLeakMarksForMeasurement(id);
      final points = leaks
          .where((lm) => lm.latitude != null && lm.longitude != null)
          .map((lm) => LatLng(lm.latitude!, lm.longitude!))
          .toList();
      if (mounted) setState(() => _leakMarkerPoints = points);
    } catch (_) {}
  }

  /// Public getter so parent screens can check recording state.
  String get recordStatus => _recordStatus;

  void activateMeasurement(Measurement m) {
    _stopwatch.stop();
    _stopwatch.reset();
    _ticker?.cancel();
    _userHasMovedMap = false;
    _lastAcceptedPoint = null;
    _lastAcceptedTime = null;
    setState(() {
      _activeMeasurement = m;
      _recordStatus = m.status == 'active'
          ? 'active'
          : m.status == 'paused'
              ? 'paused'
              : m.status == 'stopped'
                  ? 'stopped'
                  : 'idle';
    });
    if (_recordStatus == 'active') {
      _stopwatch.start();
      _startTicker();
    }
    // Close any open overlays when measurement changes
    if (mounted) {
      _leakNoteCtrl.clear();
      setState(() {
        _showAlarmOverlay = false;
        _showNotesOverlay = false;
        _showLeakOverlay = false;
        _leakPickedMediaPath = null;
        _notes = [];
        _alertDialogVisible = false;
      });
    }
    if (m.id != null) {
      _loadRouteForMeasurement(m.id!);
      _loadLeakMarkersForMeasurement(m.id!);
    } else {
      setState(() {
        _routePoints = [];
        _leakMarkerPoints = [];
      });
    }
  }

  // ── Notes helpers ─────────────────────────────────────────────────────────

  Future<void> _loadNotes() async {
    if (_activeMeasurement?.id == null) return;
    try {
      final db = await DatabaseService.instance();
      final notes = await db.getNotesForMeasurement(_activeMeasurement!.id!);
      if (mounted) setState(() => _notes = notes);
    } catch (_) {}
  }

  Future<void> _addNote() async {
    final text = _noteCtrl.text.trim();
    if (text.isEmpty || _activeMeasurement?.id == null) return;
    final db = await DatabaseService.instance();
    await db.insertNote(Note(
      measurementId: _activeMeasurement!.id!,
      text: text,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    ));
    _noteCtrl.clear();
    await _loadNotes();
  }

  Future<void> _deleteNote(int noteId) async {
    final db = await DatabaseService.instance();
    await db.deleteNote(noteId);
    await _loadNotes();
  }

  // ── Media capture ─────────────────────────────────────────────────────────

  Future<void> _capturePhoto() async {
    if (_activeMeasurement == null || _recordStatus != 'active') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start a measurement to capture GPS-tagged media.'),
        ),
      );
      return;
    }
    final picked = await ImagePicker().pickImage(source: ImageSource.camera);
    if (picked == null) return;
    final appDir = await getApplicationDocumentsDirectory();
    final surveyId = _activeMeasurement!.surveyId;
    final measurementId = _activeMeasurement!.id!;
    final destDir = Directory(
      p.join(appDir.path, 'survey_$surveyId', 'measurement_$measurementId'),
    );
    if (!await destDir.exists()) await destDir.create(recursive: true);
    final now = DateTime.now().toUtc();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final destPath = p.join(destDir.path, 'photo_$stamp.jpg');
    await File(picked.path).copy(destPath);
    final db = await DatabaseService.instance();
    await db.insertMediaFile(
      MediaFile(
        measurementId: measurementId,
        path: destPath,
        type: 'photo',
        timestamp: now.toIso8601String(),
        latitude: _lat,
        longitude: _lng,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Photo saved.')),
    );
  }

  Future<void> _captureVideo() async {
    if (_activeMeasurement == null || _recordStatus != 'active') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start a measurement to capture GPS-tagged media.'),
        ),
      );
      return;
    }
    final picked = await ImagePicker().pickVideo(source: ImageSource.camera);
    if (picked == null) return;
    final appDir = await getApplicationDocumentsDirectory();
    final surveyId = _activeMeasurement!.surveyId;
    final measurementId = _activeMeasurement!.id!;
    final destDir = Directory(
      p.join(appDir.path, 'survey_$surveyId', 'measurement_$measurementId'),
    );
    if (!await destDir.exists()) await destDir.create(recursive: true);
    final now = DateTime.now().toUtc();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final destPath = p.join(destDir.path, 'video_$stamp.mp4');
    await File(picked.path).copy(destPath);
    final db = await DatabaseService.instance();
    await db.insertMediaFile(
      MediaFile(
        measurementId: measurementId,
        path: destPath,
        type: 'video',
        timestamp: now.toIso8601String(),
        latitude: _lat,
        longitude: _lng,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Video saved.')),
    );
  }

  /// Builds the leak mark overlay panel, consistent with alarm/notes panels.
  Widget _buildLeakPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xEE1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Mark Leak',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => setState(() {
                    _showLeakOverlay = false;
                    _leakNoteCtrl.clear();
                    _leakPickedMediaPath = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _leakNoteCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white38),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.orange),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.photo_camera, color: Colors.redAccent),
              label: Text(
                _leakPickedMediaPath != null
                    ? 'Photo attached'
                    : 'Attach Photo (optional)',
                style: const TextStyle(color: Colors.white70),
              ),
              onPressed: () async {
                final xf =
                    await ImagePicker().pickImage(source: ImageSource.camera);
                if (xf != null && mounted) {
                  setState(() => _leakPickedMediaPath = xf.path);
                }
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _showLeakOverlay = false;
                    _leakNoteCtrl.clear();
                    _leakPickedMediaPath = null;
                  }),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade800,
                  ),
                  onPressed: _activeMeasurement?.id == null
                      ? null
                      : () async {
                          String? savedMediaPath;
                          if (_leakPickedMediaPath != null) {
                            try {
                              final dir =
                                  await getApplicationDocumentsDirectory();
                              final mDir = Directory(
                                '${dir.path}/survey_${_activeMeasurement!.surveyId}'
                                '/measurement_${_activeMeasurement!.id}',
                              );
                              await mDir.create(recursive: true);
                              final stamp = DateTime.now()
                                  .toUtc()
                                  .toIso8601String()
                                  .replaceAll(RegExp(r'[:\-T]'), '')
                                  .substring(0, 15);
                              final ext = p.extension(_leakPickedMediaPath!);
                              savedMediaPath = '${mDir.path}/leak_$stamp$ext';
                              await File(_leakPickedMediaPath!)
                                  .copy(savedMediaPath);
                            } catch (_) {
                              savedMediaPath = _leakPickedMediaPath;
                            }
                          }
                          final noteText = _leakNoteCtrl.text.trim();
                          final lm = LeakMark(
                            measurementId: _activeMeasurement!.id!,
                            timestamp: DateTime.now().toUtc().toIso8601String(),
                            latitude: _lat,
                            longitude: _lng,
                            note: noteText.isEmpty ? null : noteText,
                            mediaPath: savedMediaPath,
                          );
                          final db = await DatabaseService.instance();
                          await db.insertLeakMark(lm);
                          if (!mounted) return;
                          setState(() {
                            _showLeakOverlay = false;
                            _leakNoteCtrl.clear();
                            _leakPickedMediaPath = null;
                            if (lm.latitude != null && lm.longitude != null) {
                              _leakMarkerPoints.add(
                                LatLng(lm.latitude!, lm.longitude!),
                              );
                            }
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Leak marked')),
                          );
                        },
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _noteCtrl.dispose();
    _leakNoteCtrl.dispose();
    _positionStream?.cancel();
    _connSub?.cancel();
    _ticker?.cancel();
    _player.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _buildMap()),
        _buildRecordPanel(context),
      ],
    );
  }

  Widget _buildMap() {
    final Widget mapWidget;
    if (_lat == null || _lng == null) {
      mapWidget = const ColoredBox(
        color: Color(0xFF1a2335),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white54),
              SizedBox(height: 12),
              Text(
                'Getting location...',
                style: TextStyle(color: Colors.white54),
              ),
            ],
          ),
        ),
      );
    } else {
      mapWidget = FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: LatLng(_lat!, _lng!),
          initialZoom: 16.0,
          onMapEvent: (MapEvent e) {
            if (e is MapEventMoveStart &&
                (e.source == MapEventSource.dragStart ||
                    e.source == MapEventSource.onDrag)) {
              if (!_userHasMovedMap && mounted) {
                setState(() => _userHasMovedMap = true);
              }
            }
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
            userAgentPackageName: 'com.sensorx.blu',
          ),
          if (_routePoints.length >= 2)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: _routePoints,
                  color: const Color(0x55000000),
                  strokeWidth: 7.0,
                ),
              ],
            ),
          if (_routePoints.length >= 2)
            PolylineLayer(
              polylines: [
                Polyline(
                  points: _routePoints,
                  color: const Color(0xFF7d0d0d),
                  strokeWidth: 4.5,
                ),
              ],
            ),
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(_lat!, _lng!),
                width: 17,
                height: 17,
                child: Container(
                  width: 17,
                  height: 17,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.blue,
                    border: Border.fromBorderSide(
                      BorderSide(color: Colors.white, width: 1.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_leakMarkerPoints.isNotEmpty)
            MarkerLayer(
              markers: _leakMarkerPoints
                  .map(
                    (pt) => Marker(
                      point: pt,
                      width: 36,
                      height: 36,
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange,
                        size: 28,
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      );
    }

    return Stack(
      children: [
        mapWidget,
        Positioned(right: 12, top: 12, child: _buildMapFabs()),
        if (_showAlarmOverlay)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildAlarmPanel(),
          ),
        if (_showNotesOverlay)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildNotesPanel(),
          ),
        if (_showLeakOverlay)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildLeakPanel(),
          ),
      ],
    );
  }

  Widget _buildMapFabs() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MapFab(
          icon: Icons.alarm,
          active: _showAlarmOverlay,
          onTap: () => setState(() {
            _showAlarmOverlay = !_showAlarmOverlay;
            _showNotesOverlay = false;
            _showLeakOverlay = false;
          }),
        ),
        const SizedBox(height: 10),
        _MapFab(
          icon: Icons.note_alt_outlined,
          active: _showNotesOverlay,
          onTap: () {
            setState(() {
              _showNotesOverlay = !_showNotesOverlay;
              _showAlarmOverlay = false;
              _showLeakOverlay = false;
            });
            if (_showNotesOverlay) _loadNotes();
          },
        ),
        const SizedBox(height: 10),
        _MapFab(icon: Icons.camera_alt, active: false, onTap: _capturePhoto),
        const SizedBox(height: 10),
        _MapFab(icon: Icons.videocam, active: false, onTap: _captureVideo),
        const SizedBox(height: 10),
        _MapFab(
          icon: Icons.warning_amber_rounded,
          active: _showLeakOverlay,
          onTap: () {
            if (_recordStatus != 'active') {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Start a measurement first')),
              );
              return;
            }
            setState(() {
              _showLeakOverlay = !_showLeakOverlay;
              if (_showLeakOverlay) {
                _showAlarmOverlay = false;
                _showNotesOverlay = false;
              }
            });
          },
        ),
      ],
    );
  }

  Widget _buildAlarmPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Color(0xEE1a1a1a),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Alarm Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => setState(() => _showAlarmOverlay = false),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Enable alarm',
              style: TextStyle(color: Colors.white),
            ),
            value: _alarmEnabled,
            activeColor: Colors.red.shade400,
            onChanged: (v) => setState(() => _alarmEnabled = v),
          ),
          Row(
            children: [
              const Text(
                'Threshold',
                style: TextStyle(color: Colors.white70),
              ),
              Expanded(
                child: Slider(
                  min: 0,
                  max: 500,
                  divisions: 100,
                  value: _threshold,
                  activeColor: Colors.red.shade400,
                  onChanged: (v) => setState(() => _threshold = v),
                ),
              ),
              Text(
                '${_threshold.toStringAsFixed(0)} ppm',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotesPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      constraints: const BoxConstraints(maxHeight: 300),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Color(0xEE1a1a1a),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Notes',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => setState(() => _showNotesOverlay = false),
              ),
            ],
          ),
          if (_activeMeasurement == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Start or select a measurement to add notes.',
                style: TextStyle(color: Colors.white54),
              ),
            )
          else ...[
            Flexible(
              child: _notes.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No notes yet.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _notes.length,
                      itemBuilder: (_, i) => Row(
                        children: [
                          Expanded(
                            child: Text(
                              _notes[i].text,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.white38,
                              size: 20,
                            ),
                            onPressed: () => _deleteNote(_notes[i].id!),
                          ),
                        ],
                      ),
                    ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _noteCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Add a note…',
                      hintStyle: const TextStyle(color: Colors.white38),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send, color: Colors.red.shade400),
                  onPressed: _addNote,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecordPanel(BuildContext context) {
    final Color statusColor;
    final String statusText;
    switch (_recordStatus) {
      case 'active':
        statusColor = Colors.green.shade600;
        statusText = 'Active';
        break;
      case 'paused':
        statusColor = Colors.orange.shade700;
        statusText = 'Paused';
        break;
      case 'stopped':
        statusColor = const Color(0xFFF5A623); // amber like screenshot
        statusText = 'Stopped';
        break;
      default:
        statusColor = Colors.grey.shade700;
        statusText = 'Idle';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Coloured status header — mirrors the Strava-style banner
        Container(
          width: double.infinity,
          color: statusColor,
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                statusText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              if (_activeSurvey != null) ...[
                const SizedBox(width: 10),
                Text(
                  '· ${_activeSurvey!.name}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        // Dark stats row — Time | CH₄ | C₂H₆
        Container(
          color: const Color(0xFF1a1a1a),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Row(
            children: [
              _StatCell(
                label: 'CH₄ (ppm)',
                value: _bleConnected ? _latestMethane : 'No BLE',
                dimmed: !_bleConnected,
              ),
              const _PanelDivider(),
              _StatCell(
                label: 'C₂H₆ (ppm)',
                value: _bleConnected ? _latestEthane : '--',
                dimmed: !_bleConnected,
              ),
            ],
          ),
        ),
        // Buttons on dark background
        Container(
          color: const Color(0xFF1a1a1a),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: _buildButtons(),
        ),
      ],
    );
  }

  void _navigateToBle() {
    final cache = widget.cache ?? BleState.currentCache;
    if (!mounted || cache == null) return;
    Navigator.popUntil(context, (r) => r.isFirst);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BleScanWaitScreen(cache: cache),
      ),
    );
  }

  Future<bool> _checkBleConnected() async {
    final isConnected =
        BleState.currentDevice != null && BleState.currentDevice!.isConnected;
    if (isConnected) return true;
    if (!mounted) return false;
    final goToBle = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No Device Connected'),
        content: const Text(
          'No device connected. Please connect a sensor before starting a measurement.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Go to BLE'),
          ),
        ],
      ),
    );
    if (goToBle == true && mounted) _navigateToBle();
    return false;
  }

  Widget _buildButtons() {
    switch (_recordStatus) {
      case 'idle':
        return _PillButton(
          icon: Icons.play_arrow,
          label: 'Start',
          color: Colors.green.shade500,
          onPressed: () async {
            if (await _checkBleConnected()) await _showStartDialog();
          },
        );
      case 'active':
        return Row(
          children: [
            Expanded(
              child: _PillButton(
                icon: Icons.pause,
                label: 'Pause',
                color: Colors.orange.shade700,
                onPressed: _pauseRecording,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PillButton(
                icon: Icons.flag_outlined,
                label: 'Finish',
                outlined: true,
                onPressed: _finishRecording,
              ),
            ),
          ],
        );
      case 'paused':
        return Row(
          children: [
            Expanded(
              child: _PillButton(
                icon: Icons.play_arrow,
                label: 'Resume',
                color: Colors.red.shade500,
                onPressed: _resumeRecording,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PillButton(
                icon: Icons.flag_outlined,
                label: 'Finish',
                outlined: true,
                onPressed: _finishRecording,
              ),
            ),
          ],
        );
      case 'stopped':
        return _PillButton(
          icon: Icons.play_arrow,
          label: 'New Recording',
          color: Colors.green.shade500,
          onPressed: () async {
            if (await _checkBleConnected()) {
              _resetForNewRecording();
              await _showStartDialog();
            }
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final bool dimmed;

  const _StatCell(
      {required this.label, required this.value, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: dimmed ? Colors.grey : Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _PanelDivider extends StatelessWidget {
  const _PanelDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 36, color: Colors.white24);
  }
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final bool outlined;
  final VoidCallback onPressed;

  const _PillButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: OutlinedButton.icon(
          icon: Icon(icon, color: Colors.white),
          label: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.white54),
            shape: const StadiumBorder(),
          ),
          onPressed: onPressed,
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        icon: Icon(icon),
        label: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          shape: const StadiumBorder(),
        ),
        onPressed: onPressed,
      ),
    );
  }
}

class _MapFab extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _MapFab({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: active
              ? Colors.red.shade700.withValues(alpha: 0.9)
              : const Color(0xFF000000),
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
