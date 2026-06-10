class Surveyor {
  final int? id;
  final String name;

  const Surveyor({this.id, required this.name});

  factory Surveyor.fromMap(Map<String, dynamic> map) =>
      Surveyor(id: map['id'] as int?, name: map['name'] as String);

  Map<String, dynamic> toMap() => {'id': id, 'name': name};

  Surveyor copyWith({int? id, String? name}) =>
      Surveyor(id: id ?? this.id, name: name ?? this.name);
}
