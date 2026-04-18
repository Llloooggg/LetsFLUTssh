import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/form_submit_chain.dart';

void main() {
  group('FormSubmitChain', () {
    test('rejects zero-length construction', () {
      expect(
        () => FormSubmitChain(length: 0, onSubmit: () {}),
        throwsA(isA<AssertionError>()),
      );
    });

    test(
      'single-field chain uses TextInputAction.done and calls onSubmit on handler',
      () {
        var submits = 0;
        final chain = FormSubmitChain(length: 1, onSubmit: () => submits++);
        addTearDown(chain.dispose);

        expect(chain.actionAt(0), TextInputAction.done);
        chain.handlerAt(0)('whatever');
        expect(submits, 1);
      },
    );

    test(
      'multi-field chain uses .next for non-last fields and .done on the last',
      () {
        final chain = FormSubmitChain(length: 3, onSubmit: () {});
        addTearDown(chain.dispose);

        expect(chain.actionAt(0), TextInputAction.next);
        expect(chain.actionAt(1), TextInputAction.next);
        expect(chain.actionAt(2), TextInputAction.done);
      },
    );

    testWidgets(
      'handler on non-last field moves focus to the next field, handler on last '
      'field submits without moving focus',
      (tester) async {
        var submits = 0;
        final chain = FormSubmitChain(length: 3, onSubmit: () => submits++);
        addTearDown(chain.dispose);

        // Each FocusNode must be attached to a FocusScope to participate in
        // focus traversal, so mount the nodes inside a real widget tree.
        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: Column(
                children: [
                  TextField(focusNode: chain.nodeAt(0)),
                  TextField(focusNode: chain.nodeAt(1)),
                  TextField(focusNode: chain.nodeAt(2)),
                ],
              ),
            ),
          ),
        );

        chain.nodeAt(0).requestFocus();
        await tester.pump();
        expect(chain.nodeAt(0).hasFocus, isTrue);

        chain.handlerAt(0)('x');
        await tester.pump();
        expect(chain.nodeAt(1).hasFocus, isTrue);
        expect(submits, 0);

        chain.handlerAt(1)('y');
        await tester.pump();
        expect(chain.nodeAt(2).hasFocus, isTrue);
        expect(submits, 0);

        chain.handlerAt(2)('z');
        await tester.pump();
        expect(submits, 1);
        // Last handler submits, it must NOT push focus past the end of the
        // chain (that would crash on index out of range).
        expect(chain.nodeAt(2).hasFocus, isTrue);
      },
    );

    test('length reflects constructor argument', () {
      final chain = FormSubmitChain(length: 4, onSubmit: () {});
      addTearDown(chain.dispose);
      expect(chain.length, 4);
    });
  });
}
