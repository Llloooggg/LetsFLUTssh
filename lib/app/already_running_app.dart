import 'dart:io' show exit;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Minimal `MaterialApp` shown when another desktop instance holds the
/// single-instance lock.
///
/// Runs *before* `LetsFLUTsshApp` resolves its theme + widget registry,
/// so shared primitives like `AppButton` / `AppDialog` are not reachable
/// yet — keep the bare `MaterialApp` + `FilledButton` + hand-spelled
/// styles here. The caller (`main()` in `main.dart`) calls
/// `runApp(const AlreadyRunningApp())` and returns immediately, so the
/// main provider scope never initialises.
class AlreadyRunningApp extends StatelessWidget {
  const AlreadyRunningApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block, size: 48, color: AppTheme.fgDim),
              const SizedBox(height: 16),
              Text(
                'Another instance of LetsFLUTssh is already running.',
                style: TextStyle(fontSize: AppFonts.lg),
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: () => exit(0), child: const Text('OK')),
            ],
          ),
        ),
      ),
    );
  }
}
