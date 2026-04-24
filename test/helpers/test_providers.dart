/// Shared test fixture — common provider overrides for tests that
/// need to construct a [ProviderContainer] without spinning up real
/// path_provider / flutter_secure_storage / platform channels.
///
/// Usage:
///
/// ```dart
/// test('my controller does X', () {
///   final container = makeTestProviderContainer();
///   addTearDown(container.dispose);
///   final ctrl = SomeController(ref: Ref(container), ...);
///   // ...
/// });
/// ```
///
/// The factory ships sensible defaults for the providers that every
/// security / session / main-shell test needs to mock. Callers pass
/// additional `overrides` for anything specific to the scenario.
///
/// Design principle — default overrides are **no-ops that do not
/// hit the filesystem or any platform channel**. Tests that need
/// real persistence pass in a scratch [AppDatabase] via
/// `openTestDatabase()` + the corresponding `setDatabase` store
/// override; see `test/core/ssh/known_hosts_test.dart` for the
/// DB-backed pattern.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:letsflutssh/core/session/session_store.dart';
import 'package:letsflutssh/providers/session_provider.dart';

import 'fake_session_store.dart';

/// Construct a [ProviderContainer] with the most common overrides
/// already applied.
///
/// Accepts optional positional [extraOverrides] so the caller can
/// tack on scenario-specific mocks (keychain gate returns isConfigured
/// true / hardware vault isStored false / etc.) without repeating
/// the baseline each time.
///
/// Currently overrides:
/// - [sessionStoreProvider] — swapped for a [FakeSessionStore] by
///   default; pass `sessionStore:` to supply one pre-seeded with
///   test sessions.
///
/// Add more defaults here as tests prove them repeatedly useful —
/// the whole point of this fixture is to stop every new test from
/// re-writing the same mocks. Keep new defaults no-op / empty so
/// a test that didn't ask for a behaviour cannot be surprised by
/// one.
ProviderContainer makeTestProviderContainer({
  SessionStore? sessionStore,
  List<Override> extraOverrides = const [],
}) {
  return ProviderContainer(
    overrides: [
      sessionStoreProvider.overrideWithValue(
        sessionStore ?? FakeSessionStore(),
      ),
      ...extraOverrides,
    ],
  );
}
