import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../key_manager/key_manager_dialog.dart';
import '../settings/known_hosts_manager.dart';
import '../snippets/snippet_manager_dialog.dart';
import '../tags/tag_manager_dialog.dart';

/// Mobile Tools screen — list of management tools (SSH Keys, Snippets,
/// Tags, Known Hosts). Each tile opens the corresponding manager dialog.
///
/// On desktop, the same entries are shown inside [ToolsDialog] with a
/// sidebar navigation.
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const ToolsScreen(),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tools)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.vpn_key),
            title: Text(l10n.sshKeys),
            subtitle: Text(l10n.sshKeysSubtitle),
            onTap: () => KeyManagerDialog.show(context),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(l10n.snippets),
            subtitle: Text(l10n.snippetsSubtitle),
            onTap: () => SnippetManagerDialog.show(context),
          ),
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: Text(l10n.tags),
            subtitle: Text(l10n.tagsSubtitle),
            onTap: () => TagManagerDialog.show(context),
          ),
          ListTile(
            leading: const Icon(Icons.verified_user),
            title: Text(l10n.knownHosts),
            subtitle: Text(l10n.knownHostsSubtitle),
            onTap: () => KnownHostsManagerDialog.show(context),
          ),
        ],
      ),
    );
  }
}
