import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:blu/models/measurement.dart';
import 'package:blu/models/survey.dart';
import 'package:blu/services/cache_service.dart';
import 'package:blu/services/database_service.dart';
import 'package:blu/services/ble_state.dart';
import 'package:blu/services/export_service.dart';
import 'package:blu/screens/measurement/measurement_readings_screen.dart';
import 'package:blu/screens/measurement/measurement_screen.dart';
import 'package:blu/widgets/measurement_card.dart';

/// Shows all measurements belonging to [survey] and lets the user create new ones.
class SurveyScreen extends StatefulWidget {
  final Survey survey;
  final TTLFileCache? cache;

  const SurveyScreen({super.key, required this.survey, this.cache});

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  List<Measurement> _measurements = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMeasurements();
  }

  Future<void> _exportZip() async {
    if (widget.survey.id == null) return;
    try {
      final path = await ExportService.exportSurveyZip(widget.survey.id!);
      if (!mounted) return;
      final result = await Share.shareXFiles([
        XFile(path),
      ], subject: 'Survey ZIP Export');
      if (!mounted) return;
      if (result.status == ShareResultStatus.dismissed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Share dismissed — ZIP was ready.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ZIP export error: $e')));
    }
  }

  Future<void> _exportCsv() async {
    if (widget.survey.id == null) return;
    try {
      final path = await ExportService.buildCsv(widget.survey.id!);
      if (!mounted) return;
      final result = await Share.shareXFiles([
        XFile(path),
      ], subject: 'Survey CSV Export');
      if (!mounted) return;
      if (result.status == ShareResultStatus.dismissed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Share dismissed — CSV was ready.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export error [v2]: $e')));
    }
  }

  Future<void> _loadMeasurements() async {
    if (widget.survey.id == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    final db = await DatabaseService.instance();
    final results = await db.getMeasurementsForSurvey(widget.survey.id!);
    if (!mounted) return;
    setState(() {
      _measurements = results;
      _loading = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Delete measurement confirmation
  // ---------------------------------------------------------------------------

  Future<void> _confirmDeleteMeasurement(Measurement m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Measurement'),
        content: Text("Delete '${m.name}'? All readings will be deleted."),
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
    await db.deleteMeasurement(m.id!);
    await _loadMeasurements();
  }

  // ---------------------------------------------------------------------------
  // New measurement dialog
  // ---------------------------------------------------------------------------

  Future<void> _showNewMeasurementDialog() async {
    final nameController = TextEditingController();
    String? nameError;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('New Measurement'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Measurement name *',
                      errorText: nameError,
                    ),
                  ),
                ],
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
                    await db.insertMeasurement(
                      Measurement(
                        surveyId: widget.survey.id!,
                        name: name,
                        status: 'idle',
                      ),
                    );
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    await _loadMeasurements();
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
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.survey.name),
            Text(
              'Surveyor: ${widget.survey.surveyorName}',
              style: textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onPrimary.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share CSV',
            onPressed: _exportCsv,
          ),
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            tooltip: 'Share ZIP',
            onPressed: _exportZip,
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewMeasurementDialog,
        tooltip: 'New measurement',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_measurements.isEmpty) {
      return const Center(
        child: Text('No measurements yet. Tap + to add one.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Measurements',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _measurements.length,
            itemBuilder: (context, index) {
              return MeasurementCard(
                measurement: _measurements[index],
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MeasurementScreen(
                        device: BleState.currentDevice,
                        cache: widget.cache ?? BleState.currentCache,
                        measurement: _measurements[index],
                      ),
                    ),
                  );
                  await _loadMeasurements();
                },
                onViewReadings: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MeasurementReadingsScreen(
                        measurement: _measurements[index],
                      ),
                    ),
                  );
                },
                onDelete: () => _confirmDeleteMeasurement(_measurements[index]),
              );
            },
          ),
        ),
      ],
    );
  }
}
