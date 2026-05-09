import 'dart:io' show exit;

import 'package:flutter/material.dart';

import '../core/security/wipe_all_service.dart';
import '../l10n/app_localizations.dart';
import '../src/rust/api/app.dart' as rust_app;
import '../src/rust/frb_generated.dart' show RustLib;
import '../theme/app_theme.dart';
import '../utils/logger.dart';
import 'early_wipe.dart';

/// Minimal `MaterialApp` shown when an unrecoverable startup failure
/// stops the app before it can hand control to the normal UI.
///
/// Used by [main] when `loadAppConfigFromDisk` cannot parse
/// `config.json` and by `_initRustCoreOrFatal` when the bundled Rust
/// core fails to load. Without this screen the silent catch arm let
/// bootstrap continue, the next FRB call would throw, the migration
/// runner would interpret the throw as a corrupt-DB signal, and the
/// user would land on `DbCorruptDialog` whose "Reset and start fresh"
/// button calls `WipeAllService.wipeAll()` — destroying their on-disk
/// data over what is usually a transient bundle / packaging issue.
///
/// The "Wipe all data and quit" button tries the canonical Rust-side
/// [WipeAllService.wipeAll] first — it loads the Rust core lazily on
/// click (the cost lands AFTER the user explicitly decides to wipe,
/// not on the dialog open) so a clean wipe covers files + keychain +
/// hardware-vault entries. Only when `RustLib.init` itself fails
/// (broken bundle, missing native blob — the `_initRustCoreOrFatal`
/// case) does the handler fall through to the Dart-only file sweep
/// in [earlyWipeAppSupportFiles]; any keychain / hardware-vault
/// orphans then resurface on the next launch and route through the
/// normal tier-reset dialog.
///
/// Runs *before* `LetsFLUTsshApp` resolves its theme + widget
/// registry, so shared primitives like `AppButton` / `AppDialog` are
/// not reachable yet — keep the bare `MaterialApp` + `FilledButton`
/// + hand-spelled styles here. The caller calls
/// `runApp(FatalErrorApp(...))` and `return`s immediately, so the
/// main provider scope never initialises and there is no path to
/// the regular wipe action.
class FatalErrorApp extends StatefulWidget {
  final String summary;
  final String detail;

  const FatalErrorApp({super.key, required this.summary, required this.detail});

  @override
  State<FatalErrorApp> createState() => _FatalErrorAppState();
}

class _FatalErrorAppState extends State<FatalErrorApp> {
  bool _wiping = false;

  Future<void> _onWipe() async {
    if (_wiping) return;
    final l10n = S.of(context);
    final ctx = context;
    final confirmed = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.fatalErrorWipeConfirmTitle),
        content: Text(l10n.fatalErrorWipeConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.red),
            child: Text(l10n.fatalErrorWipeConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _wiping = true);
    // Prefer the canonical Rust path: it covers keychain + hardware
    // vault + writes the `.wipe-pending` crash-safety marker. We only
    // reach this dialog before `_initRustCoreOrFatal` runs, so try
    // initialising the core lazily here. If that succeeds we hand off
    // to `WipeAllService.wipeAll`; if it fails (the native blob is
    // the actual broken artefact), fall through to the Dart-only
    // file sweep — partial but still removes every managed file under
    // app-support, with the next launch's `_handleLegacyStateIfPresent`
    // mopping up keychain / hw-vault orphans.
    var ranCanonical = false;
    try {
      await RustLib.init();
      await rust_app.appInit();
      await WipeAllService().wipeAll();
      ranCanonical = true;
    } catch (e) {
      await AppLogger.instance.logCritical(
        'FatalErrorApp wipe: Rust path failed, falling back to Dart-only sweep',
        name: 'FatalErrorApp',
        error: e,
      );
    }
    if (!ranCanonical) {
      await earlyWipeAppSupportFiles();
    }
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      home: Builder(
        builder: (innerCtx) {
          final l10n = S.of(innerCtx);
          return Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: AppTheme.fgDim,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        widget.summary,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: AppFonts.lg),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        widget.detail,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: AppFonts.sm,
                          color: AppTheme.fgDim,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          OutlinedButton(
                            onPressed: _wiping ? null : () => exit(1),
                            child: Text(l10n.fatalErrorQuitButton),
                          ),
                          FilledButton(
                            onPressed: _wiping ? null : _onWipe,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.red,
                            ),
                            child: Text(
                              _wiping
                                  ? l10n.fatalErrorWipingButton
                                  : l10n.fatalErrorWipeButton,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        l10n.fatalErrorWipeExplanation,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: AppFonts.xs,
                          color: AppTheme.fgFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
