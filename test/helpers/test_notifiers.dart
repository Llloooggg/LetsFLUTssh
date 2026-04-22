import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/features/workspace/workspace_controller.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/providers/update_provider.dart';
import 'package:letsflutssh/providers/version_provider.dart';
import 'package:letsflutssh/core/session/session.dart';

/// A ConfigNotifier that returns defaults without touching disk.
class TestConfigNotifier extends ConfigNotifier {
  @override
  AppConfig build() => AppConfig.defaults;
}

/// A ConfigNotifier subclass that starts with a custom initial config.
class PrePopulatedConfigNotifier extends ConfigNotifier {
  final AppConfig _initialConfig;
  PrePopulatedConfigNotifier(this._initialConfig);

  @override
  AppConfig build() {
    super.build();
    state = _initialConfig;
    return state;
  }
}

/// A SessionNotifier subclass that starts with pre-populated sessions.
class PrePopulatedSessionNotifier extends SessionNotifier {
  final List<Session> _initialSessions;
  PrePopulatedSessionNotifier(this._initialSessions);

  @override
  List<Session> build() {
    super.build();
    state = _initialSessions;
    return state;
  }
}

/// [SessionsLoadingNotifier] that reports "already loaded" on build.
/// `sessionsLoadingProvider` defaults to `true` for the production
/// cold-start path — tests that mount `SessionPanel` should include
/// this override (or its `.overrideWith` shorthand) so the sidebar
/// paints the tree immediately instead of the blank placeholder.
class IdleSessionsLoadingNotifier extends SessionsLoadingNotifier {
  @override
  bool build() => false;
}

/// A WorkspaceNotifier that starts with a pre-built state.
class PrePopulatedWorkspaceNotifier extends WorkspaceNotifier {
  final WorkspaceState _initialState;
  PrePopulatedWorkspaceNotifier(this._initialState);

  @override
  WorkspaceState build() => _initialState;
}

/// An UpdateNotifier subclass that starts with a custom initial state.
class PrePopulatedUpdateNotifier extends UpdateNotifier {
  final UpdateState _initial;
  PrePopulatedUpdateNotifier(this._initial);

  @override
  UpdateState build() {
    super.build();
    state = _initial;
    return state;
  }
}

/// An AppVersionNotifier that returns a fixed version string.
class FixedVersionNotifier extends AppVersionNotifier {
  final String _version;
  FixedVersionNotifier(this._version);

  @override
  String build() => _version;
}
