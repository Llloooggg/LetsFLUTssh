import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../src/rust/api/app.dart' as rust_app;
import '../src/rust/api/pkcs11.dart' as rust_pkcs11;
import '../theme/app_theme.dart';
import '../utils/logger.dart';
import 'app_dialog.dart';
import 'hardware_key_prompt_dialog.dart';
import 'pkcs11_import_dialog_logic.dart';

/// Bundled outcome of a successful PKCS#11 wizard run. Returned via
/// `Navigator.pop` so the caller can refresh its key listing without
/// reaching back into FRB — the row already landed Rust-side as part
/// of `pkcs11_import_key`.
class Pkcs11ImportResult {
  /// The new `ssh_keys.id` Rust assigned. Mirrors the caller-side
  /// existing-id contract `SshKeysNotifier.save` keeps.
  final String keyId;

  /// Human-readable label the user accepted at submit time. Echoed
  /// into the success toast so the user sees the same string they
  /// typed.
  final String label;

  const Pkcs11ImportResult({required this.keyId, required this.label});
}

/// Backend abstraction so widget tests can drive every wizard step
/// without booting FRB. The production implementation
/// ([Pkcs11FrbBackend]) delegates straight to the FRB shim; tests
/// override individual methods to seed deterministic responses.
abstract class Pkcs11Backend {
  /// Default production wiring. Holds no state; safe to share across
  /// dialog instances.
  const Pkcs11Backend();

  /// Discover candidate modules on disk. Cheap — does not load any
  /// `.so` / `.dll` yet (the load happens on selection).
  Future<List<rust_pkcs11.DbPkcs11ModuleCandidate>> scanWellKnownPaths();

  /// Probe-load the module at [path]. Throws a typed PKCS#11 error
  /// envelope on failure; the dialog catches it and renders the
  /// localized `pkcs11InitializeFailed` toast.
  Future<void> loadModule(String path);

  /// Enumerate tokens (slots-with-token) under the chosen module.
  Future<List<rust_pkcs11.DbPkcs11TokenInfo>> listTokens(String path);

  /// Enumerate signable keys on the token in [slotId]. The Rust side
  /// reads the staged PIN from the process-singleton SecretStore by
  /// `pinSecretId`; `null` is the protected-authentication-path /
  /// no-login arm.
  Future<List<rust_pkcs11.DbPkcs11KeyMeta>> listKeys(
    String path,
    BigInt slotId, {
    String? pinSecretId,
  });

  /// Persist the picked key as a new `ssh_keys` row. Returns the
  /// assigned id.
  Future<String> importKey(rust_pkcs11.DbPkcs11ImportArgs args);

  /// Build the `pkcs11:` URI captured at import. We compose it Dart-
  /// side from the picked metadata so the Rust shim does not need a
  /// second probe to render the URI body.
  String composeUri({
    required String tokenLabel,
    required String serial,
    required String objectLabel,
    required Uint8List objectId,
    required String modulePath,
  });

  /// Stage [bytes] under [id] in the process-singleton SecretStore.
  /// The Rust `listKeys` call reads the entry by id; the wizard
  /// drops the entry on success or cancel so leftover PINs never
  /// accumulate.
  Future<void> stagePin(String id, List<int> bytes);

  /// Best-effort PIN drop. Failure must not block the dialog.
  Future<void> dropPin(String id);
}

/// Live production backend — every method routes straight into the
/// FRB shim under `lib/src/rust/api/pkcs11.dart` + `app.dart`.
class Pkcs11FrbBackend extends Pkcs11Backend {
  const Pkcs11FrbBackend();

  @override
  Future<List<rust_pkcs11.DbPkcs11ModuleCandidate>> scanWellKnownPaths() =>
      rust_pkcs11.pkcs11ScanWellKnownPaths();

  @override
  Future<void> loadModule(String path) =>
      rust_pkcs11.pkcs11LoadModule(path: path);

