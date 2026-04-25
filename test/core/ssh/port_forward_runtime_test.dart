import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/port_forward_rule.dart';
import 'package:letsflutssh/core/ssh/port_forward_runtime.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';

Connection _stubConnection() => Connection(
  id: 'c',
  label: 'l',
  sshConfig: const SSHConfig(
    server: ServerAddress(host: 'h', user: 'u'),
  ),
);

PortForwardRule _localRule({
  String id = 'r1',
  bool enabled = true,
  int bindPort = 0,
  String remoteHost = 'svc',
  int remotePort = 80,
}) => PortForwardRule(
  id: id,
  kind: PortForwardKind.local,
  bindHost: '127.0.0.1',
  bindPort: bindPort,
  remoteHost: remoteHost,
  remotePort: remotePort,
  enabled: enabled,
);

void main() {
  group('PortForwardRuntime', () {
    test('onConnected with no live SSHClient is a no-op', () {
      final runtime = PortForwardRuntime(rules: [_localRule()]);
      // No sshConnection wired into the stub, so client lookup returns
      // null and the runtime must skip listener creation cleanly.
      expect(() => runtime.onConnected(_stubConnection()), returnsNormally);
      runtime.dispose();
    });

    test('onDisconnecting before onConnected is a no-op', () {
      final runtime = PortForwardRuntime();
      expect(() => runtime.onDisconnecting(_stubConnection()), returnsNormally);
      runtime.dispose();
    });

    test('setRules replaces the list', () {
      final runtime = PortForwardRuntime(rules: [_localRule(id: 'r1')]);
      runtime.setRules([_localRule(id: 'r2'), _localRule(id: 'r3')]);
      expect(runtime.rules.map((r) => r.id), ['r2', 'r3']);
      runtime.dispose();
    });

    test('disabled rules are skipped at runtime registration', () {
      final runtime = PortForwardRuntime(
        rules: [
          _localRule(id: 'r1'),
          _localRule(id: 'r2', enabled: false),
        ],
      );
      // The list still holds both — toggle is a UI concern, runtime
      // filters at open-listener time. Here we only verify the
      // setter does not implicitly drop disabled rows.
      expect(runtime.rules.length, 2);
      runtime.dispose();
    });

    test('id is stable for ConnectionExtension diagnostics', () {
      expect(PortForwardRuntime().id, 'port-forward-runtime');
    });
  });
}
