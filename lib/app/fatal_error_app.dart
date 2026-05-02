import 'dart:io' show exit;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Minimal `MaterialApp` shown when an unrecoverable startup failure
/// stops the app before it can hand control to the normal UI.
///
/// Used by [main] when the bundled Rust core (`RustLib.init` /
/// `lfs_core::app::init`) fails to load or initialise. Without this
/// screen the silent catch arm let bootstrap continue, the next FRB
/// call would throw, the migration runner would interpret the throw
/// as a corrupt-DB signal, and the user would land on
/// `DbCorruptDialog` whose "Reset and start fresh" button calls
/// `WipeAllService.wipeAll()` — destroying their on-disk data over
/// what is usually a transient bundle / packaging issue.
///
/// Runs *before* `LetsFLUTsshApp` resolves its theme + widget
/// registry, so shared primitives like `AppButton` / `AppDialog` are
/// not reachable yet — keep the bare `MaterialApp` + `FilledButton`
/// + hand-spelled styles here. The caller calls
/// `runApp(FatalErrorApp(...))` and `return`s immediately, so the
/// main provider scope never initialises and there is no path to
/// the wipe action.
class FatalErrorApp extends StatelessWidget {
  final String summary;
  final String detail;

  const FatalErrorApp({super.key, required this.summary, required this.detail});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
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
                  const SizedBox(height: 16),
                  Text(
                    summary,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: AppFonts.lg),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    detail,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppFonts.sm,
                      color: AppTheme.fgDim,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => exit(1),
                    child: const Text('Quit'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
