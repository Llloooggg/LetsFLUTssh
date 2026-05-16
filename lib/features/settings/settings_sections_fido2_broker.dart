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

/// Rust-owned dispatcher snapshot. Sync FRB call — invalidated after
/// every mutation so the next `ref.watch` reads canonical state.
final _fido2TransportSnapshotProvider = Provider<rust_fido2.DbFido2Transport>(
  (ref) => rust_fido2.fido2TransportSnapshot(),
);

class _Fido2BrokerSection extends ConsumerWidget {
  const _Fido2BrokerSection();

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

  Future<void> _setPrefer(WidgetRef ref, bool prefer) async {
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
    ref.invalidate(_fido2TransportSnapshotProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = S.of(context);
    final snap = ref.watch(_fido2TransportSnapshotProvider);
    // Three cases for the toggle subtitle (the `bothPaths` boolean
    // alone is not enough — the "neither path available" branch
    // produced "Only `Not available on this platform` is available
    // on this device" by feeding the no-transport label into the
    // single-path template):
    //   1. Both broker + direct-HID present → preference toggle
    //      subtitle.
    //   2. Exactly one transport present → "Only <name> is
    //      available; the toggle is disabled".
    //   3. Neither transport present → "Hardware key support not
    //      available on this device" prose, no toggle hint.
    final bothPaths = snap.brokerAvailable && snap.directHidAvailable;
    final neitherPath = !snap.brokerAvailable && !snap.directHidAvailable;
    final preferDirect = snap.preferDirectHid;
    final String subtitle;
    if (bothPaths) {
      subtitle = l10n.fido2BrokerPreferDirectHidSubtitle(_brokerLabel(l10n));
    } else if (neitherPath) {
      subtitle = l10n.fido2BrokerNoTransportSubtitle;
    } else {
      subtitle = l10n.fido2BrokerSinglePathSubtitle(
        _currentTransportText(l10n, snap),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: l10n.fido2BrokerSectionTitle),
        Text(
          '${l10n.fido2BrokerCurrentTransportLabel}: ${_currentTransportText(l10n, snap)}',
          style: TextStyle(fontSize: AppFonts.xs, color: AppTheme.fgDim),
        ),
        const SizedBox(height: AppSpacing.md),
        _Toggle(
          label: l10n.fido2BrokerPreferDirectHidTitle,
          value: preferDirect,
          onChanged: bothPaths ? (v) => _setPrefer(ref, v) : null,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: TextStyle(fontSize: AppFonts.xs, color: AppTheme.fgDim),
        ),
      ],
    );
  }

  String _currentTransportText(S l10n, rust_fido2.DbFido2Transport snap) {
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
