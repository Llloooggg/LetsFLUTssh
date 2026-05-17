import 'package:uuid/uuid.dart';

import '../../src/rust/api/forward.dart' as rust_forward;

/// Direction of an SSH port forward — re-export of the FRB-mirror
/// enum so call sites keep the short `PortForwardKind.remote` /
/// `PortForwardKind.dynamic_` identifiers. The single source of
/// truth (variant set + wire-string grammar) lives in
/// `lfs_core::portforward::RuleKind`; FRB lowers Rust's `Dynamic`
/// variant to Dart `dynamic_` so the keyword collision is avoided
/// while the on-wire byte stays `"dynamic"` — route through
/// [`rust_forward.portForwardKindToWire`] /
/// [`rust_forward.portForwardKindFromWire`] for any wire conversion.
typedef PortForwardKind = rust_forward.DbPortForwardKind;

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
  /// short reason string. The grammar (range bounds + per-kind
  /// target rules) lives in `lfs_core::portforward::validate_rule`
  /// so the runtime check here, any future import-path check, and
  /// the driver's own pre-flight share one source.
  String? validate() {
    final err = rust_forward.portForwardValidateRule(
      kind: kind,
      bindHost: bindHost,
      bindPort: bindPort,
      remoteHost: remoteHost,
      remotePort: remotePort,
    );
    if (err == null) return null;
    switch (err) {
      case rust_forward.DbPortForwardRuleValidationError.bindPortOutOfRange:
        return 'Bind port out of range';
      case rust_forward.DbPortForwardRuleValidationError.targetHostRequired:
        return 'Target host required';
      case rust_forward.DbPortForwardRuleValidationError.targetPortOutOfRange:
        return 'Target port out of range';
      case rust_forward.DbPortForwardRuleValidationError.bindHostRequired:
        return 'Bind host required';
    }
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
