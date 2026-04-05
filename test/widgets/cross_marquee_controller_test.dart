import 'package:flutter_test/flutter_test.dart';

import 'package:letsflutssh/widgets/cross_marquee_controller.dart';

void main() {
  group('CrossMarqueeController', () {
    late CrossMarqueeController controller;

    setUp(() {
      controller = CrossMarqueeController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('initial state is inactive', () {
      expect(controller.active, isFalse);
      expect(controller.globalPosition, isNull);
      expect(controller.phase, CrossMarqueePhase.end);
    });

    test('start sets phase and position', () {
      const pos = Offset(100, 200);
      controller.start(pos);

      expect(controller.active, isTrue);
      expect(controller.phase, CrossMarqueePhase.start);
      expect(controller.globalPosition, pos);
    });

    test('move updates position and phase', () {
      controller.start(const Offset(100, 200));
      controller.move(const Offset(150, 250));

      expect(controller.active, isTrue);
      expect(controller.phase, CrossMarqueePhase.move);
      expect(controller.globalPosition, const Offset(150, 250));
    });

    test('move is ignored when not active', () {
      controller.move(const Offset(150, 250));

      expect(controller.active, isFalse);
      expect(controller.globalPosition, isNull);
    });

    test('end resets state', () {
      controller.start(const Offset(100, 200));
      controller.move(const Offset(150, 250));
      controller.end();

      expect(controller.active, isFalse);
      expect(controller.globalPosition, isNull);
      expect(controller.phase, CrossMarqueePhase.end);
    });

    test('notifies listeners on start', () {
      var notified = 0;
      controller.addListener(() => notified++);

      controller.start(const Offset(10, 20));
      expect(notified, 1);
    });

    test('notifies listeners on move', () {
      var notified = 0;
      controller.start(const Offset(10, 20));

      controller.addListener(() => notified++);
      controller.move(const Offset(30, 40));
      expect(notified, 1);
    });

    test('notifies listeners on end', () {
      var notified = 0;
      controller.start(const Offset(10, 20));

      controller.addListener(() => notified++);
      controller.end();
      expect(notified, 1);
    });

    test('move does not notify when inactive', () {
      var notified = 0;
      controller.addListener(() => notified++);

      controller.move(const Offset(10, 20));
      expect(notified, 0);
    });

    test('full lifecycle: start → move → move → end', () {
      final phases = <CrossMarqueePhase>[];
      controller.addListener(() => phases.add(controller.phase));

      controller.start(const Offset(0, 0));
      controller.move(const Offset(10, 10));
      controller.move(const Offset(20, 20));
      controller.end();

      expect(phases, [CrossMarqueePhase.start, CrossMarqueePhase.move, CrossMarqueePhase.move, CrossMarqueePhase.end]);
    });

    test('can restart after end', () {
      controller.start(const Offset(0, 0));
      controller.end();

      controller.start(const Offset(50, 50));
      expect(controller.active, isTrue);
      expect(controller.globalPosition, const Offset(50, 50));
    });
  });
}
