import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/connection/connection.dart';
import '../../core/connection/connection_step.dart';
import '../../core/connection/progress_tracker.dart';
import '../../core/connection/progress_writer.dart';
import '../../core/shortcut_registry.dart';
import '../../core/security/terminal_scrubber.dart';
import '../../core/session/session_recorder.dart';
import '../../core/ssh/shell_helper.dart';
import '../../providers/security_provider.dart';
import '../../providers/session_provider.dart';
import '../../core/config/app_config.dart';
import '../../providers/config_provider.dart';
import '../../providers/connection_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icon_button.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
import 'cursor_overlay.dart';
import '../../utils/terminal_clipboard.dart';
import '../../widgets/context_menu.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/platform.dart' as plat;
import '../snippets/snippet_picker.dart';
import '../../providers/broadcast_provider.dart';
import '../../widgets/app_dialog.dart';
import 'broadcast_controller.dart';

/// A single terminal pane — xterm TerminalView connected to one SSH shell.
///
/// Multiple panes can share the same [Connection] (each opens its own shell).
/// Factory for opening SSH shell — injectable for testing.
typedef ShellOpenFactory =
    Future<ShellConnection> Function({
      required Connection connection,
      required Terminal terminal,
      VoidCallback? onDone,
    });

class TerminalPane extends ConsumerStatefulWidget {
  final Connection connection;
  final bool isFocused;

  /// Whether there are multiple panes in the tiling layout.
  /// Focus border is only shown when this is true.
  final bool hasMultiplePanes;

  /// Tiling-tree leaf id — stable across rebuilds, used for the
  /// broadcast registry. Optional so tests / single-pane callers
  /// (mobile shell, quick-connect) can omit it.
  final String? paneId;

  /// Owning tab's stable id. Required together with [paneId] for the
  /// broadcast feature; both nullable so non-tabbed callers compile.
  final String? tabId;

  final VoidCallback? onFocused;
  final VoidCallback? onClose;

  /// Optional factory for testing — bypasses real SSH shell.
  final ShellOpenFactory? shellFactory;

  const TerminalPane({
    super.key,
    required this.connection,
    this.isFocused = false,
    this.hasMultiplePanes = false,
    this.paneId,
    this.tabId,
    this.onFocused,
    this.onClose,
    this.shellFactory,
  });

  /// True when both ids are present — guards every broadcast-related
  /// code path so the feature stays inert in single-pane / mobile
  /// surfaces that never plumb an id through.
  bool get supportsBroadcast => paneId != null && tabId != null;

  @override
  ConsumerState<TerminalPane> createState() => TerminalPaneState();
}

class TerminalPaneState extends ConsumerState<TerminalPane> {
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  ShellConnection? _shellConn;
  StreamSubscription<ConnectionStep>? _progressSub;
  Map<AppShortcut, VoidCallback>? _shortcuts;
  BroadcastController? _broadcast;
  VoidCallback? _broadcastUnsubscribe;

  /// Whether the terminal pane is in an error state.
  bool get hasError => _error != null;

  String? _error;

  // Search visibility — ValueNotifier so toggling doesn't rebuild TerminalView
  final _showSearch = ValueNotifier<bool>(false);

  /// Cached terminal theme — rebuilt only when app brightness changes.
  TerminalTheme? _cachedTheme;
  bool? _cachedIsDark;

  TerminalTheme get _terminalTheme {
    final dark = AppTheme.isDark;
    if (_cachedTheme == null || _cachedIsDark != dark) {
      _cachedIsDark = dark;
      _cachedTheme = AppTheme.terminalTheme;
    }
    return _cachedTheme!;
  }

  /// Exposed for testing — toggle search bar visibility.
  @visibleForTesting
  ValueNotifier<bool> get showSearchNotifier => _showSearch;

  /// Exposed for testing — access the xterm Terminal instance.
  @visibleForTesting
  Terminal get terminal => _terminal;

  /// Exposed for testing — access the TerminalController.
  @visibleForTesting
  TerminalController get terminalController => _terminalController;

  /// Exposed for testing — zoom in / out / reset.
  @visibleForTesting
  void zoomIn() => _zoomIn();
  @visibleForTesting
  void zoomOut() => _zoomOut();
  @visibleForTesting
  void zoomReset() => _zoomReset();

