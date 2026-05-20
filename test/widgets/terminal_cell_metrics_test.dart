import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/terminal_cell_metrics.dart';

void main() {
  group('measureMonoCell', () {
    test('row pitch is fontSize × the xterm line-height multiplier', () {
      // The cell height must equal what xterm derives from the same
      // 1.2 multiplier, otherwise a host SizedBox drifts off the grid.
      final cell = measureMonoCell(fontSize: 20);
      expect(cell.height, closeTo(20 * kTerminalLineHeight, 1e-6));
    });

    test('scales the cell by the text scaler xterm renders with', () {
      // xterm measures its grid against MediaQuery's text scaler; an
      // unscaled host measurement clips the bottom row when the OS
      // text scale is above 1.0. So a 2× scaler must double the cell.
      final unscaled = measureMonoCell(fontSize: 16);
      final scaled = measureMonoCell(
        fontSize: 16,
        textScaler: const TextScaler.linear(2.0),
      );
      expect(scaled.width, closeTo(unscaled.width * 2, 1e-6));
      expect(scaled.height, closeTo(unscaled.height * 2, 1e-6));
    });

    test('defaults to no scaling', () {
      final explicit = measureMonoCell(
        fontSize: 16,
        textScaler: TextScaler.noScaling,
      );
      final byDefault = measureMonoCell(fontSize: 16);
      expect(byDefault.width, closeTo(explicit.width, 1e-6));
      expect(byDefault.height, closeTo(explicit.height, 1e-6));
    });

    test('cell size is linear in font size', () {
      final small = measureMonoCell(fontSize: 10);
      final big = measureMonoCell(fontSize: 30);
      expect(big.width, closeTo(small.width * 3, 1e-6));
      expect(big.height, closeTo(small.height * 3, 1e-6));
    });
  });
}
