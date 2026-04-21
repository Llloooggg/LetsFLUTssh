#ifndef RUNNER_SESSION_LOCK_PLUGIN_H_
#define RUNNER_SESSION_LOCK_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

/// Bridge logind's `Session.Lock` D-Bus signal into the
/// `com.letsflutssh/session_lock` method channel. The Dart side
/// (`SessionLockListener`) subscribes and routes lock events into
/// the app's auto-lock path.
///
/// See linux/runner/session_lock_plugin.cc for the subscription
/// flow and rationale.

typedef struct _SessionLockPlugin SessionLockPlugin;

/// Registers the plugin against the given Flutter view and returns a
/// reference that the caller owns. Destroying the plugin unsubscribes
/// the D-Bus signal and disposes the channel.
SessionLockPlugin* session_lock_plugin_new(FlPluginRegistry* registry);

/// Free the plugin and drop its D-Bus subscription.
void session_lock_plugin_free(SessionLockPlugin* self);

G_END_DECLS

#endif  // RUNNER_SESSION_LOCK_PLUGIN_H_
