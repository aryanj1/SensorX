enum MeasurementStatus { idle, active, paused, stopped }

MeasurementStatus statusFromString(String s) {
  switch (s) {
    case 'active':
      return MeasurementStatus.active;
    case 'paused':
      return MeasurementStatus.paused;
    case 'stopped':
      return MeasurementStatus.stopped;
    case 'idle':
    default:
      return MeasurementStatus.idle;
  }
}

class Measurement {
  final int? id;
  final int surveyId;
  final String name;
  final String status;
  final String? startedAt;
  final String? stoppedAt;

  const Measurement({
    this.id,
    required this.surveyId,
    required this.name,
    required this.status,
    this.startedAt,
    this.stoppedAt,
  });

  factory Measurement.fromMap(Map<String, dynamic> map) {
    return Measurement(
      id: map['id'] as int?,
      surveyId: map['survey_id'] as int,
      name: map['name'] as String,
      status: map['status'] as String,
      startedAt: map['started_at'] as String?,
      stoppedAt: map['stopped_at'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'survey_id': surveyId,
      'name': name,
      'status': status,
      'started_at': startedAt,
      'stopped_at': stoppedAt,
    };
    if (id != null) m['id'] = id;
    return m;
  }

  Measurement copyWith({
    int? id,
    int? surveyId,
    String? name,
    String? status,
    String? startedAt,
    String? stoppedAt,
  }) {
    return Measurement(
      id: id ?? this.id,
      surveyId: surveyId ?? this.surveyId,
      name: name ?? this.name,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      stoppedAt: stoppedAt ?? this.stoppedAt,
    );
  }
}
