import 'dart:async' show runZonedGuarded;
import 'dart:io' show File, exit;
import 'dart:ui' show PlatformDispatcher;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'l10n/app_localizations.dart';
import 'core/config/config_store.dart';
import 'core/shortcut_registry.dart';
import 'core/deeplink/deeplink_handler.dart';
import 'core/single_instance/single_instance.dart';
import 'core/session/qr_codec.dart';
import 'core/db/database_opener.dart';
import 'core/security/aes_gcm.dart';
import 'core/security/master_password.dart';
import 'core/security/secure_key_storage.dart';
import 'core/security/security_level.dart';
import 'core/import/import_service.dart';
import 'features/session_manager/session_connect.dart';
import 'features/session_manager/session_edit_dialog.dart';
import 'features/settings/export_import.dart';
import 'widgets/app_dialog.dart';
import 'widgets/host_key_dialog.dart';
import 'widgets/passphrase_dialog.dart';
import 'widgets/security_setup_dialog.dart';
import 'widgets/unlock_dialog.dart';
import 'widgets/lfs_import_dialog.dart';
import 'widgets/cross_marquee_controller.dart';
import 'widgets/app_icon_button.dart';
import 'widgets/app_shell.dart';
import 'widgets/toast.dart';
import 'features/settings/settings_screen.dart';
import 'features/session_manager/session_panel.dart';
import 'features/tabs/tab_model.dart';
import 'features/workspace/workspace_controller.dart';
import 'features/workspace/workspace_node.dart';
import 'features/workspace/workspace_view.dart';
import 'providers/config_provider.dart';
import 'providers/connection_provider.dart';
import 'providers/key_provider.dart';
import 'providers/master_password_provider.dart';
import 'providers/security_provider.dart';
import 'providers/session_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/theme_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/update/update_service.dart';
import 'providers/update_provider.dart';
import 'providers/version_provider.dart';
import 'features/mobile/mobile_shell.dart';
import 'theme/app_theme.dart';
import 'utils/logger.dart';
import 'utils/platform.dart' as plat;
import 'utils/sanitize.dart';

/// Global navigator key for showing dialogs from non-UI contexts
/// (e.g., host key verification during SSH handshake).
final navigatorKey = GlobalKey<NavigatorState>();

/// Single-instance lock — kept alive for the process lifetime.
/// The OS releases the file lock automatically on exit (even on crash).
@visibleForTesting
SingleInstance? singleInstanceLock;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start logger init early — runs in parallel with config/lock I/O below.
  // Log path resolves in background; log() calls buffer to dev.log until ready.
  final loggerInit = AppLogger.instance.init();

  // Global error boundary — catch unhandled Flutter framework errors
  // (build, layout, paint errors — logged but don't show dialog)
  FlutterError.onError = (details) {
    final sanitizedMsg = sanitizeErrorMessage(details.exceptionAsString());
    AppLogger.instance.log(
      'FlutterError: $sanitizedMsg',
      name: 'ErrorBoundary',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  // Catch errors that escape the Flutter zone entirely (timers, isolate messages)
  PlatformDispatcher.instance.onError = (error, stack) {
    final sanitizedMsg = sanitizeErrorMessage(error.toString());
    AppLogger.instance.log(
      'Unhandled platform error: $sanitizedMsg',
      name: 'ErrorBoundary',
      error: error,
      stackTrace: stack,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        _showGlobalErrorDialog(ctx, error);
      }
    });
    return true;
  };

  // Replace the red error screen with a user-friendly widget
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

  AppLogger.instance.log('App starting', name: 'App');

  if (plat.isDesktopPlatform) {
    singleInstanceLock = SingleInstance();
    final acquired = await singleInstanceLock!.acquire();
    if (!acquired) {
      AppLogger.instance.log(
        'Another instance detected — showing blocker',
        name: 'App',
      );
      runApp(const _AlreadyRunningApp());
      return;
    }
  }

  // Load config before first frame to prevent light-theme flash.
  // The pre-loaded store is injected via override so ConfigNotifier.build()
  // reads the real config instead of defaults.
  final configStore = ConfigStore();
  final config = await configStore.load();
  await loggerInit; // ensure log path resolved before enabling file logging
  AppLogger.instance.setEnabled(config.enableLogging);

  // Wrap the entire app in runZonedGuarded to catch all async errors.
  // This catches errors from onPressed, Futures, streams, timers, etc.
  runZonedGuarded(
    () {
      runApp(
        ProviderScope(
          overrides: [configStoreProvider.overrideWithValue(configStore)],
          child: const LetsFLUTsshApp(),
        ),
      );
    },
    (error, stack) {
      final sanitizedMsg = sanitizeErrorMessage(error.toString());
      AppLogger.instance.log(
        'Unhandled async error: $sanitizedMsg',
        name: 'ErrorBoundary',
        error: error,
        stackTrace: stack,
      );
      // Show dialog after next frame — ensures Navigator is available
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          _showGlobalErrorDialog(ctx, error);
        }
      });
    },
  );
}

