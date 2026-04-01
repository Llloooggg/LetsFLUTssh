import 'package:flutter/material.dart';

/// Desktop layout shell shared by the main screen and settings.
///
/// Provides a consistent visual frame: decorated toolbar at the top,
/// optional resizable sidebar on the left, main body, and optional
/// status bar at the bottom.
///
/// When [useDrawer] is `true` the sidebar is rendered as a [Drawer]
/// instead of an inline panel (used for narrow viewports).
class AppShell extends StatefulWidget {
  /// Content placed inside the toolbar container.
  final Widget toolbar;

  /// Height of the toolbar container. Defaults to 34.
  final double toolbarHeight;

  /// Widget shown in the left sidebar panel.
  /// If `null`, no sidebar or drawer is rendered.
  final Widget? sidebar;

  /// Initial width of the sidebar in logical pixels.
  final double initialSidebarWidth;

  /// Minimum width the sidebar can be resized to.
  final double minSidebarWidth;

  /// Maximum width the sidebar can be resized to.
  final double maxSidebarWidth;

  /// Whether the sidebar is visible (inline mode only).
  final bool sidebarOpen;

  /// When `true`, [sidebar] is rendered as a [Drawer] instead of an
  /// inline panel. Sidebar open/close state is then controlled via
  /// `Scaffold.of(context).openDrawer()`.
  final bool useDrawer;

  /// Width of the drawer when [useDrawer] is `true`.
  final double drawerWidth;

  /// Main content area between the toolbar and the status bar.
  final Widget body;

  /// Optional bar at the very bottom.
  final Widget? statusBar;

  const AppShell({
    super.key,
    required this.toolbar,
    this.toolbarHeight = 34,
    this.sidebar,
    this.initialSidebarWidth = 220,
    this.minSidebarWidth = 140,
    this.maxSidebarWidth = 400,
    this.sidebarOpen = true,
    this.useDrawer = false,
    this.drawerWidth = 280,
    required this.body,
    this.statusBar,
  });

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  late double _sidebarWidth;

  @override
  void initState() {
    super.initState();
    _sidebarWidth = widget.initialSidebarWidth;
  }

  /// Current sidebar width — exposed so parents can read it if needed.
  double get sidebarWidth => _sidebarWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final toolbarContainer = Container(
      height: widget.toolbarHeight,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: widget.toolbar,
    );

    final column = Column(
      children: [
        toolbarContainer,
        Expanded(child: widget.body),
        if (widget.statusBar != null) widget.statusBar!,
      ],
    );

    // Drawer mode — sidebar as pull-out drawer.
    if (widget.useDrawer && widget.sidebar != null) {
      return Scaffold(
        drawer: Drawer(
          width: widget.drawerWidth,
          child: SafeArea(child: widget.sidebar!),
        ),
        body: column,
      );
    }

    // Inline sidebar mode.
    return Scaffold(
      body: Row(
        children: [
          if (widget.sidebarOpen && widget.sidebar != null) ...[
            SizedBox(width: _sidebarWidth, child: widget.sidebar),
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                onHorizontalDragUpdate: (d) {
                  setState(() {
                    _sidebarWidth = (_sidebarWidth + d.delta.dx)
                        .clamp(widget.minSidebarWidth, widget.maxSidebarWidth);
                  });
                },
                child: Container(
                  width: 3,
                  color: theme.dividerColor,
                ),
              ),
            ),
          ],
          Expanded(child: column),
        ],
      ),
    );
  }
}
