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
import '../../core/progress/progress_reporter.dart';
import '../../core/import/key_file_helper.dart';
import '../../core/import/openssh_config_importer.dart';
import '../../core/import/ssh_dir_key_scanner.dart';
import '../../core/db/database_opener.dart';
import 'security_tier_switcher.dart';
import '../../core/shortcut_registry.dart';
import '../../core/security/aes_gcm.dart';
import '../../core/security/biometric_auth.dart';
import '../../core/security/master_password.dart';
import '../../core/security/security_tier.dart';
import '../../core/session/qr_codec.dart';
import '../../core/session/session.dart';
import '../../providers/auto_lock_provider.dart';
import '../../providers/config_provider.dart';
import '../../providers/connection_provider.dart';
import '../../core/security/key_store.dart';
import '../../core/snippets/snippet.dart';
import '../../core/snippets/snippet_store.dart';
import '../../core/tags/tag.dart';
import '../../core/tags/tag_store.dart';
import '../../providers/key_provider.dart';
import '../../providers/master_password_provider.dart';
import '../../providers/security_provider.dart';
import '../../providers/snippet_provider.dart';
import '../../providers/tag_provider.dart';
import '../../core/update/update_service.dart';
import '../../providers/update_provider.dart';
import '../../providers/version_provider.dart';
import '../../utils/android_storage_permission.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
import '../../providers/session_provider.dart';
import '../../utils/platform.dart' as plat;
import '../../utils/secret_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bordered_box.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icon_button.dart';
import '../../widgets/form_submit_chain.dart';
import '../../widgets/hover_region.dart';
import '../../widgets/toast.dart';
import '../../widgets/unified_export_dialog.dart';
import '../../widgets/lfs_import_preview_dialog.dart';
import '../../widgets/link_import_preview_dialog.dart';
import '../../widgets/local_directory_picker.dart';
import '../../widgets/password_strength_meter.dart';
import '../../widgets/paste_import_link_dialog.dart';
import '../../widgets/ssh_dir_import_dialog.dart';
import '../session_manager/qr_display_screen.dart';
import 'export_import.dart';

part 'settings_dialogs.dart';
part 'settings_logging.dart';
part 'settings_sections_data.dart';
part 'settings_sections_preferences.dart';
part 'settings_sections_security.dart';
part 'settings_sections_updates.dart';
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

/// Ordered list of all settings sections (mobile — includes SSH Keys/tools).
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
    title: S.of(context).security,
    icon: Icons.security,
    builder: _SecuritySection.new,
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

/// Desktop sections — excludes SSH Keys/Snippets/Tags (moved to Tools dialog).
List<_Section> _buildDesktopSections(BuildContext context) => [
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
    title: S.of(context).security,
    icon: Icons.security,
    builder: _SecuritySection.new,
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
/// On desktop, settings are shown via [SettingsDialog] (full-screen modal).
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

/// Full-screen Settings dialog (VS Code style) — desktop only.
///
/// Shows all settings sections except SSH Keys/Snippets/Tags (those
/// are in the Tools dialog). Sidebar nav on the left, content on the right.
class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => const SettingsDialog(),
    );
  }

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final sections = _buildDesktopSections(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Keep Settings, Tools, and every other full-screen desktop modal
    // at the same symmetric inset so they feel like siblings — the
    // fraction and floor are owned by AppTheme.desktopModalInsetPadding.
    final viewportWidth = MediaQuery.sizeOf(context).width;

    return Dialog(
      insetPadding: AppTheme.desktopModalInsetPadding(viewportWidth),
      backgroundColor: AppTheme.bg1,
      child: CallbackShortcuts(
        bindings: AppShortcutRegistry.instance.buildCallbackMap({
          AppShortcut.dismissDialog: () => Navigator.of(context).pop(),
        }),
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              AppDialogHeader(
                title: S.of(context).settings,
                onClose: () => Navigator.pop(context),
              ),
              Expanded(
                child: Row(
                  children: [
                    // Sidebar
                    SizedBox(
                      width: 200,
                      child: Container(
                        color: scheme.surfaceContainerLow,
                        child: Column(
                          children: [
                            Expanded(
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                itemCount: sections.length,
                                itemBuilder: (context, index) {
                                  final section = sections[index];
                                  return _NavItem(
                                    icon: section.icon,
                                    label: section.title,
                                    selected: index == _selectedIndex,
                                    onTap: () =>
                                        setState(() => _selectedIndex = index),
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
                      ),
                    ),
                    VerticalDivider(width: 1, color: theme.dividerColor),
                    // Content
                    Expanded(
                      child: ListTileTheme(
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
                          style: AppFonts.inter(
                            fontSize: AppFonts.sm,
                            color: scheme.onSurface,
                          ),
                          child: ListView(
                            key: ValueKey(_selectedIndex),
                            padding: const EdgeInsets.all(24),
                            children: [
                              _SectionHeader(
                                title: sections[_selectedIndex].title,
                              ),
                              sections[_selectedIndex].builder(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
