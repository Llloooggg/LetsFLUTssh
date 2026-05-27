/// Tests for [HardwareKeyWizardMixin] — the shared four-stage ladder
/// (probing → configure → generating → complete) every hardware-key SSH
/// wizard walks. The backend-specific probe / generate hooks make real
/// OS / native calls in the concrete wizards (Secure Enclave, Hello,
/// Keystore, TPM) and are out of scope here; a minimal test wizard
/// supplies controllable fakes so the state-machine transitions and
/// their failure fallbacks can be driven deterministically.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/widgets/ssh_keys/hardware_key_wizard.dart';

/// Minimal wizard that mixes in the shared scaffold and routes the
/// abstract hooks to test-controllable behaviour.
class _TestWizard extends StatefulWidget {
  const _TestWizard({
    this.probeError,
    this.generateResult,
    this.generateError,
    this.allowGenerate = true,
    this.initialLabel,
  });

  final Object? probeError;
  final String? generateResult;
  final Object? generateError;
  final bool allowGenerate;
  final String? initialLabel;

  @override
  State<_TestWizard> createState() => _TestWizardState();
}

class _TestWizardState extends State<_TestWizard>
    with HardwareKeyWizardMixin<_TestWizard> {
  Object? lastProbeFailure;

  @override
  String wizardTitle(S s) => 'Test wizard';
  @override
  String get wizardLogName => 'TestWizard';
  @override
  String? get wizardInitialLabel => widget.initialLabel;

  @override
  Future<void> runProbe() async {
    if (widget.probeError != null) throw widget.probeError!;
  }

  @override
  void onProbeFailure(Object error) => lastProbeFailure = error;

  @override
  Widget buildConfigure(S s) => const Text('configure-body');

  @override
  bool get canGenerate => widget.allowGenerate;

  @override
  Future<String?> runGenerate() async {
    if (widget.generateError != null) throw widget.generateError!;
    return widget.generateResult;
  }

  @override
  Widget buildComplete(S s) => const Text('complete-body');

  @override
  Widget build(BuildContext context) =>
      buildWizard(S.of(context), onDone: () {});
}

void main() {
  Future<_TestWizardState> pumpWizard(
    WidgetTester tester,
    _TestWizard wizard,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        home: Scaffold(body: wizard),
      ),
    );
    // One frame lets the async `runProbe` in initState resolve. Avoid
    // pumpAndSettle: the probing/generating spinners animate forever.
    await tester.pump();
    return tester.state<_TestWizardState>(find.byType(_TestWizard));
  }

  testWidgets('a successful probe lands on the configure step', (tester) async {
    final state = await pumpWizard(tester, const _TestWizard());
    expect(state.step, HardwareKeyStep.configure);
    expect(state.lastProbeFailure, isNull);
  });

  testWidgets('a failed probe still reaches configure via the fallback', (
    tester,
  ) async {
    final state = await pumpWizard(
      tester,
      _TestWizard(probeError: Exception('no chip')),
    );
    expect(state.step, HardwareKeyStep.configure);
    expect(state.lastProbeFailure, isA<Exception>());
  });

  testWidgets('the initial label seeds the shared field', (tester) async {
    final state = await pumpWizard(
      tester,
      const _TestWizard(initialLabel: 'migrated-key'),
    );
    expect(state.labelCtrl.text, 'migrated-key');
  });

  testWidgets('generate success advances to the complete step', (tester) async {
    final state = await pumpWizard(
      tester,
      const _TestWizard(generateResult: 'ssh-ed25519 AAAA host'),
    );
    await state.runGenerateFlow();
    await tester.pump();
    expect(state.step, HardwareKeyStep.complete);
  });

  testWidgets('generate failure drops back to configure with the error', (
    tester,
  ) async {
    final state = await pumpWizard(
      tester,
      _TestWizard(generateError: Exception('user cancelled')),
    );
    await state.runGenerateFlow();
    await tester.pump();
    expect(state.step, HardwareKeyStep.configure);
    expect(state.generateError, contains('user cancelled'));
  });

  testWidgets('a null generate result leaves the backend to transition', (
    tester,
  ) async {
    // Returning null means the backend handled its own non-completing
    // transition (e.g. the Keystore StrongBox-fallback prompt); the
    // mixin must not force the complete step.
    final state = await pumpWizard(tester, const _TestWizard());
    await state.runGenerateFlow();
    await tester.pump();
    expect(state.step, HardwareKeyStep.generating);
  });

  testWidgets('generate is a no-op when canGenerate is false', (tester) async {
    final state = await pumpWizard(
      tester,
      const _TestWizard(allowGenerate: false, generateResult: 'x'),
    );
    await state.runGenerateFlow();
    await tester.pump();
    expect(state.step, HardwareKeyStep.configure);
  });

  testWidgets('backToConfigure returns from a later step', (tester) async {
    final state = await pumpWizard(
      tester,
      const _TestWizard(generateResult: 'ssh-ed25519 AAAA host'),
    );
    await state.runGenerateFlow();
    await tester.pump();
    expect(state.step, HardwareKeyStep.complete);
    state.backToConfigure();
    await tester.pump();
    expect(state.step, HardwareKeyStep.configure);
  });
}
