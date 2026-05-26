import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/core/sidebar_nav_dialog.dart';
import '../key_manager/key_manager_dialog.dart';
import '../recordings/recordings_browser.dart';
import '../settings/known_hosts_manager.dart';
import '../snippets/snippet_manager_dialog.dart';
import '../tags/tag_manager_dialog.dart';

/// Full-screen Tools dialog (VS Code style) — SSH Keys, Snippets, Tags,
/// Known Hosts, Recordings.
///
/// Desktop only. Mobile uses [ToolsScreen] with inline tiles. The dialog
/// chrome and the lazy keep-alive content pane live in [SidebarNavDialog].
class ToolsDialog extends StatelessWidget {
  const ToolsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => const ToolsDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SidebarNavDialog(
      title: S.of(context).tools,
      entries: [
        SidebarNavEntry(
          icon: Icons.vpn_key,
          title: S.of(context).sshKeys,
          builder: KeyManagerPanel.new,
        ),
        SidebarNavEntry(
          icon: Icons.code,
          title: S.of(context).snippets,
          builder: SnippetManagerPanel.new,
        ),
        SidebarNavEntry(
          icon: Icons.label_outline,
          title: S.of(context).tags,
          builder: TagManagerPanel.new,
        ),
        SidebarNavEntry(
          icon: Icons.verified_user,
          title: S.of(context).knownHosts,
          builder: KnownHostsManagerPanel.new,
        ),
        SidebarNavEntry(
          icon: Icons.play_circle_outline,
          title: S.of(context).recordingsBrowserTitle,
          builder: RecordingsPanel.new,
        ),
      ],
    );
  }
}
