import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/secure_clipboard.dart';
import '../../core/snippets/snippet.dart';
import 'snippets_logic.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/snippet_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/core/app_collection_panel.dart';
import '../../widgets/core/app_data_row.dart';
import '../../widgets/core/app_dialog.dart';
import '../../widgets/core/app_icon_button.dart';
import '../../widgets/core/hover_region.dart';
import '../../widgets/core/toast.dart';

/// Embeddable snippet manager — toolbar + list with CRUD over
/// [CollectionManagerPanel].
///
/// Used standalone inside [SnippetManagerDialog] (mobile) and embedded in
/// the desktop Tools dialog.
class SnippetManagerPanel extends StatelessWidget {
  const SnippetManagerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return CollectionManagerPanel<Snippet>(
      load: (ref) => ref.read(snippetsProvider.notifier).loadAll(),
      filter: filterSnippets,
      countLabel: s.snippetCount,
      emptyMessage: s.noSnippets,
      noResultsMessage: s.noResults,
      toolbarActions: (context, ref, reload) => [
        AppButton.secondary(
          label: s.addSnippet,
          icon: Icons.add,
          dense: true,
          onTap: () => _addSnippet(context, ref, reload),
        ),
      ],
      itemBuilder: _buildEntry,
    );
  }

  Widget _buildEntry(
    BuildContext context,
    WidgetRef ref,
    Snippet snippet,
    Future<void> Function() reload,
  ) {
    final s = S.of(context);
    return AppDataRow(
      icon: Icons.code,
      title: snippet.title,
      secondary: snippet.command,
      secondaryMono: true,
      tertiary: snippet.description.isEmpty ? null : snippet.description,
      trailing: [
        AppIconButton(
          icon: Icons.content_copy,
          tooltip: s.copy,
          dense: true,
          onTap: () => _copyCommand(context, snippet),
        ),
        AppIconButton(
          icon: Icons.edit_outlined,
          tooltip: s.editSnippet,
          dense: true,
          onTap: () => _editSnippet(context, ref, snippet, reload),
        ),
        AppIconButton(
          icon: Icons.delete_outline,
          tooltip: s.deleteSnippet,
          dense: true,
          color: AppTheme.red,
          onTap: () => _deleteSnippet(context, ref, snippet, reload),
        ),
      ],
    );
  }

  Future<void> _copyCommand(BuildContext context, Snippet snippet) async {
    // Snippets can carry credentials; SecureClipboard pins the
    // per-platform "no-cloud" flag so bytes don't reach Windows
    // clipboard history, macOS Universal Clipboard, iOS Handoff
    // or Android 13+ history. Refuse on Rust-side failure rather
    // than fall back to Flutter's stock channel.
    bool ok;
    try {
      ok = await SecureClipboard().setText(snippet.command);
    } catch (_) {
      // Native channel / FRB unreachable (flutter_test, missing
      // plugin) — surface the same failure-toast path the
      // refused-cloud-leak case uses so the user gets a clear
      // signal rather than a silent no-op.
      ok = false;
    }
    if (!context.mounted) return;
    Toast.show(
      context,
      message: ok
          ? S.of(context).commandCopied
          : S.of(context).clipboardCopyFailed,
      level: ok ? ToastLevel.info : ToastLevel.error,
    );
  }

  Future<void> _addSnippet(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() reload,
  ) async {
    final result = await _SnippetEditDialog.show(context);
    if (result == null || !context.mounted) return;
    await ref.read(snippetsProvider.notifier).add(result);
    await reload();
    if (context.mounted) {
      Toast.show(
        context,
        message: S.of(context).snippetSaved,
        level: ToastLevel.success,
      );
    }
  }

  Future<void> _editSnippet(
    BuildContext context,
    WidgetRef ref,
    Snippet snippet,
    Future<void> Function() reload,
  ) async {
    final result = await _SnippetEditDialog.show(context, snippet: snippet);
    if (result == null || !context.mounted) return;
    await ref.read(snippetsProvider.notifier).save(result);
    await reload();
    if (context.mounted) {
      Toast.show(
        context,
        message: S.of(context).snippetSaved,
        level: ToastLevel.success,
      );
    }
  }

  Future<void> _deleteSnippet(
    BuildContext context,
    WidgetRef ref,
    Snippet snippet,
    Future<void> Function() reload,
  ) async {
    final s = S.of(context);
    final confirmed = await AppDialog.show<bool>(
      context,
      builder: (ctx) => AppDialog(
        title: s.deleteSnippet,
        content: Text(s.deleteSnippetConfirm(snippet.title)),
        actions: [
          AppButton.cancel(onTap: () => Navigator.pop(ctx, false)),
          AppButton.destructive(
            label: s.delete,
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(snippetsProvider.notifier).delete(snippet.id);
    // SessionSnippets cascades on FK; `dbSnippetsDelete` Rust-side
    // publishes `SessionsChanged` so the workspace stream re-fetches
    // and the derived UI drops the dead snippet link.
    await reload();
    if (context.mounted) {
      Toast.show(context, message: s.snippetDeleted(snippet.title));
    }
  }
}

/// Dialog wrapper for standalone use (mobile settings).
class SnippetManagerDialog extends StatelessWidget {
  const SnippetManagerDialog({super.key});

  static Future<void> show(BuildContext context) {
    return AppDialog.show(
      context,
      builder: (_) => const SnippetManagerDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: S.of(context).snippets,
      maxWidth: 640,
      scrollable: false,
      contentPadding: EdgeInsets.zero,
      content: const SizedBox(height: 400, child: SnippetManagerPanel()),
      actions: [AppButton.cancel(onTap: () => Navigator.pop(context))],
    );
  }
}

// ── Add / Edit Snippet Dialog ──────────────────────────────────────

class _SnippetEditDialog extends StatefulWidget {
  final Snippet? snippet;

  const _SnippetEditDialog({this.snippet});

  static Future<Snippet?> show(BuildContext context, {Snippet? snippet}) {
    return AppDialog.show<Snippet>(
      context,
      builder: (_) => _SnippetEditDialog(snippet: snippet),
    );
  }

  @override
  State<_SnippetEditDialog> createState() => _SnippetEditDialogState();
}

class _SnippetEditDialogState extends State<_SnippetEditDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _commandCtrl;
  late final TextEditingController _descCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.snippet?.title ?? '');
    _commandCtrl = TextEditingController(text: widget.snippet?.command ?? '');
    _descCtrl = TextEditingController(text: widget.snippet?.description ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _commandCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isEdit = widget.snippet != null;
    return AppDialog(
      title: isEdit ? s.editSnippet : s.addSnippet,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titleCtrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: s.snippetTitle,
              hintText: s.snippetTitleHint,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _commandCtrl,
            maxLines: 3,
            style: AppFonts.mono(fontSize: AppFonts.sm, color: AppTheme.fg),
            decoration: InputDecoration(
              labelText: s.snippetCommand,
              hintText: s.snippetCommandHint,
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Inline hint listing the built-in placeholder tokens —
          // without it users have no way to discover that
          // {{host}} / {{user}} / {{port}} / {{label}} / {{now}}
          // (plus arbitrary user-named tokens) get substituted at
          // execution time. Tap a chip to insert the token at the
          // current caret position.
          _SnippetTokenHints(controller: _commandCtrl),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _descCtrl,
            decoration: InputDecoration(
              labelText: s.snippetDescription,
              hintText: s.snippetDescriptionHint,
            ),
          ),
        ],
      ),
      actions: [
        AppButton.cancel(onTap: () => Navigator.pop(context)),
        AppButton.primary(label: s.save, onTap: _save),
      ],
    );
  }

  void _save() {
    final title = _titleCtrl.text.trim();
    final command = _commandCtrl.text.trim();
    if (title.isEmpty || command.isEmpty) return;

    final snippet = widget.snippet != null
        ? widget.snippet!.copyWith(
            title: title,
            command: command,
            description: _descCtrl.text.trim(),
          )
        : Snippet(
            title: title,
            command: command,
            description: _descCtrl.text.trim(),
          );
    Navigator.pop(context, snippet);
  }
}