/// Shows a user-friendly error dialog for unhandled async errors.
/// Error is already logged by the global error handler — this just shows a brief message.
void _showGlobalErrorDialog(BuildContext context, Object error) {
  final errorType = error.runtimeType.toString();
  final loggingEnabled = AppLogger.instance.enabled;

  try {
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (ctx) {
        return AppDialog(
          title: 'Unexpected Error',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'An unexpected error occurred. The app will continue running.',
                style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fg),
              ),
              const SizedBox(height: 8),
              Text(
                loggingEnabled
                    ? 'Full details have been saved to the log file.'
                    : 'Enable logging in Settings to save error details.',
                style: TextStyle(
                  fontSize: AppFonts.xs,
                  color: AppTheme.fgFaint,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Error: $errorType',
                style: TextStyle(
                  fontSize: AppFonts.xxs,
                  color: AppTheme.fgFaint,
                  fontFamily: 'JetBrains Mono',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            if (!loggingEnabled)
              AppDialogAction.secondary(
                label: 'Enable Logging',
                onTap: () {
                  AppLogger.instance.setEnabled(true);
                  AppLogger.instance.log(
                    'Logging enabled after error: $errorType',
                    name: 'ErrorBoundary',
                  );
                  Navigator.of(ctx).pop();
                  Toast.show(
                    ctx,
                    message:
                        'Logging enabled — errors will be saved to log file',
                    level: ToastLevel.success,
                  );
                },
              ),
            AppDialogAction.primary(
              label: 'OK',
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        );
      },
    );
  } catch (e) {
    // If dialog fails to show, at least log it
    AppLogger.instance.log(
      'Failed to show error dialog: $e',
      name: 'ErrorBoundary',
    );
  }
}

class LetsFLUTsshApp extends ConsumerStatefulWidget {
  const LetsFLUTsshApp({super.key});

  @override
  ConsumerState<LetsFLUTsshApp> createState() => _LetsFLUTsshAppState();
}

class _LetsFLUTsshAppState extends ConsumerState<LetsFLUTsshApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _setupHostKeyCallbacks();
    _lifecycleListener = AppLifecycleListener(
      onRestart: _reloadSessions,
      onResume: _reloadSessions,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(appVersionProvider.notifier).load();
      await _initSecurity();
      await ref.read(sessionProvider.notifier).load();
      if (_credentialsWereReset) {
        _credentialsWereReset = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            Toast.show(
              ctx,
              message: S.of(ctx).credentialsReset,
              level: ToastLevel.warning,
            );
          }
        });
      }
      if (plat.isMobilePlatform) {
        AppLogger.instance.log('Initializing foreground service', name: 'App');
        ref.read(foregroundServiceProvider).init();
      }
      if (ref.read(configProvider).checkUpdatesOnStart) {
        AppLogger.instance.log('Checking for updates on start', name: 'App');
        ref.read(updateProvider.notifier).check();
      }
    });
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  void _reloadSessions() {
    AppLogger.instance.log('App resumed — reloading sessions', name: 'App');
    ref.read(sessionProvider.notifier).load();
  }

  /// True when the user chose "forgot password" — used to show a toast
  /// after sessions load (needs l10n context).
  bool _credentialsWereReset = false;

  /// Determine security level on startup.
  ///
  /// First launch is detected by the absence of any data: no master password
  /// salt, no keychain key, and no session files. In that case the
  /// [SecuritySetupDialog] wizard is shown.
  ///
  /// After resolving, injects the encryption key into all three stores
  /// (SessionStore, KeyStore, KnownHostsManager) and updates the global
  /// [securityStateProvider].
  Future<void> _initSecurity() async {
    final manager = ref.read(masterPasswordProvider);
    final keyStorage = ref.read(secureKeyStorageProvider);

    // 1. Master password — show unlock dialog.
    if (await manager.isEnabled()) {
      if (!mounted) return;
      final derivedKey = await _showUnlockDialog(manager);
      if (derivedKey != null) {
        _injectDatabase(key: derivedKey, level: SecurityLevel.masterPassword);
        AppLogger.instance.log('Master password unlocked', name: 'App');
      } else {
        _credentialsWereReset = true;
        _injectDatabase(); // Open DB without encryption after reset
        AppLogger.instance.log(
          'Master password reset — credentials cleared',
          name: 'App',
        );
      }
      return;
    }

    // 2. Keychain key exists — use it.
    final keychainKey = await keyStorage.readKey();
    if (keychainKey != null) {
      _injectDatabase(key: keychainKey, level: SecurityLevel.keychain);
      AppLogger.instance.log('Keychain key loaded', name: 'App');
      return;
    }

    // 3. Existing plaintext install — open DB without encryption.
    if (await _hasAnyData()) {
      _injectDatabase();
      AppLogger.instance.log('Plaintext mode (no encryption)', name: 'App');
      return;
    }

    // 4. First launch — show security setup wizard.
    await _firstLaunchSetup(manager, keyStorage);
  }

  /// Check whether any session/key data exists on disk.
  Future<bool> _hasAnyData() async {
    final dir = await getApplicationSupportDirectory();
    final files = ['sessions.json', 'sessions.enc', 'keys.json', 'keys.enc'];
    for (final name in files) {
      if (await File('${dir.path}/$name').exists()) return true;
    }
    return false;
  }

  /// First-launch flow: show wizard, configure security.
  Future<void> _firstLaunchSetup(
    MasterPasswordManager manager,
    SecureKeyStorage keyStorage,
  ) async {
    if (!mounted) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    final result = await SecuritySetupDialog.show(ctx, keyStorage: keyStorage);
    if (!mounted) return;

    if (result.masterPassword != null) {
      final key = await manager.enable(result.masterPassword!);
      _injectDatabase(key: key, level: SecurityLevel.masterPassword);
      AppLogger.instance.log(
        'First launch: master password enabled',
        name: 'App',
      );
    } else if (result.keychainAvailable) {
      final key = AesGcm.generateKey();
      final stored = await keyStorage.writeKey(key);
      if (stored) {
        _injectDatabase(key: key, level: SecurityLevel.keychain);
        AppLogger.instance.log(
          'First launch: keychain encryption enabled',
          name: 'App',
        );
      } else {
        _injectDatabase();
        AppLogger.instance.log(
          'First launch: keychain write failed, falling back to plaintext',
          name: 'App',
        );
      }
    } else {
      _injectDatabase();
      AppLogger.instance.log(
        'First launch: plaintext mode (no keychain, no master password)',
        name: 'App',
      );
    }
  }

  /// Open the database (with optional encryption) and inject into all stores.
  void _injectDatabase({
    Uint8List? key,
    SecurityLevel level = SecurityLevel.plaintext,
  }) {
    final db = openDatabase(encryptionKey: key);
    ref.read(sessionStoreProvider).setDatabase(db);
    ref.read(keyStoreProvider).setDatabase(db);
    ref.read(knownHostsProvider).setDatabase(db);
    if (key != null) {
      ref.read(securityStateProvider.notifier).set(level, key);
    }
  }

  /// Show unlock dialog using the navigator key context.
  ///
  /// Separated to avoid the `use_build_context_synchronously` lint — the
  /// context is obtained synchronously within this method, not across an
  /// async gap.
  Future<Uint8List?> _showUnlockDialog(MasterPasswordManager manager) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return Future.value(null);
    return UnlockDialog.show(ctx, manager: manager);
  }

  void _setupHostKeyCallbacks() {
    // Interactive passphrase prompt for encrypted SSH keys.
    final connManager = ref.read(connectionManagerProvider);
    connManager.onPassphraseRequired = (host, attempt) async {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return null;
      final result = await PassphraseDialog.show(
        ctx,
        host: host,
        attempt: attempt,
      );
      if (result == null) return null;
      return (passphrase: result.passphrase, remember: result.remember);
    };

    final knownHosts = ref.read(knownHostsProvider);
    knownHosts.onUnknownHost = (host, port, keyType, fingerprint) async {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return false;
      return HostKeyDialog.showNewHost(
        ctx,
        host: host,
        port: port,
        keyType: keyType,
        fingerprint: fingerprint,
      );
    };
    knownHosts.onHostKeyChanged = (host, port, keyType, fingerprint) async {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return false;
      return HostKeyDialog.showKeyChanged(
        ctx,
        host: host,
        port: port,
        keyType: keyType,
        fingerprint: fingerprint,
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final uiScale = ref.watch(configProvider.select((c) => c.uiScale));

    // Sync AppTheme brightness before building the widget tree
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    AppTheme.setBrightness(isDark ? Brightness.dark : Brightness.light);

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'LetsFLUTssh',
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      themeMode: themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeAnimationDuration: Duration.zero,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: mediaQuery.copyWith(textScaler: TextScaler.linear(uiScale)),
            child: child!,
          ),
        );
      },
      home: const MainScreen(),
    );
  }
}

