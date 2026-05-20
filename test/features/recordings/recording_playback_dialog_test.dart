import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/recordings/recording_playback_dialog.dart';

void main() {
  group('playbackFitFontSize', () {
    const innerPad = 8.0;
    const minFont = 6.0;

    double fit({
      required double needW,
      required double needH,
      required double maxW,
      required double maxH,
      double desired = 12.0,
    }) => playbackFitFontSize(
      desiredFontSize: desired,
      neededWidth: needW,
      neededHeight: needH,
      maxWidth: maxW,
      maxHeight: maxH,
      innerPad: innerPad,
      minFontSize: minFont,
    );

    test('keeps the desired font when the grid fits both axes', () {
      expect(fit(needW: 400, needH: 300, maxW: 800, maxH: 600), 12.0);
    });

    test('keeps the desired font on the exact-fit boundary', () {
      expect(fit(needW: 800, needH: 600, maxW: 800, maxH: 600), 12.0);
    });

    test('scales down by the width overflow ratio when width is tighter', () {
      // Width needs 808 px in a 408 px viewport; height fits. The fit
      // excludes the constant 8 px padding from the scale: the grid's
      // 800 px of cells must collapse to 400 px → font halves.
      expect(
        fit(needW: 808, needH: 100, maxW: 408, maxH: 600),
        closeTo(6.0, 1e-9),
      );
    });

    test('scales down by the height overflow ratio when height is tighter', () {
      // Height: 12 * (308 - 8) / (608 - 8) = 6.0.
      expect(
        fit(needW: 100, needH: 608, maxW: 800, maxH: 308),
        closeTo(6.0, 1e-9),
      );
    });

    test('uses the tighter axis when both overflow', () {
      // Width ratio → 9.0; height ratio → 6.0. Tighter (height) wins.
      final result = fit(needW: 408, needH: 608, maxW: 308, maxH: 308);
      expect(result, closeTo(6.0, 1e-9));
    });

    test('floors at minFontSize when the grid is far too large', () {
      // Width ratio would drive the font well below the floor.
      final result = fit(needW: 4008, needH: 100, maxW: 108, maxH: 600);
      expect(result, minFont);
    });

    test('ignores an unbounded width constraint', () {
      expect(
        fit(needW: 5000, needH: 100, maxW: double.infinity, maxH: 600),
        12.0,
      );
    });

    test('ignores an unbounded height constraint', () {
      expect(
        fit(needW: 100, needH: 5000, maxW: 800, maxH: double.infinity),
        12.0,
      );
    });

    test('never returns above the desired font even with slack', () {
      expect(fit(needW: 10, needH: 10, maxW: 10000, maxH: 10000), 12.0);
    });
  });
}
