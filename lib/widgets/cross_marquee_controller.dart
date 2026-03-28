import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Phase of a cross-widget marquee drag.
enum CrossMarqueePhase { start, move, end }

/// Notifier for cross-widget marquee selection.
///
/// When a marquee drag exits the session panel bounds, the session panel
/// writes events here. The file pane listens and selects files accordingly.
class CrossMarqueeController extends ChangeNotifier {
  Offset? _globalPosition;
  CrossMarqueePhase _phase = CrossMarqueePhase.end;

  Offset? get globalPosition => _globalPosition;
  CrossMarqueePhase get phase => _phase;
  bool get active => _phase != CrossMarqueePhase.end;

  void start(Offset globalPos) {
    _phase = CrossMarqueePhase.start;
    _globalPosition = globalPos;
    notifyListeners();
  }

  void move(Offset globalPos) {
    if (_phase == CrossMarqueePhase.end) return;
    _phase = CrossMarqueePhase.move;
    _globalPosition = globalPos;
    notifyListeners();
  }

  void end() {
    _phase = CrossMarqueePhase.end;
    _globalPosition = null;
    notifyListeners();
  }
}
