class Note {
  final int? id;
  final int measurementId;
  final String text;
  final String createdAt;

  const Note({
    this.id,
    required this.measurementId,
    required this.text,
    required this.createdAt,
  });

  factory Note.fromMap(Map<String, dynamic> m) => Note(
        id: m['id'] as int?,
        measurementId: m['measurement_id'] as int,
        text: m['text'] as String,
        createdAt: m['created_at'] as String,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'measurement_id': measurementId,
        'text': text,
        'created_at': createdAt,
      };
}