  @override
  Future<List<rust_pkcs11.DbPkcs11TokenInfo>> listTokens(String path) =>
      rust_pkcs11.pkcs11ListTokens(path: path);

  @override
  Future<List<rust_pkcs11.DbPkcs11KeyMeta>> listKeys(
    String path,
    BigInt slotId, {
    String? pinSecretId,
  }) => rust_pkcs11.pkcs11ListKeys(
    path: path,
    slotId: slotId,
    pinSecretId: pinSecretId,
  );

  @override
  Future<String> importKey(rust_pkcs11.DbPkcs11ImportArgs args) =>
      rust_pkcs11.pkcs11ImportKey(args: args);

  @override
  Future<void> stagePin(String id, List<int> bytes) =>
      rust_app.secretsPut(id: id, bytes: bytes);

  @override
  Future<void> dropPin(String id) async {
    try {
      rust_app.secretsDrop(id: id);
    } catch (_) {
      // Idle-eviction sweep cleans up anyway; never block dispose.
    }
  }

  @override
  String composeUri({
    required String tokenLabel,
    required String serial,
    required String objectLabel,
    required Uint8List objectId,
    required String modulePath,
  }) {
    // RFC 7512 attributes. We pct-encode every value that may carry
    // delimiter chars; `Uri.encodeQueryComponent` happens to escape
    // exactly the right characters (`;`, `=`, `?`, `/`, `:`, space).
    final parts = <String>[
      'token=${Uri.encodeQueryComponent(tokenLabel)}',
      'serial=${Uri.encodeQueryComponent(serial)}',
      'object=${Uri.encodeQueryComponent(objectLabel)}',
      'id=${_encodeIdAttribute(objectId)}',
    ];
    if (modulePath.isNotEmpty) {
      parts.add('module-path=${Uri.encodeQueryComponent(modulePath)}');
    }
    return 'pkcs11:${parts.join(';')}';
  }

  /// RFC 7512 `id` attribute — opaque byte string, pct-encoded.
  /// `pk11-attr-chars` accepts alphanumerics + `-._~` unescaped;
  /// everything else is `%XX`. The Rust parser does the symmetric
  /// inverse in `lfs_os_security::pkcs11::uri`.
  static String _encodeIdAttribute(Uint8List bytes) {
    final buf = StringBuffer();
    for (final b in bytes) {
      if ((b >= 0x30 && b <= 0x39) ||
          (b >= 0x41 && b <= 0x5A) ||
          (b >= 0x61 && b <= 0x7A) ||
          b == 0x2D ||
          b == 0x2E ||
          b == 0x5F ||
          b == 0x7E) {
        buf.writeCharCode(b);
      } else {
        buf.write('%');
        buf.write(b.toRadixString(16).padLeft(2, '0').toUpperCase());
      }
    }
    return buf.toString();
  }
}

/// Per-module probe outcome. Drives the small status dot in
/// `_ModuleRow`. Colours follow the standard green / amber / red
/// triad used elsewhere for healthy / warning / error.
enum Pkcs11ModuleProbe { ready, noToken, failed }

/// Top-level wizard. Drives the five-step ladder
/// (module → token → pin → key → save), composes the import args, and
/// pops a [Pkcs11ImportResult] on success.
class Pkcs11ImportDialog extends StatefulWidget {
  /// Backend injection. Defaults to the FRB-backed implementation.
  final Pkcs11Backend backend;

  /// Test seam — lets the picker step skip the native `FilePicker` (it
  /// throws `MissingPluginException` in widget tests).
  final Future<String?> Function()? pickModuleFile;

  const Pkcs11ImportDialog({
    super.key,
    this.backend = const Pkcs11FrbBackend(),
    this.pickModuleFile,
  });

  /// Convenience opener. Always returns whatever the dialog popped —
  /// `null` when the user dismissed without saving.
  static Future<Pkcs11ImportResult?> show(
    BuildContext context, {
    Pkcs11Backend backend = const Pkcs11FrbBackend(),
    Future<String?> Function()? pickModuleFile,
  }) {
    return AppDialog.show<Pkcs11ImportResult>(
      context,
      builder: (_) =>
          Pkcs11ImportDialog(backend: backend, pickModuleFile: pickModuleFile),
    );
  }