/// Which content the desktop shell is currently showing.
enum ShellMode { sessions, settings }

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  final _deepLinkHandler = DeepLinkHandler();
  final _crossMarquee = CrossMarqueeController();
  final _reverseCrossMarquee = CrossMarqueeController();
  bool _updateDialogShown = false;
  bool _sidebarOpen = true;
  ShellMode _mode = ShellMode.sessions;
  int _settingsIndex = 0;
  final _workspaceKey = GlobalKey<WorkspaceViewState>();
  final _sessionPanelKey = GlobalKey<SessionPanelState>();
  final _sidebarActivated = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _setupDeepLinks();
    _listenForStartupUpdate();
  }

  @override
  void dispose() {
    _deepLinkHandler.dispose();
    _crossMarquee.dispose();
    _reverseCrossMarquee.dispose();
    _sidebarActivated.dispose();
    super.dispose();
  }

  void _listenForStartupUpdate() {
    ref.listenManual(updateProvider, (prev, next) => _handleUpdateState(next));
  }

  void _handleUpdateState(UpdateState next) {
    if (_updateDialogShown) return;
    if (next.status != UpdateStatus.updateAvailable || next.info == null) {
      return;
    }

    final skipped = ref.read(configProvider).skippedVersion;
    if (skipped != null && skipped == next.info!.latestVersion) return;

    // A newer version supersedes the previously skipped one — clear stale skip.
    if (skipped != null) {
      ref
          .read(configProvider.notifier)
          .update(
            (c) =>
                c.copyWith(behavior: c.behavior.copyWith(skippedVersion: null)),
          );
    }

    _updateDialogShown = true;
    final ctx = navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      _showUpdateDialog(ctx, next.info!);
    }
  }

  void _showUpdateDialog(BuildContext context, UpdateInfo info) {
    final hasAsset = info.assetUrl != null && plat.isDesktopPlatform;
    AppDialog.show(
      context,
      builder: (ctx) => AppDialog(
        title: S.of(ctx).updateAvailable,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S
                  .of(ctx)
                  .updateVersionAvailable(
                    info.latestVersion,
                    info.currentVersion,
                  ),
              style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
            ),
            if (info.changelog != null && info.changelog!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                S.of(ctx).releaseNotes,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AppFonts.md,
                  color: AppTheme.fg,
                ),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(
                    info.changelog!,
                    style: TextStyle(
                      fontSize: AppFonts.md,
                      color: AppTheme.fgDim,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          AppDialogAction.cancel(onTap: () => Navigator.pop(ctx)),
          AppDialogAction.secondary(
            label: S.of(ctx).skipThisVersion,
            onTap: () {
              Navigator.pop(ctx);
              ref
                  .read(configProvider.notifier)
                  .update(
                    (c) => c.copyWith(
                      behavior: c.behavior.copyWith(
                        skippedVersion: info.latestVersion,
                      ),
                    ),
                  );
            },
          ),
          _buildPrimaryUpdateAction(ctx, context, info, hasAsset),
        ],
      ),
    );
  }

  Widget _buildPrimaryUpdateAction(
    BuildContext ctx,
    BuildContext outerContext,
    UpdateInfo info,
    bool hasAsset,
  ) {
    if (hasAsset) {
      return AppDialogAction.primary(
        label: S.of(ctx).downloadAndInstall,
        onTap: () {
          Navigator.pop(ctx);
          ref.read(updateProvider.notifier).download(autoInstall: true);
        },
      );
    }
    return AppDialogAction.primary(
      label: S.of(ctx).openInBrowser,
      onTap: () async {
        Navigator.pop(ctx);
        final url = Uri.parse(info.releaseUrl);
        if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
          if (outerContext.mounted) {
            Clipboard.setData(ClipboardData(text: info.releaseUrl));
            Toast.show(
              outerContext,
              message: S.of(outerContext).couldNotOpenBrowser,
              level: ToastLevel.warning,
            );
          }
        }
      },
    );
  }

  void _setupDeepLinks() {
    _deepLinkHandler.onConnect = (config) {
      AppLogger.instance.log(
        'Deep link: connect to ${config.displayName}',
        name: 'DeepLink',
      );
      // Defer to next frame — when resuming from background the navigator
      // context may not be available yet on the current frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navigatorKey.currentContext;
        if (ctx == null) return;
        final manager = ref.read(connectionManagerProvider);
        final conn = manager.connectAsync(config, label: config.displayName);
        ref.read(workspaceProvider.notifier).addTerminalTab(conn);
      });
    };
    _deepLinkHandler.onLfsFileOpened = (filePath) {
      AppLogger.instance.log(
        'Deep link: LFS file opened — $filePath',
        name: 'DeepLink',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          _showLfsImportDialog(ctx, filePath);
        }
      });
    };
    _deepLinkHandler.onKeyFileOpened = (filePath) {
      AppLogger.instance.log(
        'Deep link: SSH key file received — $filePath',
        name: 'DeepLink',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          Toast.show(
            ctx,
            message: S.of(ctx).sshKeyReceived(filePath.split('/').last),
            level: ToastLevel.info,
          );
        }
      });
    };
    _deepLinkHandler.onQrImport = (data) {
      AppLogger.instance.log(
        'Deep link: QR import — '
        '${data.sessions.length} session(s), '
        '${data.emptyFolders.length} folder(s)',
        name: 'DeepLink',
      );
      _handleQrImport(data);
    };
    _deepLinkHandler.init();
  }

  @override
  Widget build(BuildContext context) {
    // Mobile: completely different navigation (bottom nav bar)
    if (plat.isMobilePlatform) {
      return const MobileShell();
    }

    final ws = ref.watch(workspaceProvider);

    return CallbackShortcuts(
      bindings: _buildKeyBindings(context, ws),
      child: Focus(
        autofocus: true,
        child: DropTarget(
          onDragDone: (details) => _handleLfsDrop(context, details),
          child: LayoutBuilder(
            builder: (context, constraints) =>
                _buildDesktopLayout(context, constraints, ws),
          ),
        ),
      ),
    );
  }

  Map<ShortcutActivator, VoidCallback> _buildKeyBindings(
    BuildContext context,
    WorkspaceState ws,
  ) {
    final notifier = ref.read(workspaceProvider.notifier);
    final focusedPanel = findPanel(ws.root, ws.focusedPanelId);
    final activeTab = focusedPanel?.activeTab;
    final reg = AppShortcutRegistry.instance;

    return reg.buildCallbackMap({
      AppShortcut.newSession: () => _newSession(context, ref),
      AppShortcut.closeTab: () {
        if (activeTab != null) {
          notifier.closeTab(ws.focusedPanelId, activeTab.id);
        }
      },
      AppShortcut.nextTab: () => _switchTab(ws, 1),
      AppShortcut.prevTab: () => _switchTab(ws, -1),
      AppShortcut.toggleSidebar: () {
        setState(() => _sidebarOpen = !_sidebarOpen);
      },
      AppShortcut.splitRight: () {
        if (activeTab != null) {
          notifier.duplicateTab(ws.focusedPanelId);
        }
      },
      AppShortcut.splitDown: () {
        if (activeTab != null) {
          notifier.copyToNewPanel(ws.focusedPanelId, Axis.vertical);
        }
      },
      AppShortcut.maximizePanel: () {
        notifier.toggleMaximizePanel(ws.focusedPanelId);
      },
      AppShortcut.openSettings: () => _toggleSettings(),
      AppShortcut.closeSettings: () {
        if (_mode == ShellMode.settings) {
          _toggleSettings();
        }
      },
    });
  }

  void _switchTab(WorkspaceState ws, int delta) {
    final panel = findPanel(ws.root, ws.focusedPanelId);
    if (panel != null && panel.tabs.length > 1) {
      final index =
          (panel.activeTabIndex + delta + panel.tabs.length) %
          panel.tabs.length;
      ref.read(workspaceProvider.notifier).selectTab(ws.focusedPanelId, index);
    }
  }

  void _handleLfsDrop(BuildContext context, DropDoneDetails details) {
    final lfsFiles = details.files
        .where((f) => f.path.endsWith('.lfs'))
        .toList();
    if (lfsFiles.isNotEmpty) {
      _showLfsImportDialog(context, lfsFiles.first.path);
    }
  }

  void _toggleSettings() {
    setState(() {
      _mode = _mode == ShellMode.settings
          ? ShellMode.sessions
          : ShellMode.settings;
    });
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    BoxConstraints constraints,
    WorkspaceState ws,
  ) {
    final isNarrow = constraints.maxWidth < 600;
    final inSettings = _mode == ShellMode.settings;
    final focusedPanel = findPanel(ws.root, ws.focusedPanelId);
    final activeTab = focusedPanel?.activeTab;

    final Widget sidebar;
    final Widget body;

    final sessionBody = WorkspaceView(
      key: _workspaceKey,
      crossMarquee: _crossMarquee,
      reverseCrossMarquee: _reverseCrossMarquee,
      sidebarActivated: _sidebarActivated,
      onActivated: () => _sessionPanelKey.currentState?.clearDesktopSelection(),
    );
    if (inSettings) {
      sidebar = SettingsSidebar(
        selectedIndex: _settingsIndex,
        onSelect: (i) => setState(() => _settingsIndex = i),
      );
      // Keep terminal tabs alive (Offstage) so SSH shells survive settings.
      body = Stack(
        children: [
          Offstage(child: sessionBody),
          SettingsContent(selectedIndex: _settingsIndex),
        ],
      );
    } else {
      sidebar = SessionPanel(
        key: _sessionPanelKey,
        onConnect: (session) => _connectSession(context, ref, session),
        onSftpConnect: (session) => _connectSessionSftp(context, ref, session),
        crossMarquee: _crossMarquee,
        reverseCrossMarquee: _reverseCrossMarquee,
        onActivated: () => _sidebarActivated.value++,
      );
      body = sessionBody;
    }

    return AppShell(
      toolbar: _buildToolbar(
        isNarrow: isNarrow,
        inSettings: inSettings,
        activeTab: activeTab,
      ),
      sidebar: sidebar,
      sidebarOpen: _sidebarOpen,
      useDrawer: isNarrow,
      body: body,
      statusBar: null,
    );
  }

  _Toolbar _buildToolbar({
    required bool isNarrow,
    required bool inSettings,
    required TabEntry? activeTab,
  }) {
    final tab = activeTab;
    final hasTab = !inSettings && tab != null;
    return _Toolbar(
      sidebarOpen: _sidebarOpen,
      onToggleSidebar: () => setState(() => _sidebarOpen = !_sidebarOpen),
      showMenuButton: isNarrow,
      isTerminalTab: hasTab,
      onDuplicateTab: hasTab
          ? () {
              final ws = ref.read(workspaceProvider);
              ref
                  .read(workspaceProvider.notifier)
                  .duplicateTab(ws.focusedPanelId);
            }
          : null,
      onDuplicateDown: hasTab
          ? () {
              final ws = ref.read(workspaceProvider);
              ref
                  .read(workspaceProvider.notifier)
                  .copyToNewPanel(ws.focusedPanelId, Axis.vertical);
            }
          : null,
      onSettings: _toggleSettings,
      inSettings: inSettings,
    );
  }

  Future<void> _connectSessionSftp(
    BuildContext context,
    WidgetRef ref,
    session,
  ) => SessionConnect.connectSftp(context, ref, session);

  Future<void> _connectSession(BuildContext context, WidgetRef ref, session) =>
      SessionConnect.connectTerminal(context, ref, session);

  Future<void> _newSession(BuildContext context, WidgetRef ref) async {
    final result = await SessionEditDialog.show(context);
    if (result == null || !context.mounted) return;
    switch (result) {
      case SaveResult(:final session, :final connect):
        await ref.read(sessionProvider.notifier).add(session);
        if (connect && context.mounted) {
          await SessionConnect.connectTerminal(context, ref, session);
        }
    }
  }

  Future<void> _handleQrImport(ExportPayloadData data) async {
    // Data operations don't need UI context — always execute, even when
    // the app is still resuming from background.
    for (final session in data.sessions) {
      await ref.read(sessionProvider.notifier).add(session);
    }
    for (final folder in data.emptyFolders) {
      await ref.read(sessionProvider.notifier).addEmptyFolder(folder);
    }
    AppLogger.instance.log(
      'QR import complete: ${data.sessions.length} session(s), '
      '${data.emptyFolders.length} folder(s)',
      name: 'App',
    );

    // Toast is best-effort — show when the navigator context is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Toast.show(
          ctx,
          message: S.of(ctx).importedSessionsViaQr(data.sessions.length),
          level: ToastLevel.success,
        );
      }
    });
  }

  Future<void> _showLfsImportDialog(
    BuildContext context,
    String filePath,
  ) async {
    AppLogger.instance.log(
      'LFS import started: ${filePath.split('/').last}',
      name: 'App',
    );
    final result = await LfsImportDialog.show(context, filePath: filePath);
    if (result == null || !context.mounted) return;

    // Show progress while PBKDF2 + decryption runs in isolate
    AppProgressDialog.show(context);

    try {
      final importResult = await ExportImport.import_(
        filePath: filePath,
        masterPassword: result.password,
        mode: result.mode,
        options: const ExportOptions(
          includeSessions: true,
          includeConfig: true,
          includeKnownHosts: true,
        ),
      );

      await _buildImportService().applyResult(importResult);

      // Import known hosts via the manager (handles encryption).
      if (importResult.knownHostsContent != null) {
        try {
          await ref
              .read(knownHostsProvider)
              .importFromString(importResult.knownHostsContent!);
        } catch (e) {
          AppLogger.instance.log(
            'Failed to import known_hosts from LFS: $e',
            name: 'App',
            error: e,
          );
          // Continue — known_hosts failure shouldn't fail entire import
        }
      }

      AppLogger.instance.log(
        'LFS import success: ${importResult.sessions.length} session(s)',
        name: 'App',
      );
      if (context.mounted) {
        Navigator.of(context).pop(); // close progress
        Toast.show(
          context,
          message: S.of(context).importedSessions(importResult.sessions.length),
          level: ToastLevel.success,
        );
      }
    } catch (e) {
      AppLogger.instance.log('LFS import failed: $e', name: 'App', error: e);
      if (context.mounted) {
        Navigator.of(context).pop(); // close progress
        Toast.show(
          context,
          message: S.of(context).importFailed(e.toString()),
          level: ToastLevel.error,
        );
      }
    }
  }

  ImportService _buildImportService() {
    final store = ref.read(sessionStoreProvider);
    return ImportService(
      addSession: (s) => ref.read(sessionProvider.notifier).add(s),
      addEmptyFolder: (f) => store.addEmptyFolder(f),
      deleteSession: (id) => ref.read(sessionProvider.notifier).delete(id),
      getSessions: () => ref.read(sessionProvider),
      applyConfig: (config) =>
          ref.read(configProvider.notifier).update((_) => config),
      getEmptyFolders: () => store.emptyFolders,
      restoreSnapshot: (sessions, folders) =>
          store.restoreSnapshot(sessions, folders),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final bool sidebarOpen;
  final VoidCallback onToggleSidebar;
  final bool showMenuButton;
  final bool isTerminalTab;
  final VoidCallback? onDuplicateTab;
  final VoidCallback? onDuplicateDown;
  final VoidCallback onSettings;
  final bool inSettings;

  const _Toolbar({
    required this.sidebarOpen,
    required this.onToggleSidebar,
    this.showMenuButton = false,
    this.isTerminalTab = false,
    this.onDuplicateTab,
    this.onDuplicateDown,
    required this.onSettings,
    this.inSettings = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 2),
        if (showMenuButton)
          AppIconButton(
            icon: Icons.menu,
            onTap: () => Scaffold.of(context).openDrawer(),
            tooltip: S.of(context).sessions,
            color: AppTheme.fgDim,
          )
        else
          AppIconButton(
            icon: sidebarOpen ? Icons.chevron_left : Icons.chevron_right,
            onTap: onToggleSidebar,
            tooltip: sidebarOpen
                ? S.of(context).hideSidebar
                : S.of(context).showSidebar,
          ),
        const Spacer(),
        if (isTerminalTab) ...[
          AppIconButton(
            icon: Icons.content_copy,
            onTap: onDuplicateTab,
            tooltip: S.of(context).duplicateTabShortcut,
          ),
          AppIconButton(
            icon: Icons.horizontal_split,
            onTap: onDuplicateDown,
            tooltip: S.of(context).duplicateDownShortcut,
          ),
          _Divider(),
        ] else
          _Divider(),
        AppIconButton(
          icon: inSettings ? Icons.arrow_back : Icons.settings,
          onTap: onSettings,
          tooltip: inSettings ? S.of(context).back : S.of(context).settings,
        ),
        const SizedBox(width: 2),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

/// Minimal app shown when another instance is already running.
class _AlreadyRunningApp extends StatelessWidget {
  const _AlreadyRunningApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block, size: 48, color: AppTheme.fgDim),
              const SizedBox(height: 16),
              Text(
                'Another instance of LetsFLUTssh is already running.',
                style: TextStyle(fontSize: AppFonts.lg),
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: () => exit(0), child: const Text('OK')),
            ],
          ),
        ),
      ),
    );
  }
}
