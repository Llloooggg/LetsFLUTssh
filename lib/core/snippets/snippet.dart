import 'package:uuid/uuid.dart';

/// A reusable command snippet.
class Snippet {
  final String id;
  final String title;
  final String command;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;

  Snippet({
    String? id,
    required this.title,
    required this.command,
    this.description = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Snippet copyWith({String? title, String? command, String? description}) {
    return Snippet(
      id: id,
      title: title ?? this.title,
      command: command ?? this.command,
      description: description ?? this.description,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Snippet &&
          id == other.id &&
          title == other.title &&
          command == other.command;

  @override
  int get hashCode => Object.hash(id, title, command);

  @override
  String toString() => 'Snippet($id, $title)';
}