  @override
  State<Pkcs11ImportDialog> createState() => _Pkcs11ImportDialogState();
}

class _Pkcs11ImportDialogState extends State<Pkcs11ImportDialog> {
  Pkcs11WizardStep _step = Pkcs11WizardStep.module;

  // Module step.
  bool _scanning = true;
  List<rust_pkcs11.DbPkcs11ModuleCandidate> _modules = const [];
  String? _modulePath;
  final Map<String, Pkcs11ModuleProbe> _moduleProbes = {};

  // Token step.
  bool _loadingTokens = false;
  List<rust_pkcs11.DbPkcs11TokenInfo> _tokens = const [];
  rust_pkcs11.DbPkcs11TokenInfo? _token;

  // PIN step.
  String? _pinSecretId;

  // Key step.
  bool _loadingKeys = false;
  List<rust_pkcs11.DbPkcs11KeyMeta> _keys = const [];
  rust_pkcs11.DbPkcs11KeyMeta? _key;

  // Save step.
  bool _saving = false;
  final TextEditingController _labelCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _kickScan();
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    // Drop the staged PIN unconditionally. The Rust side already
    // consumed it for the import; this guards swallowed-exception
    // paths from leaving a stale entry pinned.
    final pid = _pinSecretId;
    if (pid != null) {
      unawaited(widget.backend.dropPin(pid));
    }
    super.dispose();
  }

  Future<void> _kickScan() async {
    try {
      final found = await widget.backend.scanWellKnownPaths();
      if (!mounted) return;
      setState(() {
        _modules = found;
        _scanning = false;
      });
    } catch (e) {
      AppLogger.instance.log(
        'pkcs11 scan failed: $e',
        name: 'Pkcs11Wizard',
        error: e,
      );
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _probeModule(String path) async {
    try {
      await widget.backend.loadModule(path);
      final tokens = await widget.backend.listTokens(path);
      if (!mounted) return;
      setState(() {
        _moduleProbes[path] = tokens.isEmpty
            ? Pkcs11ModuleProbe.noToken
            : Pkcs11ModuleProbe.ready;
      });
    } catch (e) {
      AppLogger.instance.log(
        'pkcs11 module probe failed: $e',
        name: 'Pkcs11Wizard',
        error: e,
      );
      if (!mounted) return;
      setState(() => _moduleProbes[path] = Pkcs11ModuleProbe.failed);
    }
  }

  Future<void> _pickCustomModule() async {
    final picker = widget.pickModuleFile ?? _nativePickModule;
    final path = await picker();
    if (path == null || !mounted) return;
    setState(() {
      _modules = [
        ..._modules,
        rust_pkcs11.DbPkcs11ModuleCandidate(vendor: 'Custom', path: path),
      ];
    });
    await _probeModule(path);
  }

  Future<String?> _nativePickModule() async {
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: S.of(context).pkcs11ModulePickerTitle,
        allowMultiple: false,
        type: FileType.any,
      );
      return result?.files.single.path;
    } catch (e) {
      AppLogger.instance.log(
        'pkcs11 module file-picker failed: $e',
        name: 'Pkcs11Wizard',
        error: e,
      );
      return null;
    }
  }

  Future<void> _loadTokens(String path) async {
    setState(() => _loadingTokens = true);
    try {
      final t = await widget.backend.listTokens(path);
      if (!mounted) return;
      setState(() {
        _tokens = t;
        _loadingTokens = false;
      });
    } catch (e) {
      AppLogger.instance.log(
        'pkcs11 list_tokens failed: $e',
        name: 'Pkcs11Wizard',
        error: e,
      );
      if (mounted) setState(() => _loadingTokens = false);
    }
  }

  Future<void> _loadKeys() async {
    final path = _modulePath;
    final token = _token;
    if (path == null || token == null) return;
    setState(() => _loadingKeys = true);
    try {
      final keys = await widget.backend.listKeys(
        path,
        token.slotId,
        pinSecretId: _pinSecretId,
      );
      if (!mounted) return;
      setState(() {
        _keys = keys;
        _loadingKeys = false;
      });
    } catch (e) {
      AppLogger.instance.log(
        'pkcs11 list_keys failed: $e',
        name: 'Pkcs11Wizard',
        error: e,
      );
      if (!mounted) return;
      setState(() => _loadingKeys = false);
    }
  }

  Future<void> _stagePinAndAdvance(String pin) async {
    // SecretStore id derived from the wizard instance — short-lived,
    // dropped on `dispose`. Microsecond timestamp avoids reusing a
    // stale staged value across a crashed-and-restarted wizard.
    final id = 'pkcs11.pin.wizard.${DateTime.now().microsecondsSinceEpoch}';
    try {
      await widget.backend.stagePin(id, pin.codeUnits);
    } catch (e) {
      AppLogger.instance.log(
        'pkcs11 PIN stage failed: $e',
        name: 'Pkcs11Wizard',
        error: e,
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _pinSecretId = id;
      _step = Pkcs11WizardStep.key;
    });
    await _loadKeys();
  }

  Future<void> _submit() async {
    final path = _modulePath;
    final token = _token;
    final key = _key;
    if (path == null || token == null || key == null) return;
    final typed = _labelCtrl.text.trim();
    final label = typed.isEmpty ? key.label : typed;
    final uri = widget.backend.composeUri(
      tokenLabel: token.label,
      serial: token.serial,
      objectLabel: key.label,
      objectId: key.ckaId,
      modulePath: path,
    );
    setState(() => _saving = true);
    try {
      final id = await widget.backend.importKey(
        rust_pkcs11.DbPkcs11ImportArgs(
          label: label,
          modulePath: path,
          tokenSerial: token.serial,
          ckaId: key.ckaId,
          ckaLabel: key.label,
          sshKeyType: key.sshKeyType,
          sshPublicBlob: key.sshPublicBlob,
          pkcs11Uri: uri,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(Pkcs11ImportResult(keyId: id, label: label));
    } catch (e) {
      AppLogger.instance.log(
        'pkcs11 import_key failed: $e',
        name: 'Pkcs11Wizard',
        error: e,
      );
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AppDialog(
      title: _titleForStep(s),
      maxWidth: 560,
      content: SizedBox(height: 360, child: _bodyForStep(s)),
      actions: _actionsForStep(s),
    );
  }

  String _titleForStep(S s) {
    switch (_step) {
      case Pkcs11WizardStep.module:
        return s.pkcs11WizardStepModule;
      case Pkcs11WizardStep.token:
        return s.pkcs11WizardStepToken;
      case Pkcs11WizardStep.pin:
        return s.pkcs11WizardStepPin;
      case Pkcs11WizardStep.key:
        return s.pkcs11WizardStepKey;
      case Pkcs11WizardStep.save:
        return s.pkcs11SaveCta;
    }
  }

  Widget _bodyForStep(S s) {
    switch (_step) {
      case Pkcs11WizardStep.module:
        return _buildModuleStep(s);
      case Pkcs11WizardStep.token:
        return _buildTokenStep(s);
      case Pkcs11WizardStep.pin:
        return _buildPinStep(s);
      case Pkcs11WizardStep.key:
        return _buildKeyStep(s);
      case Pkcs11WizardStep.save:
        return _buildSaveStep(s);
    }
  }

  List<Widget> _actionsForStep(S s) {
    final canBack = _step != Pkcs11WizardStep.module && !_saving;
    final back = canBack
        ? AppButton.secondary(
            label: s.pkcs11WizardBack,
            onTap: () {
              final prev = pkcs11PrevStep(
                _step,
                protectedAuthPath: _token?.protectedAuthPath ?? false,
              );
              setState(() => _step = prev);
            },
          )
        : AppButton.cancel(
            onTap: _saving ? null : () => Navigator.of(context).pop(),
          );
    if (_step == Pkcs11WizardStep.save) {
      return [
        back,
        AppButton.primary(
          label: s.pkcs11SaveCta,
          onTap: _saving ? null : _submit,
          loading: _saving,
        ),
      ];
    }
    return [back];
  }

  // ── Module step ────────────────────────────────────────────────────

  Widget _buildModuleStep(S s) {
    if (_scanning) {
      return Center(child: Text(s.pkcs11ScanInProgress));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _modules.isEmpty
              ? Center(child: Text(s.pkcs11NoModuleFound))
              : ListView.separated(
                  itemCount: _modules.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final m = _modules[i];
                    return _ModuleRow(
                      vendor: m.vendor,
                      path: m.path,
                      probe: _moduleProbes[m.path],
                      selected: _modulePath == m.path,
                      onTap: () => _onModuleTap(m.path),
                    );
                  },
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton.secondary(
          label: s.pkcs11ModuleCustom,
          icon: Icons.folder_open,
          onTap: _pickCustomModule,
        ),
      ],
    );
  }

  Future<void> _onModuleTap(String path) async {
    setState(() => _modulePath = path);
    if (_moduleProbes[path] == null) {
      await _probeModule(path);
    }
    if (!mounted) return;
    final probe = _moduleProbes[path];
    if (probe == Pkcs11ModuleProbe.ready ||
        probe == Pkcs11ModuleProbe.noToken) {
      await _loadTokens(path);
      if (!mounted) return;
      setState(() => _step = Pkcs11WizardStep.token);
    }
  }

  // ── Token step ─────────────────────────────────────────────────────

  Widget _buildTokenStep(S s) {
    if (_loadingTokens) {
      return Center(child: Text(s.pkcs11LoadingTokens));
    }
    if (_tokens.isEmpty) {
      return Center(child: Text(s.pkcs11NoTokenPresent));
    }
    return ListView.separated(
      itemCount: _tokens.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final t = _tokens[i];
        return _TokenRow(
          tokenLabel: t.label,
          serial: t.serial,
          manufacturer: t.manufacturer,
          pinPad: t.protectedAuthPath,
          locked: t.userPinLocked,
          finalTry: t.userPinFinalTry,
          selected: _token?.slotId == t.slotId,
          onTap: t.userPinLocked ? null : () => _onTokenTap(t),
        );
      },
    );
  }

  Future<void> _onTokenTap(rust_pkcs11.DbPkcs11TokenInfo t) async {
    setState(() => _token = t);
    if (pkcs11ShouldSkipPinStep(protectedAuthPath: t.protectedAuthPath) ||
        !t.loginRequired) {
      // Skip in-app PIN: the token's own PIN pad or
      // public-object access answers the listing.
      setState(() => _step = Pkcs11WizardStep.key);
      await _loadKeys();
      return;
    }
    final res = await HardwareKeyPromptDialog.show(
      context,
      deviceName: t.label,
      requiresPin: true,
    );
    if (res == null || res.cancelled || res.pin == null) {
      return;
    }
    await _stagePinAndAdvance(res.pin!);
  }

  // ── PIN step ───────────────────────────────────────────────────────
  //
  // Reuse the existing HardwareKeyPromptDialog so the visual contract
  // for hardware-key affordances stays consistent across PKCS#11 +
  // FIDO2 paths. The PIN dialog opens inline from the token-row tap;
  // this step exists in the state machine only as a landing pad for
  // the Back button.

  Widget _buildPinStep(S s) {
    return Center(child: Text(s.pkcs11WizardStepPin));
  }

  // ── Key step ───────────────────────────────────────────────────────

  Widget _buildKeyStep(S s) {
    if (_loadingKeys) {
      return Center(child: Text(s.pkcs11LoadingKeys));
    }
    if (_keys.isEmpty) {
      return Center(child: Text(s.pkcs11NoSignableKeys));
    }
    return ListView.separated(
      itemCount: _keys.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final k = _keys[i];
        final enabled = pkcs11KeyRowEnabled(
          sshKeyType: k.sshKeyType,
          disabledReason: k.disabledReason,
        );
        return _KeyRow(
          objectLabel: k.label,
          sshKeyType: k.sshKeyType,
          disabledReason: k.disabledReason,
          enabled: enabled,
          selected: _key?.ckaId == k.ckaId,
          onTap: enabled
              ? () {
                  setState(() {
                    _key = k;
                    _step = Pkcs11WizardStep.save;
                    _labelCtrl.text = k.label;
                  });
                }
              : null,
        );
      },
    );
  }

  // ── Save step ──────────────────────────────────────────────────────

  Widget _buildSaveStep(S s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_saving) ...[
          Text(s.pkcs11SaveInProgress),
          const SizedBox(height: AppSpacing.md),
        ],
        TextField(
          controller: _labelCtrl,
          decoration: InputDecoration(
            labelText: s.keyLabel,
            hintText: s.keyLabelHint,
          ),
          autofocus: true,
          enabled: !_saving,
        ),
      ],
    );
  }
}

