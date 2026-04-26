//! FRB adapter for `lfs_core::deeplink`. Synchronous because the
//! caller (Flutter `DeepLinkHandler.parseConnectUri`) is itself
//! sync — and the work is a small string parse, no IO.

/// FRB mirror of `lfs_core::deeplink::ConnectLink`. Same shape.
#[derive(Debug, Clone)]
pub struct DbConnectLink {
    pub host: String,
    pub port: u16,
    pub user: String,
}

impl From<lfs_core::deeplink::ConnectLink> for DbConnectLink {
    fn from(c: lfs_core::deeplink::ConnectLink) -> Self {
        Self {
            host: c.host,
            port: c.port,
            user: c.user,
        }
    }
}

/// Parse `uri` as a `letsflutssh://connect?host=…&user=…&port=…`
/// link. Returns `None` for any malformed / non-connect URI.
#[flutter_rust_bridge::frb(sync)]
pub fn parse_connect_uri(uri: String) -> Option<DbConnectLink> {
    lfs_core::deeplink::parse_connect_uri(&uri).map(DbConnectLink::from)
}
