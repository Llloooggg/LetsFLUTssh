import 'package:flutter/material.dart';

/// Root `MaterialApp` navigator key.
///
/// Used by callers outside the widget tree that need a `BuildContext`
/// with a mounted Navigator — crash-handler dialogs, deep-link pump,
/// post-frame toasts — because those contexts fire from `runZoned` /
/// async callbacks / native method channels where the framework
/// cannot otherwise hand them a live `BuildContext`.
///
/// Readers must always check `currentContext?.mounted` before use —
/// the MaterialApp can be in the middle of a rebuild or rotation
/// when the async callback resumes, at which point the context is
/// unmounted and calling `Navigator.of(context)` / `showDialog`
/// would throw.
final navigatorKey = GlobalKey<NavigatorState>();
