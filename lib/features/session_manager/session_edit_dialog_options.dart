part of 'session_edit_dialog.dart';

/// Advanced-section helpers for the single-form dialog. The
/// Advanced block is collapsed by default and holds the secondary
/// knobs the user rarely needs on a first save: tags (universal),
/// port-forward rules (SSH only — open via the [SessionForwardsDialog]
/// modal), and the record-session toggle (SSH only — WebDAV / S3
/// never open a shell to record).
///
/// Lives as an extension on the dialog state so the helpers reach
/// `widget.session`, `_recordEnabled`, `_forwards`, and
/// `_advancedExpanded` directly without going through a public
/// surface; `part of` joins the file into the same library so
/// library-private names stay reachable.
extension _AdvancedSection on _SessionEditDialogState {
  /// Composes the contents of the Advanced section. Wrapped by the
  /// expander in the main `build()`; this method only builds the
  /// body rows, the expand/collapse chrome lives outside.
  Widget _buildAdvancedBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTagsSection(),
        if (_kind == SessionKind.ssh) ...[
          const SizedBox(height: AppSpacing.lg),
          _buildForwardingRow(),
          const SizedBox(height: AppSpacing.lg),
          _buildRecordSection(),
        ],
      ],
    );
  }

  /// Compact row that opens the port-forward rule editor as a
  /// modal sub-dialog. Shows a pluralised summary
  /// ("3 port-forward rules") on the left and a Manage… button on
  /// the right; the actual rule editor sits inside
  /// [SessionForwardsDialog]. Persistence stays deferred — edits
  /// roundtrip through `_forwards` until the parent Save fires.
  Widget _buildForwardingRow() {
    final l10n = S.of(context);
    return _OptionRow(
      label: l10n.forwardRulesSummary(_forwards.length),
      trailing: AppButton.secondary(
        label: l10n.manageRules,
        icon: Icons.swap_horiz,
        dense: true,
        onTap: () async {
          final result = await SessionForwardsDialog.show(
            context,
            initial: _forwards,
          );
          if (result != null && mounted) {
            rebuild(() => _forwards = result);
          }
        },
      ),
    );
  }

  /// Per-session recording toggle. Persisted into `Session.extras`
  /// (via [Session.withExtras]) when the user saves; the runtime
  /// reads `extras['record']` at shell-open time. Off by default to
  /// match the privacy-first positioning — recording is opt-in.
  Widget _buildRecordSection() {
    final l10n = S.of(context);
    final current = _recordEnabled;
    return _OptionRow(
      label: l10n.recordSession,
      trailing: Switch(
        value: current,
        onChanged: (v) => rebuild(() => _recordEnabled = v),
      ),
      detail: Text(
        l10n.recordSessionHelp,
        style: TextStyle(
          fontFamily: AppFonts.interFamily,
          fontSize: AppFonts.xs,
          color: AppTheme.fgFaint,
        ),
      ),
    );
  }

  /// Tags option row — label on the left, action on the right,
  /// assigned chips on their own row below. Keeps the form's label +
  /// control rhythm predictable so new option rows (dropdowns,
  /// toggles) can be appended without the Options tab looking like a
  /// list of centred orphan buttons.
  Widget _buildTagsSection() {
    final s = S.of(context);
    return _OptionRow(
      label: s.tags,
      trailing: _isEditing
          ? _ManageTagsButton(sessionId: widget.session!.id)
          : null,
      detail: _isEditing
          ? _EditingSessionTagsChips(sessionId: widget.session!.id)
          : Text(
              s.saveSessionToAssignTags,
              style: TextStyle(
                fontFamily: AppFonts.interFamily,
                fontSize: AppFonts.xs,
                color: AppTheme.fgFaint,
              ),
            ),
    );
  }
}

/// Form row for the Options tab. Label on the left, a trailing action
/// widget on the right (typically a compact button), and an optional
/// [detail] block rendered full-width below the label/action line.
/// Adding a second option row (e.g. a dropdown) is a one-line drop-in
/// that preserves the column alignment instead of stacking orphan
/// buttons against the left edge.
class _OptionRow extends StatelessWidget {
  final String label;
  final Widget? trailing;
  final Widget? detail;

  const _OptionRow({required this.label, this.trailing, this.detail});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppFonts.interFamily,
                    fontSize: AppFonts.sm,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.fg,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          if (detail != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(alignment: Alignment.centerLeft, child: detail!),
          ],
        ],
      ),
    );
  }
}

/// Compact "Manage tags" button for the trailing slot of
/// [_OptionRow]. Intrinsic width so it doesn't stretch to fill the
/// row and look centred against whitespace.
class _ManageTagsButton extends ConsumerWidget {
  final String sessionId;

  const _ManageTagsButton({required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    return AppButton.secondary(
      label: s.manageTags,
      icon: Icons.label_outline,
      dense: true,
      onTap: () async {
        await TagAssignDialog.showForSession(context, sessionId: sessionId);
        // The dialog applies changes directly; invalidate to refresh.
        ref.invalidate(sessionTagsProvider(sessionId));
      },
    );
  }
}

/// Chips-only render of the session's assigned tags — the trailing
/// "Manage" control lives in the [_OptionRow] header so the chips
/// take the full detail width without a competing button below them.
class _EditingSessionTagsChips extends ConsumerWidget {
  final String sessionId;

  const _EditingSessionTagsChips({required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final tagsAsync = ref.watch(sessionTagsProvider(sessionId));
    return tagsAsync.when(
      loading: () => const SizedBox(
        height: 16,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (tags) {
        if (tags.isEmpty) {
          return Text(
            s.noTagsAssigned,
            style: TextStyle(
              fontFamily: AppFonts.interFamily,
              fontSize: AppFonts.xs,
              color: AppTheme.fgFaint,
            ),
          );
        }
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final tag in tags) _tagChip(tag)],
        );
      },
    );
  }

  Widget _tagChip(Tag tag) {
    final color = tag.colorValue ?? AppTheme.fgDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: AppTheme.radiusSm,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            tag.name,
            style: TextStyle(fontSize: AppFonts.xs, color: AppTheme.fg),
          ),
        ],
      ),
    );
  }
}
