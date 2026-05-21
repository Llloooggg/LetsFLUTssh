import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/widgets/core/session_kind_icon.dart';

/// Pins the canonical SessionKind → IconData map so the sidebar
/// (session_tree_view) and the tab strip (panel_tab_bar) stay
/// visually symmetric for the same connection. The earlier shape
/// had two independent mappings — the tab strip collapsed every
/// non-terminal kind onto a generic `Icons.folder`, so an S3
/// session showed a bucket glyph in the sidebar and a folder
/// glyph at the top of its open tabs.
///
/// Adding a new [SessionKind] variant → extend [SessionKindIcon]
/// and add a row here. Both production surfaces go through the
/// same extension so they pick up the change at once.
void main() {
  group('SessionKindIcon', () {
    test('SSH renders the terminal glyph', () {
      expect(SessionKind.ssh.icon, Icons.terminal);
    });

    test('WebDAV renders the outlined cloud glyph', () {
      expect(SessionKind.webdav.icon, Icons.cloud_outlined);
    });

    test('S3 renders the outlined inventory (bucket) glyph', () {
      expect(SessionKind.s3.icon, Icons.inventory_2_outlined);
    });

    test('every variant resolves to a distinct icon', () {
      // Two different protocols sharing the same glyph would
      // collapse them on every surface that uses the icon to
      // discriminate. The set length matches the variant count.
      final icons = <IconData>{for (final k in SessionKind.values) k.icon};
      expect(
        icons.length,
        SessionKind.values.length,
        reason: 'Each SessionKind must map to a distinct IconData.',
      );
    });
  });
}
