class Reading {
  final int? id;
  final int measurementId;
  final String gpsUtc;
  final int errorCode;
  final double methanePpm;
  final double ethanePpm;
  final double? latitude;
  final double? longitude;

  const Reading({
    this.id,
    required this.measurementId,
    required this.gpsUtc,
    required this.errorCode,
    required this.methanePpm,
    required this.ethanePpm,
    this.latitude,
    this.longitude,
  });

  factory Reading.fromMap(Map<String, dynamic> map) {
    return Reading(
      id: map['id'] as int?,
      measurementId: map['measurement_id'] as int,
      gpsUtc: map['gps_utc'] as String,
      errorCode: map['error_code'] as int,
      methanePpm: (map['methane_ppm'] as num).toDouble(),
      ethanePpm: (map['ethane_ppm'] as num).toDouble(),
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'measurement_id': measurementId,
      'gps_utc': gpsUtc,
      'error_code': errorCode,
      'methane_ppm': methanePpm,
      'ethane_ppm': ethanePpm,
      'latitude': latitude,
      'longitude': longitude,
    };
    if (id != null) m['id'] = id;
    return m;
  }
}
