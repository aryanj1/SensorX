class LeakMark {
  final int? id;
  final int measurementId;
  final String timestamp;
  final double? latitude;
  final double? longitude;
  final String? note;
  final String? mediaPath;

  const LeakMark({
    this.id,
    required this.measurementId,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.note,
    this.mediaPath,
  });

  factory LeakMark.fromMap(Map<String, dynamic> m) => LeakMark(
        id: m['id'] as int?,
        measurementId: m['measurement_id'] as int,
        timestamp: m['timestamp'] as String,
        latitude: (m['latitude'] as num?)?.toDouble(),
        longitude: (m['longitude'] as num?)?.toDouble(),
        note: m['note'] as String?,
        mediaPath: m['media_path'] as String?,
      );

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'measurement_id': measurementId,
      'timestamp': timestamp,
      'latitude': latitude,
      'longitude': longitude,
      'note': note,
      'media_path': mediaPath,
    };
    if (id != null) map['id'] = id;
    return map;
  }
}
