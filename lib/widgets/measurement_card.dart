import 'package:flutter/material.dart';

import 'package:blu/models/measurement.dart';

/// A card that displays a single [Measurement] with its name and status badge.
class MeasurementCard extends StatelessWidget {
  final Measurement measurement;
  final VoidCallback? onTap;
  final VoidCallback? onViewReadings;
  final VoidCallback? onDelete;

  const MeasurementCard({
    super.key,
    required this.measurement,
    this.onTap,
    this.onViewReadings,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        title: Text(
          measurement.name,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatusBadge(status: statusFromString(measurement.status)),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.list_alt),
              tooltip: 'View logged readings',
              onPressed: onViewReadings,
            ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
                onPressed: onDelete,
              ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private status badge
// ---------------------------------------------------------------------------

class _StatusBadge extends StatelessWidget {
  final MeasurementStatus status;

  const _StatusBadge({required this.status});

  Color _color() {
    switch (status) {
      case MeasurementStatus.idle:
        return Colors.grey;
      case MeasurementStatus.active:
        return Colors.green;
      case MeasurementStatus.paused:
        return Colors.orange;
      case MeasurementStatus.stopped:
        return Colors.red;
    }
  }

  String _label() {
    final raw = status.name; // e.g. 'idle'
    return raw[0].toUpperCase() + raw.substring(1); // 'Idle'
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _label(),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
