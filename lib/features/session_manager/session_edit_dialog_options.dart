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
  /// Composes the contents of the More options section. Wrapped by
  /// the expander in the main `build()`; this method only builds the
  /// body rows, the expand/collapse chrome lives outside. The SSH
  /// branch carries ProxyJump (rarely used — a bastion hop is the
  /// exception, not the default), the per-rule port-forwarding
  /// editor, and the record-session toggle. WebDAV / S3 add the
  /// trusted-cert PEM textarea + "accept any certificate" toggle
  /// here so the credential block above stays focused on the
  /// username/password tuple.
  Widget _buildAdvancedBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTagsSection(),
        if (_kind == SessionKind.ssh) ...[
          const SizedBox(height: AppSpacing.lg),
          _buildProxyJumpSection(),
          const SizedBox(height: AppSpacing.lg),
          _buildForwardingRow(),
          const SizedBox(height: AppSpacing.lg),
          _buildRecordSection(),
        ] else ...[
          // WebDAV + S3 share the trusted-cert / insecure surface —
          // one set of widgets driven by the kind-agnostic
          // `_trustedCertPemCtrl` + `_insecureSkipVerify` state.
          const SizedBox(height: AppSpacing.lg),
          _buildTrustedCertSection(),
          const SizedBox(height: AppSpacing.lg),
          _buildInsecureSkipVerifySection(),
        ],
      ],
    );
  }

  /// Trusted certificate PEM textarea — feeds
  /// [WebDavClient]/[S3Client] as an additional root CA so
  /// self-signed endpoints accept without OS-trust-store edits.
  /// Paste one or more `-----BEGIN CERTIFICATE-----` blocks (full
  /// chains supported). Disabled when [_insecureSkipVerify] is on,
  /// because skip-verify wins at the transport level and the cert
  /// list becomes a no-op.
  Widget _buildTrustedCertSection() {
    final l10n = S.of(context);
    final disabled = _insecureSkipVerify;
    return _OptionRow(
      label: l10n.trustedCert,
      detail: Opacity(
        opacity: disabled ? 0.5 : 1.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _trustedCertPemCtrl,
              enabled: !disabled,
              maxLines: 5,
              minLines: 3,
              decoration: InputDecoration(
                hintText: l10n.trustedCertHint,
                hintStyle: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: AppFonts.xs,
                  color: AppTheme.fgFaint,
                ),
                isDense: true,
                filled: true,
                fillColor: AppTheme.bg3,
                border: OutlineInputBorder(
                  borderRadius: AppTheme.radiusSm,
                  borderSide: BorderSide(color: AppTheme.borderLight),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: AppFonts.xs,
                color: AppTheme.fg,
              ),
              // The PEM is the public half of an X.509 cert — paste
              // it without IME mangling.
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              textCapitalization: TextCapitalization.none,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              l10n.trustedCertHelp,
              style: TextStyle(
                fontFamily: AppFonts.interFamily,
                fontSize: AppFonts.xs,
                color: AppTheme.fgFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Accept any certificate" toggle — flips on
  /// `reqwest::ClientBuilder::danger_accept_invalid_certs(true)`
  /// + `danger_accept_invalid_hostnames(true)`. Renders an
  /// explicit MITM warning so the user opts in knowingly. When
  /// active the trusted-cert textarea above is disabled because
  /// skip-verify wins at the transport level.
  Widget _buildInsecureSkipVerifySection() {
    final l10n = S.of(context);
    return _OptionRow(
      label: l10n.acceptAnyCert,
      trailing: Switch(
        value: _insecureSkipVerify,
        onChanged: (v) => rebuild(() => _insecureSkipVerify = v),
      ),
      detail: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.acceptAnyCertHelp,
            style: TextStyle(
              fontFamily: AppFonts.interFamily,
              fontSize: AppFonts.xs,
              color: AppTheme.fgFaint,
            ),
          ),
          if (_insecureSkipVerify) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: AppTheme.red,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    l10n.acceptAnyCertWarn,
                    style: TextStyle(
                      fontFamily: AppFonts.interFamily,
                      fontSize: AppFonts.xs,
                      color: AppTheme.red,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
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

  /// Tags option row — inline toggle picker that drives the
  /// dialog-local [_pendingTagIds] state. Works identically for new
  /// and edited sessions (new sessions start with an empty set;
  /// edits hydrate from `dbTagsListForSession` on init). The save
  /// path ships the resulting set in [SaveResult.pendingTagIds] so
  /// the caller diffs against the persisted rows and links /
  /// unlinks the delta after the session row commits — same
  /// buffering shape the port-forward rule editor uses.
  Widget _buildTagsSection() {
    final s = S.of(context);
    return _OptionRow(
      label: s.tags,
      // `manageTags` opens the workspace tag manager (rename /
      // delete / colour). The same string already labels the
      // identical action inside TagAssignDialog — reusing it keeps
      // the workspace vocabulary consistent.
      trailing: AppButton.secondary(
        label: s.manageTags,
        icon: Icons.tune,
        dense: true,
        onTap: () => TagManagerDialog.show(context),
      ),
      detail: _PendingTagsPicker(
        selected: _pendingTagIds,
        loaded: _pendingTagsLoaded,
        onToggle: (id) {
          rebuild(() {
            _pendingTagsTouched = true;
            if (_pendingTagIds.contains(id)) {
              _pendingTagIds = {..._pendingTagIds}..remove(id);
            } else {
              _pendingTagIds = {..._pendingTagIds, id};
            }
          });
        },
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

/// Inline tag picker shared by new and edited sessions. Renders
/// every tag in the workspace as a toggleable chip — the user taps
/// to add / remove from the dialog-local pending selection passed
/// in via [selected]. Writes flow through [onToggle] back into the
/// dialog state; the actual `session_tags` link / unlink fires
/// caller-side after the parent session row commits (see
/// `session_panel_session_actions._syncTagAssignments`).
///
/// `loaded = false` for edited sessions until the hydration future
/// resolves — gates the render to a small spinner so the user does
/// not start toggling against an empty initial state that would
/// then race the async load. New sessions ship `loaded = true`
/// immediately because there is no DB row to wait on.
class _PendingTagsPicker extends ConsumerWidget {
  final Set<String> selected;
  final bool loaded;
  final ValueChanged<String> onToggle;

  const _PendingTagsPicker({
    required this.selected,
    required this.loaded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    if (!loaded) {
      return const SizedBox(
        height: 16,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final tagsAsync = ref.watch(tagsProvider);
    return tagsAsync.when(
      loading: () => const SizedBox(
        height: 16,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (allTags) {
        if (allTags.isEmpty) {
          return Text(
            s.noTagsAvailable,
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
          children: [
            for (final tag in allTags)
              _PendingTagChip(
                tag: tag,
                active: selected.contains(tag.id),
                onTap: () => onToggle(tag.id),
              ),
          ],
        );
      },
    );
  }
}

/// One togglable chip inside [_PendingTagsPicker]. Active chips
/// pick up the tag's accent color + filled background; inactive
/// chips render dim with a thin outline so the affordance reads as
/// "tap to add" without taking the same visual weight as assigned
/// tags.
class _PendingTagChip extends StatelessWidget {
  final Tag tag;
  final bool active;
  final VoidCallback onTap;

  const _PendingTagChip({
    required this.tag,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = tag.colorValue ?? AppTheme.fgDim;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: AppTheme.radiusSm,
          border: Border.all(
            color: color.withValues(alpha: active ? 0.4 : 0.25),
          ),
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
              style: TextStyle(
                fontSize: AppFonts.xs,
                color: active ? AppTheme.fg : AppTheme.fgDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
