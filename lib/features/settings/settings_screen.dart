import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/config/app_config.dart';
import '../../core/import/import_service.dart';
import '../../core/session/qr_codec.dart';
import '../../providers/config_provider.dart';
import '../../providers/update_provider.dart';
import '../../providers/version_provider.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
import '../../providers/session_provider.dart';
import '../../utils/platform.dart' as plat;
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bordered_box.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/hover_region.dart';
import '../../widgets/mode_button.dart';
import '../../widgets/toast.dart';
import '../session_manager/qr_display_screen.dart';
import '../session_manager/qr_export_dialog.dart';
import 'export_import.dart';

part 'settings_dialogs.dart';
part 'settings_logging.dart';
part 'settings_sections.dart';
part 'settings_widgets.dart';

const _githubUrl = 'https://github.com/Llloooggg/LetsFLUTssh';

/// Returns a sensible initial directory for file-picker dialogs.
/// Desktop: Downloads folder; mobile: shared external storage root.
Future<String?> _defaultDirectory() async {
  if (plat.isDesktopPlatform) {
    try {
      final dir = await getDownloadsDirectory();
      if (dir != null) return dir.path;
    } catch (_) {
      // fall through
    }
  }
  final home = plat.homeDirectory;
  return home.isNotEmpty ? home : null;
}

/// Section descriptor for navigation and content rendering.
class _Section {
  final String title;
  final IconData icon;
  final Widget Function() builder;

  const _Section({
    required this.title,
    required this.icon,
    required this.builder,
  });
}

/// Ordered list of all settings sections.
List<_Section> _buildSections(BuildContext context) => [
  _Section(
    title: S.of(context).appearance,
    icon: Icons.palette,
    builder: _AppearanceSection.new,
  ),
  _Section(
    title: S.of(context).terminal,
    icon: Icons.terminal,
    builder: _TerminalSection.new,
  ),
  _Section(
    title: S.of(context).connectionSection,
    icon: Icons.lan,
    builder: _ConnectionSection.new,
  ),
  _Section(
    title: S.of(context).transfers,
    icon: Icons.swap_horiz,
    builder: _TransferSection.new,
  ),
  _Section(
    title: S.of(context).data,
    icon: Icons.storage,
    builder: _DataSection.new,
  ),
  _Section(
    title: S.of(context).logging,
    icon: Icons.description,
    builder: _LoggingSection.new,
  ),
  _Section(
    title: S.of(context).updates,
    icon: Icons.system_update,
    builder: _UpdateSection.new,
  ),
  _Section(
    title: S.of(context).about,
    icon: Icons.info_outline,
    builder: _AboutSection.new,
  ),
];

/// Settings screen with config editing.
///
/// Desktop: two-column layout (nav rail + content pane).
/// Mobile: flat scrollable list (unchanged).
///
/// Each section watches only its own config fields via `select()` to avoid
/// unnecessary rebuilds when unrelated settings change.
/// Settings screen — mobile only (pushed as a route).
///
/// On desktop, settings are embedded directly in [AppShell] via
/// [SettingsSidebar] and [SettingsContent] — no route navigation needed.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  /// Push the mobile settings screen.
  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const SettingsScreen(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const _MobileSettingsScreen();
  }
}

/// Mobile: collapsible sections in a scrollable list.
class _MobileSettingsScreen extends ConsumerWidget {
  const _MobileSettingsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = _buildSections(context);
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).settings)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final section in sections)
            _CollapsibleSection(
              title: section.title,
              icon: section.icon,
              child: section.builder(),
            ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: () => ref
                  .read(configProvider.notifier)
                  .update((_) => AppConfig.defaults),
              icon: const Icon(Icons.restore, size: 18),
              label: Text(S.of(context).resetToDefaults),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// When true (test-only), all [_CollapsibleSection] widgets start expanded.
/// Set this in test setUp / tearDown using the same pattern as
/// [plat.debugMobilePlatformOverride].
@visibleForTesting
bool debugCollapsibleSectionsExpanded = false;

/// Collapsible settings section used on mobile.
class _CollapsibleSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _CollapsibleSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  late bool _expanded = debugCollapsibleSectionsExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppTheme.radiusLg,
        side: BorderSide(color: theme.dividerColor),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(widget.icon, size: 20),
        title: Text(
          widget.title,
          style: TextStyle(fontSize: AppFonts.lg, fontWeight: FontWeight.w500),
        ),
        initiallyExpanded: _expanded,
        onExpansionChanged: (v) => setState(() => _expanded = v),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [widget.child],
      ),
    );
  }
}

