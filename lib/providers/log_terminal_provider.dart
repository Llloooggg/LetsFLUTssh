import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logs/log_terminal.dart';

/// Process-singleton handle to the live [LogTerminal]. Settings →
/// Logs viewer reads `ref.read(logTerminalProvider)` to attach a
/// `TerminalView` against the always-running Terminal buffer; the
/// boot wiring calls `ensureSeeded()` on the same instance after
/// FRB init so opening the tab is instant.
final logTerminalProvider = Provider<LogTerminal>((_) => LogTerminal.instance);
