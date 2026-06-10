class Survey {
  final int? id;
  final String name;
  final String surveyorName;
  final String createdAt;
  final String? deviceId;
  final String? deviceName;

  const Survey({
    this.id,
    required this.name,
    required this.surveyorName,
    required this.createdAt,
    this.deviceId,
    this.deviceName,
  });

  factory Survey.fromMap(Map<String, dynamic> map) {
    return Survey(
      id: map['id'] as int?,
      name: map['name'] as String,
      surveyorName: map['surveyor_name'] as String,
      createdAt: map['created_at'] as String,
      deviceId: map['device_id'] as String?,
      deviceName: map['device_name'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'name': name,
      'surveyor_name': surveyorName,
      'created_at': createdAt,
      'device_id': deviceId,
      'device_name': deviceName,
    };
    if (id != null) m['id'] = id;
    return m;
  }

  Survey copyWith({
    int? id,
    String? name,
    String? surveyorName,
    String? createdAt,
    String? deviceId,
    String? deviceName,
  }) {
    return Survey(
      id: id ?? this.id,
      name: name ?? this.name,
      surveyorName: surveyorName ?? this.surveyorName,
      createdAt: createdAt ?? this.createdAt,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
    );
  }
}
