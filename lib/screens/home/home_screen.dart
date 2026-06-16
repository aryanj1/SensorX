import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:blu/app.dart';
import 'package:blu/models/surveyor.dart';
import 'package:blu/services/ble_state.dart';
import 'package:blu/services/cache_service.dart';
import 'package:blu/services/database_service.dart';
import 'package:blu/screens/ble/ble_scan_wait_screen.dart';
import 'package:blu/screens/surveyor/surveyor_workspace_screen.dart';

// routeObserver is declared in app.dart and imported via package:blu/app.dart.

// ---------------------------------------------------------------------------
// HomeScreen — surveyor list + navigation hub
// ---------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Surveyor> _surveyors = [];
  bool _loading = true;
  bool _cacheReady = false;
  TTLFileCache? _cache;
  final Map<int, bool> _surveyorHasActive = {};

  @override
  void initState() {
    super.initState();
    _initCache();
    _loadData();
  }

  Future<void> _initCache() async {
    final cache = await TTLFileCache.open();
    if (!mounted) return;
    setState(() {
      _cache = cache;
      _cacheReady = true;
    });
  }

  Future<void> _loadData() async {
    final db = await DatabaseService.instance();
    final results = await db.getAllSurveyors();
    final activeResults = await Future.wait(
      results.map((s) => db.hasActiveMeasurementForSurveyor(s.id!)),
    );
    if (!mounted) return;
    _surveyorHasActive.clear();
    for (var i = 0; i < results.length; i++) {
      _surveyorHasActive[results[i].id!] = activeResults[i];
    }
    setState(() {
      _surveyors = results;
      _loading = false;
    });
  }

  // ---------------------------------------------------------------------------
  // New surveyor dialog
  // ---------------------------------------------------------------------------

  Future<void> _showNewSurveyorDialog() async {
    final nameController = TextEditingController();
    String? nameError;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('New Surveyor'),
              content: TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Surveyor name *',
                  errorText: nameError,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      setDialogState(() => nameError = 'Name is required');
                      return;
                    }
                    final db = await DatabaseService.instance();
                    final exists = await db.surveyorNameExists(name);
                    if (exists) {
                      setDialogState(
                        () => nameError =
                            'A surveyor named "$name" already exists',
                      );
                      return;
                    }
                    await db.insertSurveyor(Surveyor(name: name));
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    await _loadData();
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Delete surveyor confirmation
  // ---------------------------------------------------------------------------

  Future<void> _confirmDeleteSurveyor(Surveyor s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Surveyor'),
        content: Text(
          "Delete '${s.name}'? All surveys, measurements and readings will be deleted.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = await DatabaseService.instance();
    await db.deleteSurveyor(s.id!);
    _loadData();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        centerTitle: true,
        backgroundColor: sensorXRed,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        title: Image.asset(
          'assets/icons/home_logo.png',
          width: MediaQuery.of(context).size.width * 0.62,
          fit: BoxFit.contain,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bluetooth),
            tooltip: 'BLE Scanner',
            onPressed: _cacheReady
                ? () {
                    if (_cache == null) return;
                    final connected = BleState.currentDevice != null &&
                        BleState.currentDevice!.isConnected;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => connected
                            ? BLEScannerScreen(cache: _cache!)
                            : BleScanWaitScreen(cache: _cache!),
                      ),
                    );
                  }
                : null,
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewSurveyorDialog,
        tooltip: 'New surveyor',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_surveyors.isEmpty) {
      return const Center(child: Text('No surveyors yet. Tap + to add one.'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Surveyors',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _surveyors.length,
            itemBuilder: (context, index) {
              final s = _surveyors[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: sensorXRed,
                    child: const Icon(Icons.person, color: Colors.white),
                  ),
                  title: Text(s.name),
                  subtitle: _surveyorHasActive[s.id] == true
                      ? const Text(
                          'Active',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete surveyor',
                    onPressed: () => _confirmDeleteSurveyor(s),
                  ),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SurveyorWorkspaceScreen(surveyor: s, cache: _cache),
                      ),
                    );
                    _loadData();
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// BLEScannerScreen — cache is now injected; no longer initialised here
// ---------------------------------------------------------------------------

class BLEScannerScreen extends StatefulWidget {
  final TTLFileCache cache;

  const BLEScannerScreen({super.key, required this.cache});

  @override
  State<BLEScannerScreen> createState() => _BLEScannerScreenState();
}

class _BLEScannerScreenState extends State<BLEScannerScreen> with RouteAware {
  final List<ScanResult> foundDevices = [];
  StreamSubscription<bool>? _scanSub;
  StreamSubscription<List<ScanResult>>? _resultsSub;
  BluetoothDevice? _connectedDevice;

  // Convenience getter — HomeScreen guarantees cache is ready before push.
  TTLFileCache get _cache => widget.cache;

  @override
  void initState() {
    super.initState();
    _connectedDevice = BleState.currentDevice;
    _startBLEScan();
    _scanSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (!scanning && mounted) setState(() => foundDevices.clear());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  /// Fired when the user pops back to this page from a pushed route.
  @override
  void didPopNext() {
    if (mounted) setState(() => _connectedDevice = BleState.currentDevice);
  }

  Future<void> _startBLEScan() async {
    await _requestPermissions();
    BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      await for (final newState in FlutterBluePlus.adapterState) {
        if (newState == BluetoothAdapterState.on) break;
      }
    }
    foundDevices.clear();
    FlutterBluePlus.startScan();
    _resultsSub = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (!_isLikelySensor(r)) continue;
        if (!foundDevices.any((d) => d.device.remoteId == r.device.remoteId)) {
          if (mounted) setState(() => foundDevices.add(r));
        }
      }
    });
  }

  /// Returns true if the device is likely an embedded sensor (not a consumer device).
  bool _isLikelySensor(ScanResult r) {
    const consumerKeywords = [
      'iphone',
      'ipad',
      'macbook',
      'mac mini',
      'mac pro',
      'imac',
      'airpods',
      'beats',
      'samsung',
      'galaxy',
      'pixel',
      'huawei',
      'oneplus',
      'xiaomi',
      'oppo',
      'realme',
      'vivo',
      'honor',
      'headphones',
      'earbuds',
      'earphone',
      'buds',
      'jbl',
      'bose',
      'sony',
      'jabra',
      'sennheiser',
      'skullcandy',
      'watch',
      'band',
      'fitbit',
      'garmin',
      'keyboard',
      'mouse',
      'trackpad',
      'tv ',
      ' tv',
      'television',
      'roku',
      'fire tv',
      'laptop',
      'thinkpad',
      'surface',
    ];
    final name = r.device.platformName.toLowerCase().trim();
    // Keep unnamed devices — likely embedded sensors.
    if (name.isEmpty) return true;
    return !consumerKeywords.any((kw) => name.contains(kw));
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<void> _disconnectCurrentDevice() async {
    final device = BleState.currentDevice;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
      BleState.currentDevice = null;
      BleState.currentCache = null;
      _connectedDevice = null;
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _scanSub?.cancel();
    _resultsSub?.cancel();
    super.dispose();
  }

  Future<void> _connectAndShowData(BluetoothDevice device) async {
    if (!device.isConnected) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Padding(
            padding: EdgeInsets.all(8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Connecting...'),
              ],
            ),
          ),
        ),
      );
      try {
        await device.connect(timeout: const Duration(seconds: 15));
        if (!mounted) return;
        Navigator.pop(context);
      } catch (e) {
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: ${e.toString()}')),
        );
        return;
      }
    }
    if (!mounted) return;
    BleState.currentDevice = device;
    BleState.currentCache = _cache;
    if (mounted) setState(() => _connectedDevice = device);
  }

  Widget _buildConnectedDeviceSection() {
    final device = _connectedDevice;
    if (device == null) return const SizedBox.shrink();
    return StreamBuilder<BluetoothConnectionState>(
      stream: device.connectionState,
      initialData: device.isConnected
          ? BluetoothConnectionState.connected
          : BluetoothConnectionState.disconnected,
      builder: (ctx, snap) {
        final isConnected = snap.data == BluetoothConnectionState.connected;
        if (!isConnected && !device.isConnected) return const SizedBox.shrink();
        final name = device.platformName.isNotEmpty
            ? device.platformName
            : device.remoteId.toString();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 16, 8),
              child: Text(
                'CONNECTED DEVICE',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                title: Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  'Connected',
                  style: TextStyle(color: Colors.green),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white54, size: 20),
                      onPressed: () async {
                        await _disconnectCurrentDevice();
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
                onTap: () => _connectAndShowData(device),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      appBar: AppBar(
        title: const Text('Bluetooth'),
        backgroundColor: sensorXRed,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scanning toggle
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            decoration: BoxDecoration(
              color: const Color(0xFF2C2C2E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: StreamBuilder<bool>(
              stream: FlutterBluePlus.isScanning,
              builder: (ctx, snap) {
                final scanning = snap.data ?? false;
                return SwitchListTile(
                  title: const Text(
                    'Bluetooth Scanning',
                    style: TextStyle(color: Colors.white),
                  ),
                  value: scanning,
                  activeColor: sensorXRed,
                  onChanged: (v) async {
                    if (v) {
                      _startBLEScan();
                    } else {
                      FlutterBluePlus.stopScan();
                      await _disconnectCurrentDevice();
                      if (mounted) setState(() => foundDevices.clear());
                    }
                  },
                );
              },
            ),
          ),
          // Connected device section
          _buildConnectedDeviceSection(),
          // Section header
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 16, 8),
            child: Text(
              'AVAILABLE DEVICES',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
          // Device list
          Expanded(
            child: foundDevices.isEmpty
                ? const Center(
                    child: Text(
                      'No devices found',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: foundDevices.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final device = foundDevices[i].device;
                      return Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF2C2C2E),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          title: Text(
                            device.platformName.isNotEmpty
                                ? device.platformName
                                : device.remoteId.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: StreamBuilder<BluetoothConnectionState>(
                            stream: device.connectionState,
                            builder: (ctx, snap) {
                              final state = snap.data ??
                                  BluetoothConnectionState.disconnected;
                              final isConnected =
                                  state == BluetoothConnectionState.connected;
                              return Text(
                                isConnected ? 'Connected' : 'Not Connected',
                                style: TextStyle(
                                  color:
                                      isConnected ? Colors.green : Colors.grey,
                                ),
                              );
                            },
                          ),
                          trailing: const Icon(
                            Icons.info_outline,
                            color: Colors.grey,
                          ),
                          onTap: () => _connectAndShowData(device),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
