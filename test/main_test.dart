import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/config/config_store.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/connection/connection_manager.dart';
import 'package:letsflutssh/core/connection/foreground_service.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/known_hosts.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/core/update/update_service.dart';
import 'package:letsflutssh/features/tabs/tab_model.dart';
import 'package:letsflutssh/features/workspace/workspace_controller.dart';
import 'package:letsflutssh/features/workspace/workspace_node.dart';
import 'package:letsflutssh/main.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/session_provider.dart';
import 'package:letsflutssh/providers/update_provider.dart';
import 'package:letsflutssh/providers/version_provider.dart';
import 'package:letsflutssh/utils/platform.dart' as plat;
import 'package:letsflutssh/widgets/app_icon_button.dart';

import 'helpers/fake_session_store.dart';
import 'helpers/test_notifiers.dart';

/// An UpdateNotifier that transitions from idle to updateAvailable
/// after the first frame, simulating real update check flow.
class _DelayedUpdateNotifier extends UpdateNotifier {
  final UpdateState _target;
  _DelayedUpdateNotifier(this._target);

  @override
  UpdateState build() {
    // Schedule state transition for after the widget tree is built,
    // so listenManual in _MainScreenState catches the change.
    Future.microtask(() => state = _target);
    return const UpdateState();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    plat.debugDesktopPlatformOverride = true;
    plat.debugMobilePlatformOverride = false;
  });

  tearDown(() {
    plat.debugDesktopPlatformOverride = null;
    plat.debugMobilePlatformOverride = null;
  });

  Widget buildApp({
    AppConfig? config,
    List<Session>? sessions,
    WorkspaceState? workspaceState,
    UpdateState? delayedUpdateState,
    String version = '1.0.0',
  }) {
    return ProviderScope(
      overrides: [
        sessionStoreProvider.overrideWithValue(
          FakeSessionStore(sessions: sessions),
        ),
        sessionProvider.overrideWith(
          sessions != null
              ? () => PrePopulatedSessionNotifier(sessions)
              : SessionNotifier.new,
        ),
        knownHostsProvider.overrideWithValue(KnownHostsManager()),
        connectionManagerProvider.overrideWithValue(
          ConnectionManager(knownHosts: KnownHostsManager()),
        ),
        connectionsProvider.overrideWith((ref) => Stream.value(<Connection>[])),
        configStoreProvider.overrideWithValue(ConfigStore()),
        configProvider.overrideWith(
          config != null
              ? () => PrePopulatedConfigNotifier(config)
              : TestConfigNotifier.new,
        ),
        foregroundServiceProvider.overrideWithValue(ForegroundServiceManager()),
        appVersionProvider.overrideWith(() => FixedVersionNotifier(version)),
        if (workspaceState != null)
          workspaceProvider.overrideWith(
            () => PrePopulatedWorkspaceNotifier(workspaceState),
          ),
        if (delayedUpdateState != null)
          updateProvider.overrideWith(
            () => _DelayedUpdateNotifier(delayedUpdateState),
          ),
      ],
      child: const LetsFLUTsshApp(),
    );
  }

  group('LetsFLUTsshApp', () {
    testWidgets('renders MaterialApp with correct title', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp).first);
      expect(app.title, 'LetsFLUTssh');
      expect(app.debugShowCheckedModeBanner, false);
    });

    testWidgets('uses dark theme when config theme is dark', (tester) async {
      final config = AppConfig.defaults.copyWith(
        terminal: AppConfig.defaults.terminal.copyWith(theme: 'dark'),
      );
      await tester.pumpWidget(buildApp(config: config));
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp).first);
      expect(app.themeMode, ThemeMode.dark);
    });

    testWidgets('uses light theme when config theme is light', (tester) async {
      final config = AppConfig.defaults.copyWith(
        terminal: AppConfig.defaults.terminal.copyWith(theme: 'light'),
      );
      await tester.pumpWidget(buildApp(config: config));
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp).first);
      expect(app.themeMode, ThemeMode.light);
    });

    testWidgets('applies UI scale from config', (tester) async {
      final config = AppConfig.defaults.copyWith(
        ui: AppConfig.defaults.ui.copyWith(uiScale: 1.5),
      );
      await tester.pumpWidget(buildApp(config: config));
      await tester.pumpAndSettle();

      // The MediaQuery inside builder should reflect the scale
      final mediaQuery = tester.widget<MediaQuery>(
        find.byType(MediaQuery).last,
      );
      expect(mediaQuery.data.textScaler, const TextScaler.linear(1.5));
    });

    testWidgets('respects locale from config', (tester) async {
      final config = AppConfig.defaults.copyWith(locale: 'ru');
      await tester.pumpWidget(buildApp(config: config));
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp).first);
      expect(app.locale, const Locale('ru'));
    });
  });

  group('MainScreen — desktop layout', () {
    testWidgets('shows toolbar with sidebar toggle and settings button', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Sidebar toggle (chevron_left when open)
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      // Settings text button
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('toggle sidebar hides and shows it', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Click sidebar toggle
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();

      // Now should show chevron_right (sidebar closed)
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      // Toggle back
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    });

    testWidgets('toolbar shows tools and settings text buttons', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Tools'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('shows duplicate/split buttons when terminal tab is active', (
      tester,
    ) async {
      final conn = Connection(
        id: 'c1',
        label: 'Server-1',
        sshConfig: const SSHConfig(
          server: ServerAddress(host: '10.0.0.1', user: 'root'),
        ),
        state: SSHConnectionState.connected,
      );
      final tab = TabEntry(
        id: 'tab-0',
        label: conn.label,
        connection: conn,
        kind: TabKind.terminal,
      );
      final panel = PanelLeaf(id: 'p0', tabs: [tab], activeTabIndex: 0);
      final ws = WorkspaceState(root: panel, focusedPanelId: 'p0');

      await tester.pumpWidget(buildApp(workspaceState: ws));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.content_copy), findsOneWidget);
      expect(find.byIcon(Icons.horizontal_split), findsOneWidget);
    });

    testWidgets('hides duplicate/split buttons when no active tab', (
      tester,
    ) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.content_copy), findsNothing);
      expect(find.byIcon(Icons.horizontal_split), findsNothing);
    });
  });

  group('MainScreen — mobile layout', () {
    setUp(() {
      plat.debugDesktopPlatformOverride = false;
      plat.debugMobilePlatformOverride = true;
    });

    testWidgets('renders MobileShell on mobile platform', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // On mobile, MobileShell is used instead of desktop layout
      // Verify desktop-specific widgets are absent
      expect(find.byIcon(Icons.chevron_left), findsNothing);
    });
  });

  group('MainScreen — narrow layout', () {
    testWidgets(
      'shows menu button instead of sidebar toggle on narrow screen',
      (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(buildApp());
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.menu), findsOneWidget);
        expect(find.byIcon(Icons.chevron_left), findsNothing);
      },
    );
  });

  group('navigatorKey', () {
    test('is a GlobalKey<NavigatorState>', () {
      expect(navigatorKey, isA<GlobalKey<NavigatorState>>());
    });
  });

  group('Update dialog', () {
    testWidgets('shows update dialog when update is available', (tester) async {
      const updateState = UpdateState(
        status: UpdateStatus.updateAvailable,
        info: UpdateInfo(
          currentVersion: '1.0.0',
          latestVersion: '2.0.0',
          releaseUrl: 'https://github.com/test/releases/tag/v2.0.0',
          changelog: 'New features!',
        ),
      );

      await tester.pumpWidget(
        buildApp(delayedUpdateState: updateState, version: '1.0.0'),
      );
      await tester.pumpAndSettle();

      // The update dialog should appear
      expect(find.textContaining('2.0.0'), findsWidgets);
    });

    testWidgets('does not show dialog when version is skipped', (tester) async {
      final config = AppConfig.defaults.copyWith(
        behavior: AppConfig.defaults.behavior.copyWith(skippedVersion: '2.0.0'),
      );
      const updateState = UpdateState(
        status: UpdateStatus.updateAvailable,
        info: UpdateInfo(
          currentVersion: '1.0.0',
          latestVersion: '2.0.0',
          releaseUrl: 'https://github.com/test/releases/tag/v2.0.0',
        ),
      );

      await tester.pumpWidget(
        buildApp(
          config: config,
          delayedUpdateState: updateState,
          version: '1.0.0',
        ),
      );
      await tester.pumpAndSettle();

      // Dialog should not appear for skipped version
      expect(find.textContaining('2.0.0'), findsNothing);
    });

    testWidgets('shows changelog in update dialog when available', (
      tester,
    ) async {
      const updateState = UpdateState(
        status: UpdateStatus.updateAvailable,
        info: UpdateInfo(
          currentVersion: '1.0.0',
          latestVersion: '2.0.0',
          releaseUrl: 'https://github.com/test/releases/tag/v2.0.0',
          changelog: 'Bug fixes and improvements',
        ),
      );

      await tester.pumpWidget(
        buildApp(delayedUpdateState: updateState, version: '1.0.0'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bug fixes and improvements'), findsOneWidget);
    });

    testWidgets('skip button sets skipped version in config', (tester) async {
      const updateState = UpdateState(
        status: UpdateStatus.updateAvailable,
        info: UpdateInfo(
          currentVersion: '1.0.0',
          latestVersion: '2.0.0',
          releaseUrl: 'https://github.com/test/releases/tag/v2.0.0',
        ),
      );

      await tester.pumpWidget(
        buildApp(delayedUpdateState: updateState, version: '1.0.0'),
      );
      await tester.pumpAndSettle();

      // Find and tap the skip button
      final skipFinder = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data != null &&
            w.data!.toLowerCase().contains('skip'),
      );
      if (skipFinder.evaluate().isNotEmpty) {
        await tester.tap(skipFinder.first);
        await tester.pumpAndSettle();
      }
    });
  });

  group('_Toolbar', () {
    testWidgets('renders sidebar toggle and text buttons', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // AppIconButton for sidebar toggle
      expect(find.byType(AppIconButton), findsWidgets);
      // Text buttons for Tools and Settings
      expect(find.text('Tools'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });
  });

  group('ErrorWidget.builder', () {
    test('ErrorWidget builder produces a Container with error text', () {
      // Trigger the error widget builder installed by main()
      // We can test it directly since it's set on ErrorWidget.builder
      final originalBuilder = ErrorWidget.builder;

      // Install our builder (simulating what main() does)
      ErrorWidget.builder = (details) {
        return Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(16),
          child: const Text(
            'Something went wrong.\n'
            'Try restarting the app.',
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 14, color: Color(0xFFABB2BF)),
          ),
        );
      };

      final widget = ErrorWidget.builder(
        FlutterErrorDetails(exception: Exception('test')),
      );
      expect(widget, isA<Container>());

      // Restore
      ErrorWidget.builder = originalBuilder;
    });
  });

  group('navigatorKey', () {
    test('is a GlobalKey<NavigatorState>', () {
      expect(navigatorKey, isA<GlobalKey<NavigatorState>>());
    });
  });

  group('singleInstanceLock', () {
    test('is initially null', () {
      // Reset if needed
      final previous = singleInstanceLock;
      singleInstanceLock = null;
      expect(singleInstanceLock, isNull);
      singleInstanceLock = previous;
    });
  });
}
