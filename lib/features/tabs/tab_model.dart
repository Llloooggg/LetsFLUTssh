import '../../core/connection/connection.dart';

/// Type of tab content.
enum TabKind { terminal, sftp }

/// Model representing an open tab.
class TabEntry {
  final String id;
  final String label;
  final Connection connection;
  final TabKind kind;

  const TabEntry({
    required this.id,
    required this.label,
    required this.connection,
    required this.kind,
  });

  TabEntry copyWith({String? label}) {
    return TabEntry(
      id: id,
      label: label ?? this.label,
      connection: connection,
      kind: kind,
    );
  }
}
