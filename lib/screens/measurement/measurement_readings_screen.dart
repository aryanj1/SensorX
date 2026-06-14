import 'package:flutter/material.dart';

import 'package:blu/models/measurement.dart';
import 'package:blu/models/reading.dart';
import 'package:blu/services/database_service.dart';

/// Displays all SQLite readings logged for a single [Measurement].
class MeasurementReadingsScreen extends StatefulWidget {
  final Measurement measurement;

  const MeasurementReadingsScreen({super.key, required this.measurement});

  @override
  State<MeasurementReadingsScreen> createState() =>
      _MeasurementReadingsScreenState();
}

class _MeasurementReadingsScreenState extends State<MeasurementReadingsScreen> {
  List<Reading> _readings = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReadings();
  }

  Future<void> _loadReadings() async {
    if (widget.measurement.id == null) {
      setState(() {
        _error = 'No measurement ID';
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = await DatabaseService.instance();
      final results = await db.getReadingsForMeasurement(
        widget.measurement.id!,
      );
      if (!mounted) return;
      setState(() {
        _readings = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.measurement.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh readings',
            onPressed: _loadReadings,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadReadings,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_readings.isEmpty) {
      return const Center(
        child: Text(
          'No SQLite readings logged yet. Start this measurement and wait for BLE data.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _loadReadings(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CountHeader(count: _readings.length),
          Expanded(
            child: ListView.builder(
              itemCount: _readings.length,
              itemBuilder: (context, index) {
                final r = _readings[index];
                return _ReadingTile(reading: r);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Count header
// ---------------------------------------------------------------------------

class _CountHeader extends StatelessWidget {
  final int count;

  const _CountHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        '$count ${count == 1 ? 'reading' : 'readings'}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reading tile
// ---------------------------------------------------------------------------

class _ReadingTile extends StatelessWidget {
  final Reading reading;

  const _ReadingTile({required this.reading});

  @override
  Widget build(BuildContext context) {
    final r = reading;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: ListTile(
        dense: true,
        title: Text(
          '${r.gpsUtc}  |  CH4: ${r.methanePpm.toStringAsFixed(2)} ppm'
          '  |  C2H6: ${r.ethanePpm.toStringAsFixed(2)} ppm',
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          'Error: ${r.errorCode}  |  Lat: ${r.latitude?.toStringAsFixed(4) ?? '--'}'
          '  |  Lon: ${r.longitude?.toStringAsFixed(4) ?? '--'}',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}
