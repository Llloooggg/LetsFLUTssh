part of 'settings_screen.dart';

// ═══════════════════════════════════════════════════════════════════
// Settings → Hardware security keys (FIDO2 / sk-*).
//
// Single user-visible control: "Prefer direct USB HID over system
// dialog". Off by default. The dispatcher in
// `lfs_core::fido2::brokers` routes assertion calls through the OS
// security-key broker (Windows WebAuthn.dll / Apple
// AuthenticationServices / Android Credential Manager) by default;
// flipping the toggle on Windows / macOS forces the direct CTAP2 HID
// transport instead.
//
// Linux ignores the toggle entirely — no broker exists there. iOS /
// Android ignore it — only the broker path is viable.
// ═══════════════════════════════════════════════════════════════════

class _Fido2BrokerSection extends ConsumerStatefulWidget {
  const _Fido2BrokerSection();

  @override
  ConsumerState<_Fido2BrokerSection> createState() =>
      _Fido2BrokerSectionState();
}

class _Fido2BrokerSectionState extends ConsumerState<_Fido2BrokerSection> {
  rust_fido2.DbFido2Transport? _snapshot;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    // Rust owns the dispatcher state — re-read on every rebuild so
    // a Settings tier change / config reload always renders against
    // the canonical view.
    setState(() {
      _snapshot = rust_fido2.fido2TransportSnapshot();
    });
  }

  /// Localized label for the OS broker dialog the dispatcher routes
  /// to on the current host. Surfaces "Windows Hello / security key"
  /// on Win, "System security key dialog" on macOS, the
  /// USB / NFC / BLE variants on iOS / Android.
  String _brokerLabel(S l10n) {
    if (Platform.isWindows) return l10n.fido2BrokerWindowsLabel;
    if (Platform.isMacOS) return l10n.fido2BrokerMacosLabel;
    if (Platform.isIOS) return l10n.fido2BrokerIosLabel;
    if (Platform.isAndroid) return l10n.fido2BrokerAndroidLabel;
    return l10n.fido2BrokerWindowsLabel;
  }

  Future<void> _setPrefer(bool prefer) async {
    // Sync FRB call — flips the process-wide atomic immediately so
    // the next sk-* assertion picks the right transport. Persistence
    // into config.json runs separately via the config provider.
    rust_fido2.fido2SetPreferDirectHid(prefer: prefer);
    await ref
        .read(configProvider.notifier)
        .update(
          (c) => c.copyWith(
            behavior: c.behavior.copyWith(fido2PreferDirectHid: prefer),
          ),
        );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);
    final snap = _snapshot;
    // Disable the toggle when only one transport exists on this
    // host. Linux: direct HID only — toggle is irrelevant. iOS /
    // Android: broker only — toggle is irrelevant.
    final bothPaths =
        snap != null && snap.brokerAvailable && snap.directHidAvailable;
    final preferDirect =
        snap?.preferDirectHid ??
        ref.watch(configProvider).behavior.fido2PreferDirectHid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: l10n.fido2BrokerSectionTitle),
        const SizedBox(height: 4),
        Text(
          '${l10n.fido2BrokerCurrentTransportLabel}: ${_currentTransportText(l10n, snap)}',
          style: TextStyle(fontSize: AppFonts.xs, color: AppTheme.fgDim),
        ),
        const SizedBox(height: 12),
        _Toggle(
          label: l10n.fido2BrokerPreferDirectHidTitle,
          value: preferDirect,
          onChanged: bothPaths ? _setPrefer : null,
        ),
        const SizedBox(height: 4),
        Text(
          bothPaths
              ? l10n.fido2BrokerPreferDirectHidSubtitle(_brokerLabel(l10n))
              : l10n.fido2BrokerSinglePathSubtitle(
                  _currentTransportText(l10n, snap),
                ),
          style: TextStyle(fontSize: AppFonts.xs, color: AppTheme.fgDim),
        ),
      ],
    );
  }

  String _currentTransportText(S l10n, rust_fido2.DbFido2Transport? snap) {
    if (snap == null) return l10n.fido2BrokerTransportNone;
    switch (snap.kind) {
      case 'broker':
        return _brokerLabel(l10n);
      case 'direct-hid':
        return l10n.fido2BrokerTransportDirectHid;
      default:
        return l10n.fido2BrokerTransportNone;
    }
  }
}
