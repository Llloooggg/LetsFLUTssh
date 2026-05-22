import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/import_flow.dart';
import '../../core/config/app_config.dart';
import '../../core/import/import_service.dart';
import '../../core/progress/progress_reporter.dart';
import '../../core/import/key_file_helper.dart';
import '../../core/import/openssh_config_importer.dart';
import '../../core/import/ssh_dir_key_scanner.dart';
import 'security_tier_switcher.dart';
import '../../src/rust/api/app.dart' as rust_app;
import '../../src/rust/api/crypto.dart' as rust_crypto;
import '../../src/rust/api/fido2.dart' as rust_fido2;
import '../../src/rust/api/format.dart' as rust_format;
import '../../src/rust/api/logger.dart' as rust_logger;
import '../../src/rust/api/macos_resign.dart' as rust_macos_resign;
import '../../src/rust/api/recorder.dart' as rust_recorder;
import '../../src/rust/api/security_capabilities.dart'
    show DbKeyringProbeResult;
import '../../src/rust/api/ssh_agent.dart' as rust_ssh_agent;
import '../../src/rust/api/sync.dart' as rust_sync;
import '../../core/security/active_dbkey.dart';
import '../../core/security/biometric_auth.dart';
import '../../core/security/security_tier.dart';
import '../../core/security/wipe_all_service.dart';
import '../../core/session/qr_codec.dart';
import '../../src/rust/api/archive.dart' as rust_archive;
import '../../providers/auto_lock_provider.dart';
import '../../providers/config_provider.dart';
import '../../providers/connection_provider.dart';
import '../../providers/key_provider.dart';
import '../../core/logs/log_store.dart';
import '../../providers/log_store_provider.dart';
import '../../providers/master_password_provider.dart';
import '../../core/security/security_bootstrap.dart';
import '../../providers/security_provider.dart';
import '../../providers/security_reinit_provider.dart';
import '../../providers/session_credential_cache_provider.dart';
import '../../providers/snippet_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/tag_provider.dart';
import '../../core/update/update_service.dart';
import '../../providers/update_provider.dart';
import '../../providers/version_provider.dart';
import '../../utils/format.dart';
import '../../utils/logger.dart';
import 'qr_export_logic.dart';
import 'security_section_logic.dart';
import '../../providers/session_provider.dart';
import '../../utils/platform.dart' as plat;
import '../../utils/secret_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/core/app_bordered_box.dart';
import '../../widgets/core/app_popup_select.dart';
import '../../widgets/core/app_dialog.dart';
import '../../widgets/core/app_selection_area.dart';
import '../../widgets/core/sidebar_nav_dialog.dart';
import '../../widgets/terminal/readonly_terminal_view.dart';
import '../../widgets/core/app_icon_button.dart';
import '../../widgets/core/confirm_dialog.dart';
import '../../widgets/core/typed_name_confirm_dialog.dart';
import '../../widgets/core/form_submit_chain.dart';
import '../../widgets/core/hover_region.dart';
import '../../widgets/security/secure_password_field.dart';
import '../../widgets/security/secure_screen_scope.dart';
import '../../widgets/core/styled_form_field.dart';
import '../../widgets/security/expandable_tier_card.dart';
import '../../widgets/core/toast.dart';
import '../../widgets/terminal/update_progress_indicator.dart';
import '../../widgets/import_export/unified_export_dialog.dart';
import '../../widgets/import_export/lfs_import_preview_dialog.dart';
import '../../widgets/import_export/link_import_preview_dialog.dart';
import '../../widgets/import_export/paste_import_link_dialog.dart';
import '../../widgets/security/security_setup_dialog.dart';
import '../../widgets/import_export/ssh_dir_import_dialog.dart';
import '../session_manager/qr_display_screen.dart';

import '../../core/import/export_import.dart';

