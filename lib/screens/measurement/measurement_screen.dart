import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:vibration/vibration.dart';

import 'package:blu/app.dart';

import '../../models/measurement.dart';
import '../../models/media_file.dart';
import '../../models/reading.dart';
import '../../services/cache_service.dart';
import '../../services/database_service.dart';
import '../files/pending_files_screen.dart';

class MeasurementScreen extends StatefulWidget {
  final BluetoothDevice? device;
  final TTLFileCache? cache;
  final Measurement? measurement;

  const MeasurementScreen({
    super.key,
    this.device,
    this.cache,
    this.measurement,
  });

  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen> {
  final List<Map<String, String>> dataLog = [];
  final List<LatLng> customMarkers = [];
  BluetoothCharacteristic? notifyChar;
  bool isPaused = false;
  bool alarmEnabled = true;
  double threshold = 50.0;
  bool compactView = false;
  String latestMethane = '--';
  String latestEthane = '--';

  String? phoneLatitude;
  String? phoneLongitude;
  String? gpsUtcIso;

  late String _measurementStatus;

  final serviceUUID = Guid('4fafc201-1fb5-459e-8fcc-c5c9c331914b');
  final charUUID = Guid('beb5483e-36e1-4688-b7f5-ea07361b26a8');

  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  final AudioPlayer _player = AudioPlayer();
  DateTime? _lastAlarmTime;
  final Duration _alarmCooldown = const Duration(seconds: 10);

  static const _ttl = Duration(days: 14);
  static const _maxCacheBytes = 200 * 1024 * 1024;
  String? _sessionFile;

  @override
  void initState() {
    super.initState();
    _measurementStatus = widget.measurement?.status ?? 'idle';
    _getPhoneLocation();
    _startLiveLocationTracking();
    if (widget.device != null) {
      _connectAndListen();
      _watchConnectionState();
    }
  }

  String _slug(String s) {
    final cleaned = s.trim().replaceAll(' ', '_');
    return cleaned.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
  }

  String _fmtUtc(DateTime dt) {
    final z = dt.toUtc();
    String p2(int n) => n.toString().padLeft(2, '0');
    return '${z.year}-${p2(z.month)}-${p2(z.day)}_${p2(z.hour)}-${p2(z.minute)}-${p2(z.second)}Z';
  }

  Future<void> _startSessionFile() async {
    if (widget.cache == null) return;
    final sess = await widget.cache!.nextSessionNumber();

    final devId = widget.device!.remoteId.str.replaceAll(':', '').toLowerCase();
    final last6 = devId.length >= 6 ? devId.substring(devId.length - 6) : devId;
    final devName = widget.device!.platformName.isNotEmpty
        ? widget.device!.platformName
        : 'device';
    final niceName = _slug(devName);
    final stamp = _fmtUtc(DateTime.now());

    final name =
        'survey_${niceName}_${last6}_session_${sess.toString().padLeft(3, '0')}_$stamp.csv';
    _sessionFile = name;

    const header =
        'GPS UTC,Error Code,Methane (ppm),Ethane (ppm),Phone Latitude,Phone Longitude';
    await widget.cache!.ensureHeader(
      basename: name,
      headerLine: header,
      ttl: _ttl,
      mime: 'text/csv',
      meta: {
        'schema': 'sensor_v1',
        'device_name': widget.device!.platformName,
        'device_id': widget.device!.remoteId.str,
        'session_number': sess,
        'session_started_utc': DateTime.now().toUtc().toIso8601String(),
      },
    );
    setState(() {});
  }

  void _watchConnectionState() {
    if (widget.device == null) return;
    _connSub = widget.device!.connectionState.listen((s) async {
      if (s == BluetoothConnectionState.disconnected) {
        setState(() {
          _sessionFile = null;
        });
      }
    });
  }

  void _startLiveLocationTracking() {
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );
    _positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position pos) {
        setState(() {
          phoneLatitude = pos.latitude.toString();
          phoneLongitude = pos.longitude.toString();
          gpsUtcIso = pos.timestamp.toUtc().toIso8601String();
        });
        _mapController.move(LatLng(pos.latitude, pos.longitude), 16);
      },
    );
  }

  Future<void> _getPhoneLocation() async {
    await Geolocator.requestPermission();
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    setState(() {
      phoneLatitude = pos.latitude.toString();
      phoneLongitude = pos.longitude.toString();
      gpsUtcIso = pos.timestamp.toUtc().toIso8601String();
    });
  }

  Future<void> _connectAndListen() async {
    try {
      await widget.device!.connect(autoConnect: false);
      await _startSessionFile();
      final services = await widget.device!.discoverServices();
      for (final service in services) {
        for (final c in service.characteristics) {
          if (service.uuid == serviceUUID && c.uuid == charUUID) {
            notifyChar = c;
            await c.setNotifyValue(true);
            c.onValueReceived.listen((value) async {
              if (isPaused) return;
              final received = String.fromCharCodes(value).trim();
              final raw = parseCSV(received);
              if (raw.isNotEmpty) {
                final gpsUtc =
                    gpsUtcIso ?? DateTime.now().toUtc().toIso8601String();
                final ordered = <String, String>{
                  'GPS UTC': gpsUtc,
                  'Error Code': raw['Error Code'] ?? '',
                  'Methane (ppm)': raw['Methane (ppm)'] ?? '',
                  'Ethane (ppm)': raw['Ethane (ppm)'] ?? '',
                };
                if (phoneLatitude != null) {
                  ordered['Phone Latitude'] = phoneLatitude!;
                }
                if (phoneLongitude != null) {
                  ordered['Phone Longitude'] = phoneLongitude!;
                }

                setState(() {
                  latestMethane = ordered['Methane (ppm)'] ?? '--';
                  latestEthane = ordered['Ethane (ppm)'] ?? '--';
                  if (dataLog.length > 500) dataLog.removeAt(0);
                  dataLog.add(ordered);
                });

                await _saveReadingToCache(ordered);

                if (_measurementStatus == 'active' &&
                    widget.measurement?.id != null) {
                  final db = await DatabaseService.instance();
                  await db.insertReading(
                    Reading(
                      measurementId: widget.measurement!.id!,
                      gpsUtc:
                          gpsUtcIso ?? DateTime.now().toUtc().toIso8601String(),
                      errorCode:
                          int.tryParse(ordered['Error Code'] ?? '0') ?? 0,
                      methanePpm:
                          double.tryParse(ordered['Methane (ppm)'] ?? '0') ??
                              0.0,
                      ethanePpm:
                          double.tryParse(ordered['Ethane (ppm)'] ?? '0') ??
                              0.0,
                      latitude: phoneLatitude != null
                          ? double.tryParse(phoneLatitude!)
                          : null,
                      longitude: phoneLongitude != null
                          ? double.tryParse(phoneLongitude!)
                          : null,
                    ),
                  );
                }

                final methane =
                    double.tryParse(ordered['Methane (ppm)'] ?? '0') ?? 0;
                if (alarmEnabled && methane > threshold) {
                  _triggerAlarm(methane);
                }
              }
            });
            return;
          }
        }
      }
    } catch (_) {
      // connection failure is surfaced via the no-BLE banner
    }
  }

  void _togglePause() => setState(() => isPaused = !isPaused);

  void _triggerAlarm(double value) async {
    final now = DateTime.now();
    if (_lastAlarmTime != null &&
        now.difference(_lastAlarmTime!) < _alarmCooldown) {
      return;
    }
    _lastAlarmTime = now;
    if ((await Vibration.hasVibrator()) == true) {
      Vibration.vibrate(duration: 500);
    }
    await _player.play(AssetSource('alert.mp3'));
  }

  Map<String, String> parseCSV(String line) {
    final parts = line.split(',');
    if (parts.length != 4) return {};
    return {
      'Error Code': parts[1],
      'Methane (ppm)': parts[2],
      'Ethane (ppm)': parts[3],
    };
  }

  Future<void> _saveReadingToCache(Map<String, String> row) async {
    if (widget.cache == null) return;
    try {
      _sessionFile ??=
          'survey_fallback_session_${DateTime.now().millisecondsSinceEpoch}.csv';

      const header =
          'GPS UTC,Error Code,Methane (ppm),Ethane (ppm),Phone Latitude,Phone Longitude';
      await widget.cache!.ensureHeader(
        basename: _sessionFile!,
        headerLine: header,
        ttl: _ttl,
        mime: 'text/csv',
        meta: {'schema': 'sensor_v1'},
      );

      final line = [
        row['GPS UTC'] ??
            (gpsUtcIso ?? DateTime.now().toUtc().toIso8601String()),
        row['Error Code'] ?? '',
        row['Methane (ppm)'] ?? '',
        row['Ethane (ppm)'] ?? '',
        row['Phone Latitude'] ?? '',
        row['Phone Longitude'] ?? '',
      ].join(',');

      await widget.cache!.appendLine(
        basename: _sessionFile!,
        line: line,
        ttl: _ttl,
        mime: 'text/csv',
      );

      await widget.cache!.enforceMaxBytes(_maxCacheBytes);
    } catch (_) {
      // cache write failure is non-fatal
    }
  }

  Future<void> _capturePhoto() async {
    if (_measurementStatus != 'active') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start measurement to capture GPS-tagged media.'),
        ),
      );
      return;
    }
    if (widget.measurement?.id == null) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.camera);
    if (picked == null) return;
    final appDir = await getApplicationDocumentsDirectory();
    final surveyId = widget.measurement!.surveyId;
    final measurementId = widget.measurement!.id!;
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
        latitude:
            phoneLatitude != null ? double.tryParse(phoneLatitude!) : null,
        longitude:
            phoneLongitude != null ? double.tryParse(phoneLongitude!) : null,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Photo saved.')));
  }

  Future<void> _captureVideo() async {
    if (_measurementStatus != 'active') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start measurement to capture GPS-tagged media.'),
        ),
      );
      return;
    }
    if (widget.measurement?.id == null) return;
    final picked = await ImagePicker().pickVideo(source: ImageSource.camera);
    if (picked == null) return;
    final appDir = await getApplicationDocumentsDirectory();
    final surveyId = widget.measurement!.surveyId;
    final measurementId = widget.measurement!.id!;
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
        latitude:
            phoneLatitude != null ? double.tryParse(phoneLatitude!) : null,
        longitude:
            phoneLongitude != null ? double.tryParse(phoneLongitude!) : null,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Video saved.')));
  }

  Future<void> _startMeasurement() async {
    if (widget.measurement?.id == null) return;
    final db = await DatabaseService.instance();
    final updated = widget.measurement!.copyWith(
      status: 'active',
      startedAt: widget.measurement!.startedAt ??
          DateTime.now().toUtc().toIso8601String(),
    );
    await db.updateMeasurement(updated);
    if (!mounted) return;
    setState(() => _measurementStatus = 'active');
  }

  Future<void> _pauseMeasurement() async {
    if (widget.measurement?.id == null) return;
    final db = await DatabaseService.instance();
    final updated = widget.measurement!.copyWith(status: 'paused');
    await db.updateMeasurement(updated);
    if (!mounted) return;
    setState(() => _measurementStatus = 'paused');
  }

  Future<void> _stopMeasurement() async {
    if (widget.measurement?.id == null) return;
    final db = await DatabaseService.instance();
    final updated = widget.measurement!.copyWith(
      status: 'stopped',
      stoppedAt: DateTime.now().toUtc().toIso8601String(),
    );
    await db.updateMeasurement(updated);
    if (!mounted) return;
    setState(() => _measurementStatus = 'stopped');
  }

  @override
  void dispose() {
    widget.device?.disconnect();
    _positionStream?.cancel();
    _connSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _openPendingFiles() {
    if (widget.cache == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PendingFilesScreen(cache: widget.cache!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: sensorXRed,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.device != null && widget.device!.platformName.isNotEmpty
              ? 'Connected: ${widget.device!.platformName}'
              : widget.measurement?.name ?? 'Measurement',
        ),
        actions: [
          IconButton(
            icon: Icon(compactView ? Icons.list : Icons.view_compact),
            tooltip: compactView ? 'Full View' : 'Compact View',
            onPressed: () => setState(() => compactView = !compactView),
          ),
          IconButton(
            icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
            tooltip: isPaused ? 'Resume stream' : 'Pause stream',
            onPressed: _togglePause,
          ),
          if (widget.cache != null)
            IconButton(
              icon: const Icon(Icons.folder),
              tooltip: 'Pending files',
              onPressed: _openPendingFiles,
            ),
        ],
      ),
      body: Column(
        children: [
          if (widget.device == null)
            Container(
              width: double.infinity,
              color: Colors.orange.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: const Text(
                'No BLE device connected — GPS and map active only',
                style: TextStyle(fontSize: 12),
              ),
            ),
          if (_sessionFile != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  const Icon(Icons.save_alt, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Saving to: $_sessionFile',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (widget.measurement != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_measurementStatus == 'idle' ||
                      _measurementStatus == 'paused')
                    FilledButton.icon(
                      onPressed: _startMeasurement,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start'),
                    ),
                  if (_measurementStatus == 'active')
                    FilledButton.icon(
                      onPressed: _pauseMeasurement,
                      icon: const Icon(Icons.pause),
                      label: const Text('Pause'),
                    ),
                  if (_measurementStatus == 'active' ||
                      _measurementStatus == 'paused') ...[
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _stopMeasurement,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    ),
                  ],
                ],
              ),
            ),
          if (widget.measurement != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Photo'),
                    onPressed: _capturePhoto,
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.videocam),
                    label: const Text('Video'),
                    onPressed: _captureVideo,
                  ),
                ],
              ),
            ),
          if (phoneLatitude != null && phoneLongitude != null)
            SizedBox(
              height: 200,
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: LatLng(
                    double.parse(phoneLatitude!),
                    double.parse(phoneLongitude!),
                  ),
                  initialZoom: 16.0,
                  onTap: (tapPos, latlng) =>
                      setState(() => customMarkers.add(latlng)),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c'],
                    userAgentPackageName: 'com.sensorx.blu',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(
                          double.parse(phoneLatitude!),
                          double.parse(phoneLongitude!),
                        ),
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.circle,
                          color: Colors.blue,
                          size: 18,
                        ),
                      ),
                      ...customMarkers.map(
                        (pos) => Marker(
                          point: pos,
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Getting phone location...'),
            ),
          ElevatedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Current Coordinates: $phoneLatitude, $phoneLongitude',
                  ),
                ),
              );
            },
            child: const Text('Get Coordinates'),
          ),
          SwitchListTile(
            title: const Text('Enable Alarm'),
            value: alarmEnabled,
            onChanged: (val) => setState(() => alarmEnabled = val),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Threshold: '),
              Slider(
                min: 0,
                max: 100,
                divisions: 20,
                value: threshold,
                label: threshold.toStringAsFixed(0),
                onChanged: (val) => setState(() => threshold = val),
              ),
              Text('${threshold.toStringAsFixed(0)} ppm'),
            ],
          ),
          const Divider(height: 1),
          if (widget.measurement == null || _measurementStatus == 'active')
            Expanded(
              child: compactView
                  ? Center(
                      child: Card(
                        margin: const EdgeInsets.all(20),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'Methane: $latestMethane ppm\nEthane: $latestEthane ppm',
                            style: const TextStyle(fontSize: 20),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    )
                  : dataLog.isEmpty
                      ? const Center(child: Text('Waiting for data...'))
                      : ListView.builder(
                          itemCount: dataLog.length,
                          itemBuilder: (context, index) {
                            final entry = dataLog[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: entry.entries
                                      .map(
                                        (e) => Text(
                                          '${e.key}: ${e.value}',
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            );
                          },
                        ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Measurement is not active. Tap Start to begin displaying and logging readings.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }
}
