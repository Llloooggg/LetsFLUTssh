/// Unit tests extracted from fido2/brokers.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

fn av(os: Os, broker: bool, hid: bool, prefer_hid: bool) -> Availability {
    Availability {
        broker,
        direct_hid: hid,
        prefer_direct_hid: prefer_hid,
        os,
    }
}

#[test]
fn linux_always_direct_hid_when_available() {
    assert_eq!(
        select_transport(av(Os::Linux, false, true, false)),
        Transport::DirectHid
    );
    assert_eq!(
        select_transport(av(Os::Linux, true, true, false)),
        Transport::DirectHid
    );
    assert_eq!(
        select_transport(av(Os::Linux, true, true, true)),
        Transport::DirectHid
    );
}

#[test]
fn linux_none_when_hid_unavailable() {
    // Linux runner without udev rules or libudev — nothing to
    // fall back to.
    assert_eq!(
        select_transport(av(Os::Linux, false, false, false)),
        Transport::None
    );
}

#[test]
fn windows_prefers_broker_then_hid() {
    assert_eq!(
        select_transport(av(Os::Windows, true, true, false)),
        Transport::Broker
    );
    assert_eq!(
        select_transport(av(Os::Windows, false, true, false)),
        Transport::DirectHid
    );
    assert_eq!(
        select_transport(av(Os::Windows, true, false, false)),
        Transport::Broker
    );
    assert_eq!(
        select_transport(av(Os::Windows, false, false, false)),
        Transport::None
    );
}

#[test]
fn windows_prefer_hid_toggle_overrides_broker() {
    // Settings toggle on + HID reachable → bypass broker.
    assert_eq!(
        select_transport(av(Os::Windows, true, true, true)),
        Transport::DirectHid
    );
}

#[test]
fn windows_prefer_hid_toggle_ignored_when_hid_missing() {
    // Toggle on but HID unreachable → fall through to broker
    // (better than locking the user out).
    assert_eq!(
        select_transport(av(Os::Windows, true, false, true)),
        Transport::Broker
    );
}

#[test]
fn macos_same_ladder_as_windows() {
    assert_eq!(
        select_transport(av(Os::Macos, true, true, false)),
        Transport::Broker
    );
    assert_eq!(
        select_transport(av(Os::Macos, false, true, false)),
        Transport::DirectHid
    );
    assert_eq!(
        select_transport(av(Os::Macos, true, true, true)),
        Transport::DirectHid
    );
}

#[test]
fn ios_broker_or_none() {
    assert_eq!(
        select_transport(av(Os::Ios, true, false, false)),
        Transport::Broker
    );
    // The HID column is irrelevant — iOS has no USB-HID
    // fallback at any rung.
    assert_eq!(
        select_transport(av(Os::Ios, false, true, false)),
        Transport::None
    );
    assert_eq!(
        select_transport(av(Os::Ios, false, false, true)),
        Transport::None
    );
}

#[test]
fn android_broker_or_none() {
    assert_eq!(
        select_transport(av(Os::Android, true, false, false)),
        Transport::Broker
    );
    assert_eq!(
        select_transport(av(Os::Android, false, true, false)),
        Transport::None
    );
}

#[test]
fn prefer_direct_hid_round_trips_through_atomic() {
    let start = prefer_direct_hid();
    set_prefer_direct_hid(true);
    assert!(prefer_direct_hid());
    set_prefer_direct_hid(false);
    assert!(!prefer_direct_hid());
    set_prefer_direct_hid(start);
}
