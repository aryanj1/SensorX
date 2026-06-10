import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blu/app.dart';
import 'package:blu/models/surveyor.dart';
import 'package:blu/services/ble_state.dart';
import 'package:blu/services/cache_service.dart';
import 'package:blu/services/database_service.dart';
import 'package:blu/screens/files/pending_files_screen.dart';
import 'package:blu/screens/measurement/measurement_screen.dart';
import 'package:blu/screens/surveyor/surveyor_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _initCache();
    _loadData();
    _loadTheme();
  }

  Future<void> _initCache() async {
    final cache = await TTLFileCache.open();
    if (!mounted) return;
    setState(() {
      _cache = cache;
      _cacheReady = true;
    });
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('theme_mode');
    App.themeModeNotifier.value =
        saved == 'dark' ? ThemeMode.dark : ThemeMode.light;
    if (mounted) setState(() {});
  }

  Future<void> _toggleTheme() async {
    final isDark = App.themeModeNotifier.value == ThemeMode.dark;
    App.themeModeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', isDark ? 'light' : 'dark');
    if (mounted) setState(() {});
  }

  Future<void> _loadData() async {
    final db = await DatabaseService.instance();
    final results = await db.getAllSurveyors();
    if (!mounted) return;
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
        title: const Text('blu'),
        actions: [
          IconButton(
            icon: Icon(
              App.themeModeNotifier.value == ThemeMode.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            tooltip: 'Toggle theme',
            onPressed: _toggleTheme,
          ),
          IconButton(
            icon: const Icon(Icons.bluetooth),
            tooltip: 'BLE Scanner',
            onPressed: _cacheReady
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BLEScannerScreen(cache: _cache!),
                      ),
                    )
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Pending files',
            onPressed: _cacheReady
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PendingFilesScreen(cache: _cache!),
                      ),
                    )
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
      return const Center(
        child: Text('No surveyors yet. Tap + to add one.'),
      );
    }
    return ListView.builder(
      itemCount: _surveyors.length,
      itemBuilder: (context, index) {
        final s = _surveyors[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(s.name),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete surveyor',
              onPressed: () => _confirmDeleteSurveyor(s),
            ),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SurveyorScreen(surveyor: s, cache: _cache),
                ),
              );
              _loadData();
            },
          ),
        );
      },
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

class _BLEScannerScreenState extends State<BLEScannerScreen> {
  final List<ScanResult> foundDevices = [];

  // Convenience getter — HomeScreen guarantees cache is ready before push.
  TTLFileCache get _cache => widget.cache;

  @override
  void initState() {
    super.initState();
    _startBLEScan();
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
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (!foundDevices.any((d) => d.device.remoteId == r.device.remoteId)) {
          if (mounted) setState(() => foundDevices.add(r));
        }
      }
    });
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  void _connectAndShowData(BluetoothDevice device) {
    BleState.currentDevice = device;
    BleState.currentCache = _cache;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeasurementScreen(device: device, cache: _cache),
      ),
    );
  }

  void _openPendingFiles() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PendingFilesScreen(cache: _cache),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Scanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder),
            tooltip: 'Pending files',
            onPressed: _openPendingFiles,
          ),
        ],
      ),
      body: foundDevices.isEmpty
          ? const Center(child: Text('Scanning for BLE devices...'))
          : ListView.builder(
              itemCount: foundDevices.length,
              itemBuilder: (context, index) {
                final device = foundDevices[index].device;
                return ListTile(
                  title: Text(device.platformName.isNotEmpty
                      ? device.platformName
                      : '(Unknown Device)'),
                  subtitle: Text(device.remoteId.str),
                  trailing: Text('${foundDevices[index].rssi} dBm'),
                  onTap: () => _connectAndShowData(device),
                );
              },
            ),
    );
  }
}
