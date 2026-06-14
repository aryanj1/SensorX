class MediaFile {
  final int? id;
  final int measurementId;
  final String path;
  final String type;
  final String timestamp;
  final double? latitude;
  final double? longitude;

  const MediaFile({
    this.id,
    required this.measurementId,
    required this.path,
    required this.type,
    required this.timestamp,
    this.latitude,
    this.longitude,
  });

  factory MediaFile.fromMap(Map<String, dynamic> map) {
    return MediaFile(
      id: map['id'] as int?,
      measurementId: map['measurement_id'] as int,
      path: map['path'] as String,
      type: map['type'] as String,
      timestamp: map['timestamp'] as String,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'measurement_id': measurementId,
      'path': path,
      'type': type,
      'timestamp': timestamp,
      'latitude': latitude,
      'longitude': longitude,
    };
    if (id != null) m['id'] = id;
    return m;
  }

  MediaFile copyWith({
    int? id,
    int? measurementId,
    String? path,
    String? type,
    String? timestamp,
    double? latitude,
    double? longitude,
  }) {
    return MediaFile(
      id: id ?? this.id,
      measurementId: measurementId ?? this.measurementId,
      path: path ?? this.path,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}
