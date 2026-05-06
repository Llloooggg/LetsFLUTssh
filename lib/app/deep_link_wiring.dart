import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/deeplink/deeplink_handler.dart';
import '../features/workspace/workspace_controller.dart';
import '../l10n/app_localizations.dart';
import '../providers/connection_provider.dart';
import '../utils/logger.dart';
import '../widgets/toast.dart';
import 'import_flow.dart';
import 'navigator_key.dart';

/// Process-wide deep-link handler. Lives in a provider so the
/// pre-FRB `_MainScreenState.initState` can register callbacks
/// without firing `getInitialLink()` (which would dispatch through
/// FRB before `_initRustCoreOrFatal` ran), while
/// `_LetsFLUTsshAppState._bootstrap` activates the same instance via
/// [activateDeepLinks] AFTER Rust is up. Single instance per
/// process — disposing happens at app exit.
final deepLinkHandlerProvider = Provider<DeepLinkHandler>((_) {
  return DeepLinkHandler();
});

/// Bind every callback on [handler] to the app's post-frame
/// plumbing. Pure-Dart wiring — does NOT call `handler.init()`,
/// which is deferred to [activateDeepLinks] post-FRB-init so a
/// cold-start `letsflutssh://` URL or `.lfs` file does not race
/// `_initRustCoreOrFatal` (the dispatch goes through Rust).
///
/// Each callback defers to `addPostFrameCallback` before reading
/// `navigatorKey.currentContext` — when the deep link arrives while
/// the app is resuming from background the navigator context isn't
/// mounted on the current frame yet, and reading it would return
/// null. Logging on every branch so a user hitting a
/// `letsflutssh://` link has a greppable trace of which callback
/// fired.
///
/// Moved out of `_MainScreenState` so the state class keeps its
/// focus on shell lifecycle; this module owns only the deep-link
/// surface area (connect, LFS open, key-file open, QR import,
/// version-too-new).
void wireDeepLinks(DeepLinkHandler handler, WidgetRef ref) {
  handler.onConnect = (config) {
    AppLogger.instance.log(
      'Deep link: connect to ${config.displayName}',
      name: 'DeepLink',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      final manager = ref.read(connectionsProvider.notifier);
      final conn = manager.connectAsync(config, label: config.displayName);
      ref.read(workspaceProvider.notifier).addTerminalTab(conn);
    });
  };
  handler.onLfsFileOpened = (filePath) {
    AppLogger.instance.log(
      'Deep link: LFS file opened — $filePath',
      name: 'DeepLink',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        showLfsImportDialog(ctx, ref, filePath);
      }
    });
  };
  handler.onKeyFileOpened = (filePath) {
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
  handler.onQrImport = (source) {
    final preview = source.preview;
    AppLogger.instance.log(
      'Deep link: QR import — '
      '${preview.sessionCount} session(s), '
      '${preview.emptyFoldersCount} folder(s)',
      name: 'DeepLink',
    );
    handleQrImport(ref, source);
  };
  handler.onQrImportVersionTooNew = (found, supported) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Toast.show(
          ctx,
          message: S.of(ctx).errLfsUnsupportedVersion(found, supported),
          level: ToastLevel.warning,
        );
      }
    });
  };
}

/// Fire the handler's `init()` — drains the cold-launch
/// `getInitialLink()` (which dispatches through Rust) and
/// subscribes to the warm-start URI stream. Called from
/// `_LetsFLUTsshAppState._bootstrap` AFTER `_initRustCoreOrFatal`
/// so a cold-launch via `letsflutssh://` or a double-clicked
/// `.lfs` file never races the FRB load.
Future<void> activateDeepLinks(DeepLinkHandler handler) async {
  await handler.init();
}
