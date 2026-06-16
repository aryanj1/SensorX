import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:blu/app.dart';

import 'package:blu/models/measurement.dart';
import 'package:blu/models/survey.dart';
import 'package:blu/models/surveyor.dart';
import 'package:blu/services/ble_state.dart';
import 'package:blu/services/cache_service.dart';
import 'package:blu/services/database_service.dart';
import 'package:blu/screens/survey/survey_screen.dart';
import 'package:blu/screens/surveyor/record_map_tab.dart';

/// Top-level workspace screen reached after selecting a surveyor.
/// Two tabs: Record/Map (default) and Surveys.
class SurveyorWorkspaceScreen extends StatefulWidget {
  final Surveyor surveyor;
  final TTLFileCache? cache;

  const SurveyorWorkspaceScreen({
    super.key,
    required this.surveyor,
    this.cache,
  });

  @override
  State<SurveyorWorkspaceScreen> createState() =>
      _SurveyorWorkspaceScreenState();
}

class _SurveyorWorkspaceScreenState extends State<SurveyorWorkspaceScreen> {
  int _selectedIndex = 0;
  final _surveysKey = GlobalKey<_SurveysTabState>();
  final _recordMapKey = GlobalKey<RecordMapTabState>();

  Future<bool> _guardNavigation() async {
    final status = _recordMapKey.currentState?.recordStatus ?? 'idle';
    if (status == 'active') {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Active Measurement'),
          content: const Text(
            'Pause or finish the active measurement before leaving.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _onNavTap(int index) async {
    if (index != 0 && _selectedIndex == 0) {
      final allowed = await _guardNavigation();
      if (!allowed) return;
    }
    setState(() => _selectedIndex = index);
    // Refresh survey list whenever the tab is revealed
    if (index == 1) _surveysKey.currentState?.reload();
  }

  void _activateMeasurementOnMap(Measurement m) {
    setState(() => _selectedIndex = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recordMapKey.currentState?.activateMeasurement(m);
    });
  }

  Widget _buildConnectionBadge() {
    final device = BleState.currentDevice;
    if (device == null) return const SizedBox.shrink();
    return StreamBuilder<BluetoothConnectionState>(
      stream: device.connectionState,
      builder: (ctx, snap) {
        final connected = snap.data == BluetoothConnectionState.connected;
        if (!connected) return const SizedBox.shrink();
        return const Text(
          '● Connected',
          style: TextStyle(
            color: Colors.green,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final allowed = await _guardNavigation();
        if (allowed && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: sensorXRed,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          actionsIconTheme: const IconThemeData(color: Colors.white),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.surveyor.name),
              _buildConnectionBadge(),
            ],
          ),
        ),
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            RecordMapTab(
              key: _recordMapKey,
              surveyor: widget.surveyor,
              cache: widget.cache,
            ),
            _SurveysTab(
              key: _surveysKey,
              surveyor: widget.surveyor,
              cache: widget.cache,
              onMeasurementSelected: _activateMeasurementOnMap,
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onNavTap,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Record / Map',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder),
              label: 'Surveys',
            ),
          ],
        ),
      ),
    );
  }
}

// ── Surveys tab ───────────────────────────────────────────────────────────────

class _SurveysTab extends StatefulWidget {
  final Surveyor surveyor;
  final TTLFileCache? cache;
  final void Function(Measurement)? onMeasurementSelected;

  const _SurveysTab({
    super.key,
    required this.surveyor,
    this.cache,
    this.onMeasurementSelected,
  });

  @override
  State<_SurveysTab> createState() => _SurveysTabState();
}

class _SurveysTabState extends State<_SurveysTab> {
  List<Survey> _surveys = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSurveys();
  }

  /// Called by the parent workspace whenever the Surveys tab is selected.
  void reload() => _loadSurveys();

  Future<void> _loadSurveys() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final db = await DatabaseService.instance();
      final results = await db.getSurveysForSurveyor(widget.surveyor.id!);
      if (!mounted) return;
      setState(() {
        _surveys = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _showNewSurveyDialog() async {
    final nameCtrl = TextEditingController();
    String? nameError;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('New Survey'),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Survey name *',
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
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  setDlg(() => nameError = 'Name is required');
                  return;
                }
                final db = await DatabaseService.instance();
                final exists = await db.surveyNameExistsForSurveyor(
                  widget.surveyor.id!,
                  name,
                );
                if (exists) {
                  setDlg(
                    () => nameError = 'A survey named "$name" already exists',
                  );
                  return;
                }
                await db.insertSurvey(
                  Survey(
                    name: name,
                    surveyorName: widget.surveyor.name,
                    surveyorId: widget.surveyor.id,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  ),
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                await _loadSurveys();
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteSurvey(Survey s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Survey'),
        content: Text(
          "Delete '${s.name}'? All measurements and readings will be deleted.",
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
    await db.deleteSurvey(s.id!);
    await _loadSurveys();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
          child: Row(
            children: [
              Text(
                'Surveys',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'New survey',
                onPressed: _showNewSurveyDialog,
              ),
            ],
          ),
        ),
        if (_surveys.isEmpty)
          const Expanded(
            child: Center(child: Text('No surveys yet. Tap + to add one.')),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: _surveys.length,
              itemBuilder: (context, i) {
                final survey = _surveys[i];
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  elevation: 3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    title: Text(
                      survey.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(survey.createdAt),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.chevron_right),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete',
                          onPressed: () => _confirmDeleteSurvey(survey),
                        ),
                      ],
                    ),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SurveyScreen(
                            survey: survey,
                            cache: widget.cache,
                            onMeasurementSelected: widget.onMeasurementSelected,
                          ),
                        ),
                      );
                      await _loadSurveys();
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
