import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/file_browser/column_widths.dart';
import 'package:letsflutssh/features/file_browser/transfer_panel_controller.dart';

void main() {
  group('FileBrowserColumns', () {
    test('transfer panel starts with the shared size + time defaults so the '
        'SFTP tab and the transfer queue stay visually aligned', () {
      final c = TransferPanelController();
      addTearDown(c.dispose);
      expect(c.sizeColWidth, FileBrowserColumns.size);
      expect(c.timeColWidth, FileBrowserColumns.modifiedOrTime);
    });

    test(
      'shared defaults are positive and fall inside the transfer-panel clamp '
      'range so the initial state is not rejected on first resize',
      () {
        expect(FileBrowserColumns.size, greaterThan(0));
        expect(
          FileBrowserColumns.size,
          inInclusiveRange(
            TransferPanelController.sizeColMin,
            TransferPanelController.sizeColMax,
          ),
        );

        expect(FileBrowserColumns.modifiedOrTime, greaterThan(0));
        expect(
          FileBrowserColumns.modifiedOrTime,
          inInclusiveRange(
            TransferPanelController.timeColMin,
            TransferPanelController.timeColMax,
          ),
        );
      },
    );
  });
}