  /// Send a command string to the SSH shell.
  ///
  /// Appends a newline if not already present. No-op if shell is not open.
  void sendCommand(String command) {
    if (_shellConn == null) return;
    final cmd = command.endsWith('\n') ? command : '$command\n';
    _terminal.textInput(cmd);
  }

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: ref.read(configProvider).scrollback);
    _terminalController = TerminalController();
    // Register with the scrubber so auto-lock wipes this terminal's
    // scrollback alongside the DB key. Dispose removes us from the
    // registry so stale pointers do not linger.
    TerminalScrubber.instance.register(_terminal);
    HardwareKeyboard.instance.addHandler(_onShiftToggle);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectAndOpenShell();
    });
  }

  Future<void> _connectAndOpenShell() async {
    final conn = widget.connection;
    final l10n = S.of(context);
    final tracker = ProgressTracker(conn);
    final writer = ProgressWriter(
      terminal: _terminal,
      l10n: l10n,
      config: conn.sshConfig,
    );

    // Subscribe to progress stream and write steps to terminal
    _progressSub = writer.subscribe(tracker);

    // Wait for connection if still connecting
    await conn.waitUntilReady();
    _progressSub?.cancel();
    _progressSub = null;
    tracker.dispose();

    // Check connection result
    if (!conn.isConnected) {
      if (!mounted) return;
      // Mark disconnected so tab dot and connection bar update
      conn.state = SSHConnectionState.disconnected;
      final error = conn.connectionError != null
          ? localizeError(l10n, conn.connectionError!)
          : l10n.errConnectionFailed;
      _terminal.write('\x1B[?25h\x1B[31m$error\x1B[0m\r\n');
      setState(() => _error = error);
      // Notify provider so workspace status dots and connection bar update
      ref.read(connectionManagerProvider).notifyStateChanged();
      return;
    }

    try {
      // Clear progress log before opening shell — openShell wires stdout
      // to terminal.write(), so any server output must not be erased.
      writer.clear();
      _shellConn = await _openShell(conn);
      _attachBroadcast();
      // Notify provider so workspace status dots and connection bar update
      if (mounted) ref.read(connectionManagerProvider).notifyStateChanged();
    } catch (e) {
      AppLogger.instance.log(
        'Shell open failed: $e',
        name: 'TerminalPane',
        error: e,
      );
      if (mounted) {
        final localized = localizeError(l10n, e);
        _terminal.write('\x1B[?25h\x1B[31m$localized\x1B[0m\r\n');
        setState(() => _error = localized);
      }
    }
  }

  /// Wire this pane into the per-tab broadcast controller. Must run
  /// after [_openShell] so the shell sink is non-null. Idempotent —
  /// re-runs after a reconnect drop the previous registration first.
  void _attachBroadcast() {
    if (!widget.supportsBroadcast) return;
    final shellConn = _shellConn;
    if (shellConn == null) return;
    final controller = ref.read(broadcastControllerProvider(widget.tabId!));
    final paneId = widget.paneId!;
    _broadcast = controller;
    controller.registerSink(paneId, (bytes) {
      try {
        shellConn.write(bytes);
      } catch (_) {
        // Receiver shell torn down between dispatch and write — drop
        // the byte rather than fault the driver loop.
      }
    });
    // Wrap the existing onOutput hook so the driver path also fans out
    // to receivers. We capture the original hook installed by
    // ShellHelper so a future swap (e.g. local echo) keeps composing.
    final original = _terminal.onOutput;
    _terminal.onOutput = (data) {
      original?.call(data);
      if (controller.isDriver(paneId)) {
        controller.broadcastFrom(paneId, Uint8List.fromList(utf8.encode(data)));
      }
    };
    void onChange() {
      if (mounted) setState(() {});
    }

    controller.addListener(onChange);
    _broadcastUnsubscribe = () => controller.removeListener(onChange);
  }

  Future<ShellConnection> _openShell(Connection conn) async {
    void onDone() {
      if (mounted) {
        setState(() => _error = S.of(context).errSessionClosed);
      }
    }

    if (widget.shellFactory != null) {
      return widget.shellFactory!(
        connection: conn,
        terminal: _terminal,
        onDone: onDone,
      );
    }
    final recorder = await _maybeOpenRecorder(conn);
    return ShellHelper.openShell(
      connection: conn,
      terminal: _terminal,
      onDone: onDone,
      recorder: recorder,
    );
  }

  /// Open a recorder when the session has opted in via
  /// `Session.extras['record'] == true`. Returns null if recording
  /// is off, the session is unsaved (quick-connect), or the
  /// recorder failed to open — all three are equivalent from the
  /// shell's perspective: no tee, no file. Recorder failure is
  /// best-effort; a refusal here never blocks the connect.
  Future<SessionRecorder?> _maybeOpenRecorder(Connection conn) async {
    final sessionId = conn.sessionId;
    if (sessionId == null) return null;
    final store = ref.read(sessionStoreProvider);
    final session = await store.loadWithCredentials(sessionId);
    if (session == null) return null;
    if (session.extrasBool('record') != true) return null;
    final dbKey = ref.read(securityStateProvider).encryptionKey;
    return SessionRecorder.open(
      sessionId: sessionId,
      shellLabel: session.label,
      width: _terminal.viewWidth,
      height: _terminal.viewHeight,
      dbKey: dbKey,
    );
  }

  @override
  void didUpdateWidget(covariant TerminalPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFocused && !widget.isFocused) {
      _terminalController.clearSelection();
    }
  }

  @override
  void dispose() {
    TerminalScrubber.instance.unregister(_terminal);
    _progressSub?.cancel();
    HardwareKeyboard.instance.removeHandler(_onShiftToggle);
    _broadcastUnsubscribe?.call();
    if (widget.paneId != null) _broadcast?.unregisterSink(widget.paneId!);
    _shellConn?.close();
    _terminalController.dispose();
    _showSearch.dispose();
    super.dispose();
  }

  /// When the terminal app has enabled mouse mode (e.g. htop, vim), holding
  /// Shift bypasses mouse forwarding so the user can select text locally.
  /// Standard terminal-emulator behaviour (xterm, GNOME Terminal, etc.).
  bool _onShiftToggle(KeyEvent event) {
    final shouldSuspend =
        HardwareKeyboard.instance.isShiftPressed &&
        _terminal.mouseMode != MouseMode.none;
    if (_terminalController.suspendedPointerInputs != shouldSuspend) {
      _terminalController.setSuspendPointerInput(shouldSuspend);
    }
    return false; // never consume the key event
  }

  /// Toggle search bar visibility. Exposed for testing — in production
  /// triggered by Ctrl+Shift+F shortcut.
  @visibleForTesting
  void toggleSearch() {
    _showSearch.value = !_showSearch.value;
  }

  void _closeSearch() {
    _showSearch.value = false;
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = ref.watch(configProvider.select((c) => c.fontSize));

    // No border on panes — the 4px divider in TilingView separates them.
    //
    // Route onFocused through a raw Listener.onPointerDown rather than
    // GestureDetector.onTap: onTap only fires when the gesture arena
    // resolves as a clean tap, and any drift during the click (or the
    // xterm TerminalView's own pan/select gesture claiming the arena)
    // swallows the event, so the focused pane would stop switching
    // "every other click" when jumping between split panes.
    final paneId = widget.paneId;
    final tabId = widget.tabId;
    BroadcastController? broadcast;
    if (paneId != null && tabId != null) {
      broadcast = ref.watch(broadcastControllerProvider(tabId));
    }
    final isDriver = broadcast != null && paneId != null
        ? broadcast.isDriver(paneId)
        : false;
    final isReceiver = broadcast != null && paneId != null
        ? broadcast.isReceiver(paneId)
        : false;
    final borderColor = isDriver || isReceiver ? AppTheme.yellow : null;
    final borderWidth = isDriver ? 2.5 : 1.5;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.onFocused?.call(),
      child: Container(
        decoration: borderColor == null
            ? null
            : BoxDecoration(
                border: Border.all(color: borderColor, width: borderWidth),
              ),
        child: CallbackShortcuts(
          bindings: AppShortcutRegistry.instance.buildCallbackMap({
            AppShortcut.terminalSearch: toggleSearch,
            AppShortcut.terminalCloseSearch: _closeSearch,
          }),
          child: Column(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: _showSearch,
                builder: (context, show, _) {
                  if (!show) return const SizedBox.shrink();
                  return TerminalSearchBar(
                    terminal: _terminal,
                    terminalController: _terminalController,
                    onClose: _closeSearch,
                  );
                },
              ),
              // Snap the terminal widget's height to an integer number of
              // cells so xterm's viewport doesn't leave a dead strip at
              // the bottom — the same trick MobileTerminalView applies.
              // `kTerminalLineHeight` is the shared 1.2 multiplier xterm's
              // painter uses internally; mirroring it here gives us a
              // pre-layout estimate that matches the real measurement
              // closely enough that xterm settles on `rows * cellHeight`
              // rendered text with zero trailing gap. The remainder pixels
              // become a `ColoredBox` painted in the terminal background
              // so the boundary between the last row and the pane's next
              // widget (split divider / status) reads as a clean edge.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const verticalPadding = 8.0; // EdgeInsets.all(4).vertical
                    final cellHeight = fontSize * kTerminalLineHeight;
                    final usable = constraints.maxHeight - verticalPadding;
                    final rows = usable > 0 ? (usable / cellHeight).floor() : 0;
                    final snappedHeight = rows > 0
                        ? rows * cellHeight + verticalPadding
                        : constraints.maxHeight;
                    return Column(
                      children: [
                        SizedBox(
                          height: snappedHeight,
                          child: _buildTerminalStack(fontSize),
                        ),
                        if (snappedHeight < constraints.maxHeight)
                          Expanded(
                            child: ColoredBox(color: _terminalTheme.background),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Inner Listener + Stack(TerminalView, CursorTextOverlay). Extracted
  /// so the LayoutBuilder above can pin the terminal widget to an
  /// integer-row height via a `SizedBox` parent.
  Widget _buildTerminalStack(double fontSize) {
    return Listener(
      onPointerDown: (event) {
        if (event.buttons == kSecondaryButton) {
          _showContextMenu(context, event.position);
        }
      },
      onPointerSignal: _onPointerSignal,
      child: Stack(
        children: [
          TerminalView(
            _terminal,
            controller: _terminalController,
            autofocus: widget.isFocused,
            hardwareKeyboardOnly: plat.isDesktopPlatform,
            onKeyEvent: _handleTerminalKey,
            backgroundOpacity: 1.0,
            padding: const EdgeInsets.all(4),
            theme: _terminalTheme,
            textStyle: TerminalStyle(
              fontSize: fontSize,
              fontFamily: AppFonts.monoFamily,
              fontFamilyFallback: AppFonts.monoFallback,
            ),
          ),
          Positioned.fill(
            child: CursorTextOverlay(terminal: _terminal, fontSize: fontSize),
          ),
        ],
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final hasSelection = _terminalController.selection != null;
    final l10n = S.of(context);

    showAppContextMenu(
      context: context,
      position: position,
      items: [
        if (hasSelection)
          StandardMenuAction.copy.item(
            context,
            shortcut: AppShortcut.terminalCopy,
            onTap: _copySelection,
          ),
        StandardMenuAction.paste.item(
          context,
          shortcut: AppShortcut.terminalPaste,
          onTap: _pasteClipboard,
        ),
        StandardMenuAction.snippets.item(
          context,
          onTap: () => _showSnippetPicker(context),
        ),
        ..._buildBroadcastMenuItems(l10n),
      ],
    );
  }

  /// Broadcast actions are only meaningful when the pane is part of a
  /// multi-pane tab and we have ids to address it by — guard on both
  /// before adding any entry, otherwise the menu grows misleading
  /// "Broadcast from this pane" rows on solo panes / mobile.
  List<ContextMenuItem> _buildBroadcastMenuItems(S l10n) {
    if (!widget.supportsBroadcast || !widget.hasMultiplePanes) {
      return const [];
    }
    final controller = ref.read(broadcastControllerProvider(widget.tabId!));
    final paneId = widget.paneId!;
    final isDriver = controller.isDriver(paneId);
    final isReceiver = controller.isReceiver(paneId);

    return [
      const ContextMenuItem.divider(),
      ContextMenuItem(
        label: isDriver ? l10n.broadcastClearDriver : l10n.broadcastSetDriver,
        icon: isDriver ? Icons.podcasts : Icons.podcasts_outlined,
        color: isDriver ? AppTheme.yellow : null,
        onTap: () => controller.setDriver(isDriver ? null : paneId),
      ),
      if (!isDriver)
        ContextMenuItem(
          label: isReceiver
              ? l10n.broadcastRemoveReceiver
              : l10n.broadcastAddReceiver,
          icon: isReceiver ? Icons.input : Icons.input_outlined,
          color: isReceiver ? AppTheme.yellow : null,
          onTap: () => controller.toggleReceiver(paneId),
        ),
      if (controller.driverId != null || controller.receiverIds.isNotEmpty)
        ContextMenuItem(
          label: l10n.broadcastClearAll,
          icon: Icons.stop_circle_outlined,
          onTap: controller.clearAll,
        ),
    ];
  }

  /// Intercept keyboard shortcuts before xterm's built-in handler consumes
  /// them — xterm sends most key combos to the terminal as raw data, so
  /// ancestor CallbackShortcuts never see them.
  KeyEventResult _handleTerminalKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final reg = AppShortcutRegistry.instance;

    _shortcuts ??= <AppShortcut, VoidCallback>{
      AppShortcut.terminalCopy: _copySelection,
      AppShortcut.terminalPaste: _pasteClipboard,
      AppShortcut.zoomIn: _zoomIn,
      AppShortcut.zoomOut: _zoomOut,
      AppShortcut.zoomReset: _zoomReset,
    };

    for (final entry in _shortcuts!.entries) {
      if (reg.matches(entry.key, event)) {
        entry.value();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _copySelection() =>
      TerminalClipboard.copy(_terminal, _terminalController);

  Future<void> _pasteClipboard() async {
    final controller = widget.supportsBroadcast
        ? ref.read(broadcastControllerProvider(widget.tabId!))
        : null;
    final isDriver = controller != null && controller.isDriver(widget.paneId!);
    if (isDriver && controller.isActive) {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clip?.text;
      if (text == null || text.isEmpty) return;
      if (!mounted) return;
      final ok = await _confirmBroadcastPaste(text, controller);
      if (!ok) return;
      if (!mounted) return;
      // Same wire format as TerminalClipboard.paste — feed the bytes
      // directly so onOutput's broadcast wrapper fires and the receivers
      // see the same paste in lockstep.
      _terminal.paste(text);
      return;
    }
    return TerminalClipboard.paste(_terminal);
  }

  Future<bool> _confirmBroadcastPaste(
    String text,
    BroadcastController controller,
  ) async {
    final l10n = S.of(context);
    final receiverCount = controller.receiverIds
        .where((id) => id != widget.paneId)
        .length;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AppDialog(
        title: l10n.broadcastPasteTitle,
        maxWidth: 420,
        content: Text(
          l10n.broadcastPasteBody(text.length, receiverCount),
          style: TextStyle(
            color: AppTheme.fg,
            fontSize: AppFonts.sm,
            fontFamily: 'Inter',
          ),
        ),
        actions: [
          AppButton.cancel(onTap: () => Navigator.pop(context, false)),
          AppButton.primary(
            label: l10n.broadcastPasteSend,
            onTap: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _showSnippetPicker(BuildContext context) async {
    final cfg = widget.connection.sshConfig;
    final command = await SnippetPicker.show(
      context,
      sessionId: widget.connection.sessionId,
      templateContext: {
        'host': cfg.host,
        'user': cfg.user,
        'port': cfg.port.toString(),
        'label': widget.connection.label,
        'now': DateTime.now().toIso8601String(),
      },
    );
    if (command != null) {
      sendCommand(command);
    }
  }

  void _zoomIn() => _adjustFontSize(1);

  void _zoomOut() => _adjustFontSize(-1);

  void _zoomReset() {
    ref
        .read(configProvider.notifier)
        .update(
          (c) => c.copyWith(
            terminal: c.terminal.copyWith(
              fontSize: TerminalConfig.defaults.fontSize,
            ),
          ),
        );
  }

  void _adjustFontSize(double delta) {
    final current = ref.read(configProvider).fontSize;
    final updated = (current + delta).clamp(8.0, 24.0);
    if (updated == current) return;
    ref
        .read(configProvider.notifier)
        .update(
          (c) => c.copyWith(terminal: c.terminal.copyWith(fontSize: updated)),
        );
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent &&
        HardwareKeyboard.instance.isControlPressed) {
      _adjustFontSize(event.scrollDelta.dy < 0 ? 1 : -1);
    }
  }
}

/// Self-contained search bar widget — manages its own state so that
/// search interactions (typing, next/prev) don't rebuild the TerminalView.
class TerminalSearchBar extends StatefulWidget {
  final Terminal terminal;
  final TerminalController terminalController;
  final VoidCallback onClose;

  const TerminalSearchBar({
    super.key,
    required this.terminal,
    required this.terminalController,
    required this.onClose,
  });

  @override
  State<TerminalSearchBar> createState() => TerminalSearchBarState();
}

class TerminalSearchBarState extends State<TerminalSearchBar> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  List<TerminalHighlight> _searchHighlights = [];
  int _currentMatchIndex = -1;
  int _totalMatches = 0;
  bool _disposed = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _clearHighlights();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _debouncedSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _performSearch);
  }

  void _performSearch() {
    _clearHighlights();
    if (_disposed) return;
    final query = _searchController.text;
    if (query.isEmpty) {
      setState(() {
        _totalMatches = 0;
        _currentMatchIndex = -1;
      });
      return;
    }

    final buffer = widget.terminal.buffer;
    final highlights = <TerminalHighlight>[];
    const maxMatches = 1000;

    for (var y = 0; y < buffer.height && highlights.length < maxMatches; y++) {
      _highlightLineMatches(buffer, y, query, highlights, maxMatches);
    }

    setState(() {
      _searchHighlights = highlights;
      _totalMatches = highlights.length;
      _currentMatchIndex = highlights.isNotEmpty ? 0 : -1;
    });
  }

  void _highlightLineMatches(
    Buffer buffer,
    int y,
    String query,
    List<TerminalHighlight> highlights,
    int maxMatches,
  ) {
    final lineText = buffer.lines[y].toString().toLowerCase();
    final queryLower = query.toLowerCase();
    var startIndex = 0;
    while (startIndex < lineText.length && highlights.length < maxMatches) {
      final pos = lineText.indexOf(queryLower, startIndex);
      if (pos < 0) break;
      try {
        final p1 = buffer.createAnchor(pos, y);
        final p2 = buffer.createAnchor(pos + query.length, y);
        highlights.add(
          widget.terminalController.highlight(
            p1: p1,
            p2: p2,
            color: AppTheme.searchHighlight,
          ),
        );
      } catch (e) {
        AppLogger.instance.log(
          'Highlight failed at ($pos, $y): $e',
          name: 'TerminalSearch',
        );
      }
      startIndex = pos + 1;
    }
  }

  void _nextMatch() {
    if (_totalMatches == 0) return;
    setState(
      () => _currentMatchIndex = (_currentMatchIndex + 1) % _totalMatches,
    );
  }

  void _prevMatch() {
    if (_totalMatches == 0) return;
    setState(
      () => _currentMatchIndex =
          (_currentMatchIndex - 1 + _totalMatches) % _totalMatches,
    );
  }

  void _clearHighlights() {
    for (final h in _searchHighlights) {
      h.dispose();
    }
    _searchHighlights = [];
  }

  void _close() {
    _clearHighlights();
    widget.onClose();
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppTheme.barHeightSm,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: AppTheme.bg1,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              autofocus: true,
              style: AppFonts.mono(fontSize: AppFonts.sm, color: AppTheme.fg),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: AppTheme.bg3,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppTheme.radiusSm,
                  borderSide: BorderSide(color: AppTheme.borderLight),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppTheme.radiusSm,
                  borderSide: BorderSide(color: AppTheme.accent),
                ),
                hintText: S.of(context).search,
                hintStyle: AppFonts.mono(
                  fontSize: AppFonts.sm,
                  color: AppTheme.fgFaint,
                ),
                suffixText: _totalMatches > 0
                    ? '${_currentMatchIndex + 1}/$_totalMatches'
                    : null,
                suffixStyle: AppFonts.mono(
                  fontSize: AppFonts.sm,
                  color: AppTheme.fgDim,
                ),
              ),
              onChanged: (_) => _debouncedSearch(),
              onSubmitted: (_) => _nextMatch(),
            ),
          ),
          const SizedBox(width: 4),
          AppIconButton(
            icon: Icons.keyboard_arrow_up,
            onTap: _totalMatches > 0 ? _prevMatch : null,
            tooltip: S.of(context).previous,
          ),
          AppIconButton(
            icon: Icons.keyboard_arrow_down,
            onTap: _totalMatches > 0 ? _nextMatch : null,
            tooltip: S.of(context).next,
          ),
          AppIconButton(
            icon: Icons.close,
            onTap: _close,
            tooltip: S.of(context).closeEsc,
          ),
        ],
      ),
    );
  }
}
