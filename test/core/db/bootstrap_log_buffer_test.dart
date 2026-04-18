import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/bootstrap_log_buffer.dart';

void main() {
  group('BootstrapLogBuffer', () {
    test('drainTo yields FIFO order and clears the buffer', () {
      final buf = BootstrapLogBuffer<int>(capacity: 8);
      buf.add(1);
      buf.add(2);
      buf.add(3);
      final drained = <int>[];
      buf.drainTo(drained.add);
      expect(drained, [1, 2, 3]);
      expect(buf.isEmpty, isTrue);
      expect(buf.length, 0);
    });

    test('oldest entry is dropped at capacity', () {
      final buf = BootstrapLogBuffer<int>(capacity: 3);
      buf.add(1);
      buf.add(2);
      buf.add(3);
      buf.add(4); // evicts 1
      buf.add(5); // evicts 2
      final drained = <int>[];
      buf.drainTo(drained.add);
      expect(drained, [3, 4, 5]);
    });

    test('empty buffer drains to nothing', () {
      final buf = BootstrapLogBuffer<int>();
      final drained = <int>[];
      buf.drainTo(drained.add);
      expect(drained, isEmpty);
    });

    test('reuse after drain preserves semantics', () {
      final buf = BootstrapLogBuffer<int>(capacity: 3);
      buf.add(1);
      buf.add(2);
      final first = <int>[];
      buf.drainTo(first.add);
      expect(first, [1, 2]);
      buf.add(10);
      buf.add(20);
      buf.add(30);
      buf.add(40); // evicts 10
      final second = <int>[];
      buf.drainTo(second.add);
      expect(second, [20, 30, 40]);
    });
  });
}