part 'settings_dialogs.dart';
part 'settings_logging.dart';
part 'settings_sections_data.dart';
part 'settings_sections_fido2_broker.dart';
part 'settings_sections_data_export_import.dart';
part 'settings_sections_preferences.dart';
part 'settings_sections_security.dart';
part 'settings_sections_security_apply.dart';
part 'settings_sections_security_biometric.dart';
part 'settings_sections_security_macos.dart';
part 'settings_sections_ssh_agent.dart';
part 'settings_sections_sync.dart';
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
/// Single source of truth for the settings section list. The mobile
/// collapsible-list and the desktop two-pane modal both read this —
/// every section appears on every platform with one ordering, one
/// icon set, one set of titles. SSH Keys / Snippets / Tags live in the
/// Tools dialog instead, so they are absent here.
List<SidebarNavEntry> _buildSections(BuildContext context) => [
  SidebarNavEntry(
    title: S.of(context).appearance,
    icon: Icons.palette,
    builder: _AppearanceSection.new,
  ),
  SidebarNavEntry(
    title: S.of(context).connectionSection,
    icon: Icons.lan,
    builder: _ConnectionSection.new,
  ),
  SidebarNavEntry(
    title: S.of(context).transfers,
    icon: Icons.swap_horiz,
    builder: _TransferSection.new,
  ),
  SidebarNavEntry(
    title: S.of(context).security,
    icon: Icons.security,
    builder: _SecuritySection.new,
  ),
  // Combined parent for the SSH-key plumbing toggles. The
  // agent-endpoint switch + the FIDO2 transport preference were two
  // separate top-level sections with one control each; merged into
  // a single section with sub-headers inside so the settings list
  // does not surface a collapsible-card-per-toggle.
  SidebarNavEntry(
    title: S.of(context).sshIntegrationSection,
    icon: Icons.vpn_key_outlined,
    builder: _SshIntegrationSection.new,
  ),
  SidebarNavEntry(
    title: S.of(context).data,
    icon: Icons.storage,
    builder: _DataSection.new,
  ),
  SidebarNavEntry(
    title: S.of(context).syncSection,
    icon: Icons.sync,
    builder: _SyncSection.new,
  ),
  SidebarNavEntry(
    title: S.of(context).logging,
    icon: Icons.description,
    builder: _LoggingSection.new,
  ),
  SidebarNavEntry(
    title: S.of(context).updates,
    icon: Icons.system_update,
    builder: _UpdateSection.new,
  ),
  SidebarNavEntry(
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
      // SingleChildScrollView + Column so every section is built
      // eagerly. The section count is under 10 — the lazy-sliver
      // default defers rows below the fold, which lets find-by-text
      // in tests miss widgets that are materialised only on scroll.
      // Eager-build keeps find + scroll-to-reveal symmetrical.
      //
      // `SelectionArea` wraps the body because this route is pushed
      // on the root Navigator, above the MainScreen-level
      // `SelectionArea` — so without an inner one the body's Text
      // widgets would lose drag-to-select. The log viewer no longer
      // nests its own `SelectionArea` (it renders to an xterm
      // `Terminal` which has independent selection), so there is no
      // `ContextMenuController` contention any more.
      body: AppSelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              for (final section in sections)
                _CollapsibleSection(
                  title: section.title,
                  icon: section.icon,
                  child: section.builder(),
                ),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: AppButton.secondary(
                  label: S.of(context).resetToDefaults,
                  icon: Icons.restore,
                  onTap: () => ref
                      .read(configProvider.notifier)
                      .update((_) => AppConfig.defaults),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
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
        childrenPadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
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
class SettingsDialog extends ConsumerWidget {
  const SettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => const SettingsDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return SidebarNavDialog(
      title: S.of(context).settings,
      entries: _buildSections(context),
      sidebarFooter: _ResetButton(
        onTap: () =>
            ref.read(configProvider.notifier).update((_) => AppConfig.defaults),
      ),
      // Each section scrolls in its own pane under the dense ListTile +
      // form text styles. Eager `ListView` children (not lazy slivers)
      // keep every row in the tree regardless of scroll position, so
      // find-by-text in tests never misses a row below the fold.
      panelBuilder: (panel) => ListTileTheme(
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
            padding: const EdgeInsets.all(24),
            cacheExtent: 10000,
            children: [panel],
          ),
        ),
      ),
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
              const SizedBox(width: AppSpacing.xxs),
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
