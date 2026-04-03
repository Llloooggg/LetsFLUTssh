import 'package:uuid/uuid.dart';

import '../../core/connection/connection.dart';

const _uuid = Uuid();

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

  /// Create a duplicate with a new unique ID but same connection/label/kind.
  TabEntry duplicate() {
    return TabEntry(
      id: _uuid.v4(),
      label: label,
      connection: connection,
      kind: kind,
    );
  }
}
