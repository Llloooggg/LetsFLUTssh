import 'package:uuid/uuid.dart';

/// Direction of an SSH port forward.
///
/// v1 ships local-only (-L). Remote (-R) and dynamic SOCKS5 (-D) are
/// declared in the enum so the persistence layer rejects nothing on
/// import, but the runtime guards against running the unsupported
/// kinds — see `PortForwardRuntime` for the gating logic.
enum PortForwardKind { local, remote, dynamic_ }

extension PortForwardKindExt on PortForwardKind {
  String get wireName => switch (this) {
    PortForwardKind.local => 'local',
    PortForwardKind.remote => 'remote',
    PortForwardKind.dynamic_ => 'dynamic',
  };

  static PortForwardKind fromWireName(String? name) {
    switch (name) {
      case 'remote':
        return PortForwardKind.remote;
      case 'dynamic':
        return PortForwardKind.dynamic_;
      default:
        return PortForwardKind.local;
    }
  }
}

/// Immutable description of a single port-forward rule attached to a
/// session.
///
/// Rules live in their own DB table (one-to-many session→rules) so a
/// rule can be enabled / disabled / re-bound without rewriting the
/// session row. The runtime ([`PortForwardRuntime`]) opens a listener
/// for every `enabled` rule on connect and tears it down on
/// disconnect via the [`ConnectionExtension`] hooks.
class PortForwardRule {
  final String id;
  final PortForwardKind kind;
  final String bindHost;
  final int bindPort;
  final String remoteHost;
  final int remotePort;
  final String description;
  final bool enabled;
  final int sortOrder;
  final DateTime createdAt;

  PortForwardRule({
    String? id,
    required this.kind,
    this.bindHost = '127.0.0.1',
    required this.bindPort,
    required this.remoteHost,
    required this.remotePort,
    this.description = '',
    this.enabled = true,
    this.sortOrder = 0,
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  /// Return `null` when the rule's network params are valid, else a
  /// short reason string. Centralises the validation so the picker
  /// dialog and any import path agree on the same constraints.
  String? validate() {
    if (bindPort < 1 || bindPort > 65535) return 'Bind port out of range';
    // Local + remote forwards target a (host:port) on the SSH server
    // side; dynamic does not. Validate accordingly so a user-typed
    // partial rule does not crash the runtime.
    if (kind != PortForwardKind.dynamic_) {
      if (remoteHost.trim().isEmpty) return 'Target host required';
      if (remotePort < 1 || remotePort > 65535) {
        return 'Target port out of range';
      }
    }
    if (bindHost.trim().isEmpty) return 'Bind host required';
    return null;
  }

  /// Loopback-only check — used by the UI to surface a warning when
  /// the user types `0.0.0.0` (publishes the forward to every NIC,
  /// usually a footgun on a multi-user box).
  bool get bindsLoopbackOnly =>
      bindHost == '127.0.0.1' || bindHost == '::1' || bindHost == 'localhost';

  PortForwardRule copyWith({
    PortForwardKind? kind,
    String? bindHost,
    int? bindPort,
    String? remoteHost,
    int? remotePort,
    String? description,
    bool? enabled,
    int? sortOrder,
  }) => PortForwardRule(
    id: id,
    kind: kind ?? this.kind,
    bindHost: bindHost ?? this.bindHost,
    bindPort: bindPort ?? this.bindPort,
    remoteHost: remoteHost ?? this.remoteHost,
    remotePort: remotePort ?? this.remotePort,
    description: description ?? this.description,
    enabled: enabled ?? this.enabled,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.wireName,
    'bind_host': bindHost,
    'bind_port': bindPort,
    'remote_host': remoteHost,
    'remote_port': remotePort,
    if (description.isNotEmpty) 'description': description,
    'enabled': enabled,
    'sort_order': sortOrder,
    'created_at': createdAt.toIso8601String(),
  };

  factory PortForwardRule.fromJson(Map<String, dynamic> json) =>
      PortForwardRule(
        id: json['id'] as String?,
        kind: PortForwardKindExt.fromWireName(json['kind'] as String?),
        bindHost: json['bind_host'] as String? ?? '127.0.0.1',
        bindPort: json['bind_port'] as int? ?? 0,
        remoteHost: json['remote_host'] as String? ?? '',
        remotePort: json['remote_port'] as int? ?? 0,
        description: json['description'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
        sortOrder: json['sort_order'] as int? ?? 0,
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PortForwardRule &&
          id == other.id &&
          kind == other.kind &&
          bindHost == other.bindHost &&
          bindPort == other.bindPort &&
          remoteHost == other.remoteHost &&
          remotePort == other.remotePort &&
          description == other.description &&
          enabled == other.enabled &&
          sortOrder == other.sortOrder;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    bindHost,
    bindPort,
    remoteHost,
    remotePort,
    description,
    enabled,
    sortOrder,
  );
}