/// Inline hint surfaced under the command field — chips that
/// document the built-in `{{name}}` tokens and insert them into the
/// command field on tap. Without this hint users had no way to
/// discover that snippets support template substitution at all.
class _SnippetTokenHints extends StatelessWidget {
  final TextEditingController controller;
  const _SnippetTokenHints({required this.controller});

  /// Built-in tokens — kept in sync with `core/snippets/snippet_template.dart`.
  /// Custom user tokens (`{{my-name}}`) work too — those prompt at
  /// run time. The chip row here only documents the always-resolved
  /// set; the runtime help text below adds the prompt-on-execute
  /// note for everything else.
  static const _tokens = ['host', 'user', 'port', 'label', 'now'];

  void _insert(String token) {
    final inject = '{{$token}}';
    final selection = controller.selection;
    if (selection.isValid) {
      final text = controller.text;
      final start = selection.start;
      final end = selection.end;
      final next = text.replaceRange(start, end, inject);
      controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: start + inject.length),
      );
    } else {
      controller.text = '${controller.text}$inject';
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.snippetTokensHint,
          style: TextStyle(
            color: AppTheme.fgFaint,
            fontSize: AppFonts.xs,
            fontFamily: AppFonts.interFamily,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in _tokens)
              // SelectionContainer.disabled — the chip is a button,
              // its label must not behave like body text inside the
              // surrounding SelectionArea (drag-to-copy on a button
              // is the wrong affordance and reads as "this is text"
              // not "this is tappable").
              SelectionContainer.disabled(
                child: HoverRegion(
                  onTap: () => _insert(t),
                  builder: (hovered) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: hovered ? AppTheme.hover : AppTheme.bg3,
                      borderRadius: AppTheme.radiusSm,
                      border: Border.all(color: AppTheme.borderLight),
                    ),
                    child: Text(
                      '{{$t}}',
                      style: AppFonts.mono(
                        fontSize: AppFonts.xs,
                        color: AppTheme.accent,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          s.snippetCustomTokensHint,
          style: TextStyle(
            color: AppTheme.fgFaint,
            fontSize: AppFonts.xs,
            fontFamily: AppFonts.interFamily,
          ),
        ),
      ],
    );
  }
}
