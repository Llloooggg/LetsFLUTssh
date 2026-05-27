/// Unit tests for the unified-export model bundles. The optional-field
/// defaults are a contract: call sites that don't expose tags / snippets
/// / recordings rely on them, so a default drifting (e.g. recordingsBytes
/// to a non-zero sentinel) would silently change the export-size display.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/qr_codec.dart';
import 'package:letsflutssh/widgets/import_export/unified_export_models.dart';

void main() {
  group('UnifiedExportDialogData', () {
    test('optional collections default to empty and recordings to 0', () {
      const data = UnifiedExportDialogData(sessions: [], emptyFolders: {});
      expect(data.tags, isEmpty);
      expect(data.snippets, isEmpty);
      expect(data.recordingsBytes, 0);
      expect(data.config, isNull);
      expect(data.knownHostsContent, isNull);
    });

    test('carries the values it is given', () {
      const data = UnifiedExportDialogData(
        sessions: [],
        emptyFolders: {'Work'},
        recordingsBytes: 4096,
        knownHostsContent: 'host ssh-rsa AAAA',
      );
      expect(data.emptyFolders, {'Work'});
      expect(data.recordingsBytes, 4096);
      expect(data.knownHostsContent, 'host ssh-rsa AAAA');
    });
  });

  group('UnifiedExportResult', () {
    test('holds the chosen options and selection', () {
      const result = UnifiedExportResult(
        options: ExportOptions(),
        selectedSessions: [],
        selectedEmptyFolders: {'A', 'B'},
      );
      expect(result.selectedEmptyFolders, {'A', 'B'});
      expect(result.selectedSessions, isEmpty);
    });
  });
}
