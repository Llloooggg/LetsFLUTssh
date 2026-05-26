import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logs/log_store.dart';

/// Process-singleton handle to the in-memory [LogStore]. The Settings
/// → Logs viewer reads `ref.read(logStoreProvider)` to attach a
/// `ListenableBuilder` against the always-running buffer; the boot
/// wiring calls `ensureSeeded()` on the same instance after FRB init
/// so opening the tab is instant.
final logStoreProvider = Provider<LogStore>((_) => LogStore.instance);
