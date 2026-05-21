import 'package:uuid/uuid.dart';

/// A user-defined tag for organizing sessions and folders.
///
/// Stays Flutter-package-free — the [Tag] model is plain data so
/// `core/tags/` can be consumed by tests / future headless tools
/// without dragging in `package:flutter`. UI-side helpers (the
/// [Color] resolver) live in `lib/widgets/core/tag_color.dart`.
class Tag {
  final String id;
  final String name;

  /// Hex color string (e.g. '#FF5722'), or null for default.
  /// The Flutter [Color] resolution lives in the
  /// `lib/widgets/core/tag_color.dart` extension.
  final String? color;
  final DateTime createdAt;

  Tag({String? id, required this.name, this.color, DateTime? createdAt})
    : id = id ?? const Uuid().v4(),
      createdAt = createdAt ?? DateTime.now();

  Tag copyWith({String? name, String? color}) {
    return Tag(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Tag && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Tag($id, $name)';
}

/// Predefined tag colors for the color picker.
const tagColors = [
  '#EF5350', // red
  '#EC407A', // pink
  '#AB47BC', // purple
  '#5C6BC0', // indigo
  '#42A5F5', // blue
  '#26C6DA', // cyan
  '#66BB6A', // green
  '#D4E157', // lime
  '#FFA726', // orange
  '#8D6E63', // brown
];