// ── Internal supporting widgets ──────────────────────────────────────

class _ModuleRow extends StatelessWidget {
  final String vendor;
  final String path;
  final Pkcs11ModuleProbe? probe;
  final bool selected;
  final VoidCallback? onTap;

  const _ModuleRow({
    required this.vendor,
    required this.path,
    required this.probe,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent.withValues(alpha: 0.08) : null,
        ),
        child: Row(
          children: [
            _StatusDot(probe: probe),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vendor,
                    style: AppFonts.inter(
                      fontSize: AppFonts.sm,
                      color: AppTheme.fg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    path,
                    style: AppFonts.mono(
                      fontSize: AppFonts.xs,
                      color: AppTheme.fgDim,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Pkcs11ModuleProbe? probe;
  const _StatusDot({required this.probe});

  @override
  Widget build(BuildContext context) {
    final color = switch (probe) {
      Pkcs11ModuleProbe.ready => AppTheme.green,
      Pkcs11ModuleProbe.noToken => AppTheme.orange,
      Pkcs11ModuleProbe.failed => AppTheme.red,
      null => AppTheme.fgDim,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _TokenRow extends StatelessWidget {
  final String tokenLabel;
  final String serial;
  final String manufacturer;
  final bool pinPad;
  final bool locked;
  final bool finalTry;
  final bool selected;
  final VoidCallback? onTap;

  const _TokenRow({
    required this.tokenLabel,
    required this.serial,
    required this.manufacturer,
    required this.pinPad,
    required this.locked,
    required this.finalTry,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: locked ? 0.5 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent.withValues(alpha: 0.08) : null,
          ),
          child: Row(
            children: [
              Icon(Icons.memory, size: 16, color: AppTheme.fgDim),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _tokenColumn(s),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _tokenColumn(S s) {
    return [
      Text(
        tokenLabel,
        style: AppFonts.inter(
          fontSize: AppFonts.sm,
          fontWeight: FontWeight.w600,
          color: AppTheme.fg,
        ),
      ),
      Text(
        s.pkcs11InfoTokenSerial(serial),
        style: AppFonts.mono(fontSize: AppFonts.xs, color: AppTheme.fgDim),
      ),
      if (manufacturer.isNotEmpty)
        Text(
          manufacturer,
          style: AppFonts.inter(fontSize: AppFonts.xs, color: AppTheme.fgDim),
        ),
      if (pinPad)
        Text(
          s.pkcs11PinPadHint,
          style: AppFonts.inter(fontSize: AppFonts.xs, color: AppTheme.accent),
        ),
      if (locked)
        Text(
          s.pkcs11PinLocked,
          style: AppFonts.inter(fontSize: AppFonts.xs, color: AppTheme.red),
        )
      else if (finalTry)
        Text(
          s.pkcs11PinIncorrect('1'),
          style: AppFonts.inter(fontSize: AppFonts.xs, color: AppTheme.orange),
        ),
    ];
  }
}

class _KeyRow extends StatelessWidget {
  final String objectLabel;
  final String sshKeyType;
  final String disabledReason;
  final bool enabled;
  final bool selected;
  final VoidCallback? onTap;

  const _KeyRow({
    required this.objectLabel,
    required this.sshKeyType,
    required this.disabledReason,
    required this.enabled,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final algoDetail = pkcs11AlgoDetail(sshKeyType);
    final algoLabel = algoDetail.algo.isEmpty
        ? (disabledReason.startsWith('gost') ? s.pkcs11AlgoGost : sshKeyType)
        : algoDetail.algo;
    final meta = algoDetail.detail.isEmpty
        ? algoLabel
        : s.pkcs11KeyMetaFormat(algoLabel, algoDetail.detail);
    return InkWell(
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent.withValues(alpha: 0.08) : null,
          ),
          child: Row(
            children: [
              Icon(
                Icons.key,
                size: 16,
                color: enabled ? AppTheme.accent : AppTheme.fgDim,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      objectLabel,
                      style: AppFonts.inter(
                        fontSize: AppFonts.sm,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.fg,
                      ),
                    ),
                    Text(
                      meta,
                      style: AppFonts.mono(
                        fontSize: AppFonts.xs,
                        color: AppTheme.fgDim,
                      ),
                    ),
                    if (!enabled && disabledReason.isNotEmpty)
                      Text(
                        s.pkcs11GostUnsupported,
                        style: AppFonts.inter(
                          fontSize: AppFonts.xs,
                          color: AppTheme.orange,
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

// ── PKCS#11 row badge + info popover ─────────────────────────────────

/// Hardware badge variant for `backend = 'pkcs11'` rows in the key
/// manager. Renders the localized `pkcs11Badge` pill, with a tap
/// affordance that drops an [AppDialog] showing the module path,
/// token serial, and object label captured at import.
///
/// Visual contract mirrors the `_HardwareBadge` pill in
/// `key_manager_dialog.dart` so the row tail reads consistently when
/// PKCS#11 + FIDO2 + certificate badges co-exist on a list dialog.
class Pkcs11Badge extends StatelessWidget {
  final String label;
  final String? modulePath;
  final String? tokenSerial;
  final String? objectLabel;

  const Pkcs11Badge({
    super.key,
    required this.label,
    this.modulePath,
    this.tokenSerial,
    this.objectLabel,
  });

  void _showInfo(BuildContext context) {
    final s = S.of(context);
    AppDialog.show<void>(
      context,
      builder: (ctx) => AppDialog(
        title: s.pkcs11Badge,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (modulePath != null && modulePath!.isNotEmpty)
              Text(
                s.pkcs11InfoModulePath(modulePath!),
                style: AppFonts.mono(
                  fontSize: AppFonts.xs,
                  color: AppTheme.fgDim,
                ),
              ),
            if (tokenSerial != null && tokenSerial!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  s.pkcs11InfoTokenSerial(tokenSerial!),
                  style: AppFonts.mono(
                    fontSize: AppFonts.xs,
                    color: AppTheme.fgDim,
                  ),
                ),
              ),
            if (objectLabel != null && objectLabel!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  s.pkcs11InfoObjectLabel(objectLabel!),
                  style: AppFonts.inter(
                    fontSize: AppFonts.xs,
                    color: AppTheme.fgDim,
                  ),
                ),
              ),
          ],
        ),
        actions: [AppButton.cancel(onTap: () => Navigator.of(ctx).pop())],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: () => _showInfo(context),
        borderRadius: AppTheme.radiusSm,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.16),
            borderRadius: AppTheme.radiusSm,
            border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.memory, size: 12, color: AppTheme.accent),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: AppFonts.inter(
                  fontSize: AppFonts.xxs,
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
