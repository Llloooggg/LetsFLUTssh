#include "session_lock_plugin.h"

#include <gio/gio.h>
#include <unistd.h>

#include <cstring>

/// Listens on systemd-logind's D-Bus `Session.Lock` signal and pumps
/// a `sessionLocked` method call into the Dart side on every fire.
///
/// systemd-logind emits `org.freedesktop.login1.Session.Lock` when
/// the user's desktop session transitions to a locked state — GNOME
/// Shell's lock-screen, i3lock + loginctl lock-session, KDE's
/// ksmserver lock, and the hardware-lock button all end up at the
/// same place. Subscribing to the D-Bus signal is the right answer
/// (vs polling `loginctl show-session` or scraping a screensaver
/// inhibitor): it fires exactly once per transition, costs nothing
/// when idle, and matches the behaviour every other app on the
/// desktop bus uses.
///
/// To keep the signal scoped to *our* user's session (a machine may
/// have multiple logged-in sessions — an SSH session, a GDM greeter,
/// a Wayland session — and we only care about the graphical one
/// that owns our window), the plugin asks logind's
/// `org.freedesktop.login1.Manager.GetSessionByPID(getpid())` for
/// the session object path and subscribes with that path as the
/// filter. Any Lock signal that fires on a different session is
/// ignored.
///
/// The subscription is torn down when the plugin is freed; logind
/// handles that cleanly via GDBus's unsubscribe path — no leftover
/// watcher process, no dangling file descriptor.

struct _SessionLockPlugin {
  GDBusConnection* bus;           // owned: g_object_ref'd
  FlMethodChannel* channel;       // owned: g_object_ref'd
  guint signal_subscription_id;   // 0 when not subscribed
  gchar* session_path;            // owned: g_free'd; NULL if not resolved
};

static const char kChannelName[] = "com.letsflutssh/session_lock";
static const char kLogindService[] = "org.freedesktop.login1";
static const char kManagerPath[] = "/org/freedesktop/login1";
static const char kManagerInterface[] = "org.freedesktop.login1.Manager";
static const char kSessionInterface[] = "org.freedesktop.login1.Session";

// Called from GDBus when a matching Lock signal fires on our
// scoped session path. We forward a fire-and-forget
// `sessionLocked` method call on the channel — the Dart side
// coalesces per-listener and runs the in-app lock flow.
static void on_lock_signal(GDBusConnection* connection, const gchar* sender,
                           const gchar* object_path,
                           const gchar* interface_name,
                           const gchar* signal_name, GVariant* parameters,
                           gpointer user_data) {
  (void)connection;
  (void)sender;
  (void)object_path;
  (void)interface_name;
  (void)signal_name;
  (void)parameters;
  SessionLockPlugin* self = static_cast<SessionLockPlugin*>(user_data);
  if (self->channel == nullptr) return;
  g_autoptr(FlValue) args = fl_value_new_null();
  fl_method_channel_invoke_method(self->channel, "sessionLocked", args, nullptr,
                                  nullptr, nullptr);
}

// Resolve the D-Bus session object path for the current PID so we
// subscribe with a path filter rather than firing on every session.
static gchar* resolve_session_path(GDBusConnection* bus) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      bus, kLogindService, kManagerPath, kManagerInterface, "GetSessionByPID",
      g_variant_new("(u)", static_cast<guint32>(getpid())),
      G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, 2000, nullptr, &error);
  if (reply == nullptr) {
    // Expected in several legitimate environments — WSL2/WSLg (no
    // logind session), headless CI, containers without a session
    // manager, or a user session that was reparented. We fall back
    // to an unscoped subscription below, so this is not an error.
    // Use g_debug so the log stays quiet on a normal launch without
    // hiding the detail from G_MESSAGES_DEBUG-instrumented runs.
    g_debug("session_lock: GetSessionByPID unavailable (%s) — using "
            "unscoped lock subscription",
            error != nullptr ? error->message : "(no error detail)");
    return nullptr;
  }
  const gchar* path = nullptr;
  g_variant_get(reply, "(&o)", &path);
  return g_strdup(path);
}

// The one method the channel takes from Dart: `start`. The Dart side
// calls it once to tell us to begin observing; we already installed
// the subscription on construction, so this is a success no-op.
static void on_method_call(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  (void)channel;
  (void)user_data;
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(fl_method_call_get_name(method_call), "start") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("session_lock: respond failed: %s",
              error != nullptr ? error->message : "(no error detail)");
  }
}

SessionLockPlugin* session_lock_plugin_new(FlPluginRegistry* registry) {
  SessionLockPlugin* self = g_new0(SessionLockPlugin, 1);

  g_autoptr(GError) bus_error = nullptr;
  self->bus = g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, &bus_error);
  if (self->bus == nullptr) {
    g_warning("session_lock: failed to open system bus: %s",
              bus_error != nullptr ? bus_error->message : "(no detail)");
    g_free(self);
    return nullptr;
  }

  self->session_path = resolve_session_path(self->bus);

  // Subscribe either path-scoped (preferred) or unscoped (fallback
  // — better to fire on every session than to miss the app's own
  // lock because GetSessionByPID failed on an unusual logind build).
  FlPluginRegistrar* registrar = fl_plugin_registry_get_registrar_for_plugin(
      registry, "com.letsflutssh.session_lock");
  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(messenger, kChannelName,
                                        FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, on_method_call, self,
                                            nullptr);

  self->signal_subscription_id = g_dbus_connection_signal_subscribe(
      self->bus, kLogindService, kSessionInterface, "Lock", self->session_path,
      nullptr, G_DBUS_SIGNAL_FLAGS_NONE, on_lock_signal, self, nullptr);

  return self;
}

void session_lock_plugin_free(SessionLockPlugin* self) {
  if (self == nullptr) return;
  if (self->signal_subscription_id != 0 && self->bus != nullptr) {
    g_dbus_connection_signal_unsubscribe(self->bus,
                                         self->signal_subscription_id);
    self->signal_subscription_id = 0;
  }
  g_clear_object(&self->channel);
  g_clear_object(&self->bus);
  g_clear_pointer(&self->session_path, g_free);
  g_free(self);
}