/// Desktop settings sidebar — nav items + reset button.
///
/// Designed to be embedded in [AppShell]'s sidebar slot so it shares
/// the same resizable panel and visual frame as the sessions sidebar.
class SettingsSidebar extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const SettingsSidebar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = _buildSections(context);
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          // Header — matches SessionPanel _PanelHeader style
          Container(
            height: AppTheme.barHeightSm,
            padding: const EdgeInsets.only(left: 12, right: 2),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    S.of(context).settings.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: AppFonts.sm,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.45,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: sections.length,
              itemBuilder: (context, index) {
                final section = sections[index];
                return _NavItem(
                  icon: section.icon,
                  label: section.title,
                  selected: index == selectedIndex,
                  onTap: () => onSelect(index),
                );
              },
            ),
          ),
          _ResetButton(
            onTap: () => ref
                .read(configProvider.notifier)
                .update((_) => AppConfig.defaults),
          ),
        ],
      ),
    );
  }
}

/// Desktop settings content pane — shows the selected section.
///
/// Designed to be embedded in [AppShell]'s body slot.
class SettingsContent extends StatelessWidget {
  final int selectedIndex;

  const SettingsContent({super.key, required this.selectedIndex});

  @override
  Widget build(BuildContext context) {
    final sections = _buildSections(context);
    final scheme = Theme.of(context).colorScheme;
    return ListTileTheme(
      data: ListTileThemeData(
        dense: true,
        contentPadding: EdgeInsets.zero,
        titleTextStyle: AppFonts.inter(
          fontSize: AppFonts.sm,
          color: scheme.onSurface,
        ),
        subtitleTextStyle: AppFonts.inter(
          fontSize: AppFonts.xs,
          color: scheme.onSurfaceVariant,
        ),
        leadingAndTrailingTextStyle: AppFonts.inter(
          fontSize: AppFonts.xs,
          color: scheme.onSurface.withValues(alpha: 0.45),
        ),
      ),
      child: DefaultTextStyle(
        style: AppFonts.inter(fontSize: AppFonts.sm, color: scheme.onSurface),
        child: ListView(
          key: ValueKey(selectedIndex),
          padding: const EdgeInsets.all(24),
          children: [
            _SectionHeader(title: sections[selectedIndex].title),
            sections[selectedIndex].builder(),
          ],
        ),
      ),
    );
  }
}

/// A single item in the desktop navigation rail.
class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HoverRegion(
      onTap: widget.onTap,
      builder: (hovered) {
        final Color bg;
        if (widget.selected) {
          bg = theme.colorScheme.primary.withValues(alpha: 0.15);
        } else if (hovered) {
          bg = AppTheme.hover;
        } else {
          bg = Colors.transparent;
        }
        return Container(
          height: AppTheme.controlHeightMd,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: bg,
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 13,
                color: widget.selected ? AppTheme.fg : AppTheme.fgDim,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.inter(
                    fontSize: AppFonts.sm,
                    color: widget.selected ? AppTheme.fg : AppTheme.fgDim,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Reset to Defaults button at bottom of nav.
class _ResetButton extends StatefulWidget {
  final VoidCallback onTap;
  const _ResetButton({required this.onTap});

  @override
  State<_ResetButton> createState() => _ResetButtonState();
}

class _ResetButtonState extends State<_ResetButton> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: HoverRegion(
        onTap: widget.onTap,
        builder: (hovered) => Container(
          height: AppTheme.controlHeightSm,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: hovered ? AppTheme.hover : Colors.transparent,
          child: Row(
            children: [
              Icon(Icons.restore, size: 12, color: AppTheme.red),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  S.of(context).resetToDefaults,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.inter(
                    fontSize: AppFonts.xs,
                    color: AppTheme.red,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
