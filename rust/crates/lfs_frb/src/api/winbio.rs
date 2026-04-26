//! Windows Biometric Framework probe over the FRB boundary.
//!
//! Mirrors `lib/core/security/windows/WinBioProbe`. Counts the
//! physical biometric units the OS exposes — fingerprint
//! readers, IR cameras for Hello Face, iris scanners. Empty
//! count is the ground truth that the biometric-unlock UI must
//! refuse to light up regardless of what `UserConsentVerifier`
//! claims (it returns "available" when Hello is configured in
//! any form, including a plain PIN with no sensor attached).
//!
//! Returns `-1` on non-Windows hosts so the caller's
//! tier-availability probe stays a single integer surface
//! regardless of the platform the build runs on. The real FFI
//! lives behind a `cfg(target_os = "windows")` gate; on every
//! other target the function compiles to a constant-`-1` stub.
//!
//! The FFI is on `lfs_frb` rather than `lfs_core` because
//! `lfs_core` has `unsafe_code = "forbid"` at the crate level.
//! Adapter code (FRB / future Tauri) is the natural home for
//! the unavoidable FFI surface.

#[flutter_rust_bridge::frb(sync)]
pub fn winbio_count_units() -> i64 {
    inner::count()
}

#[cfg(not(target_os = "windows"))]
pub mod inner {
    /// Non-Windows shim — keeps the FRB binding shape stable
    /// across platforms. The Dart caller treats `-1` as
    /// "don't gate on this probe" so the Linux / macOS /
    /// Android / iOS paths fall through to their existing
    /// availability logic.
    pub fn count() -> i64 {
        -1
    }
}

#[cfg(target_os = "windows")]
pub mod inner {
    use libloading::Library;

    /// Bitmask passed to `WinBioEnumBiometricUnits`. Voice
    /// (0x04) is intentionally omitted — Hello does not
    /// surface it for app authentication on any SKU we ship
    /// to. Same factor set the Dart probe uses.
    const WINBIO_TYPE_FINGERPRINT: u32 = 0x0000_0001;
    const WINBIO_TYPE_FACIAL_FEATURES: u32 = 0x0000_0002;
    const WINBIO_TYPE_IRIS: u32 = 0x0000_0008;
    const BIOMETRIC_FACTORS: u32 =
        WINBIO_TYPE_FINGERPRINT | WINBIO_TYPE_FACIAL_FEATURES | WINBIO_TYPE_IRIS;

    type EnumBiometricUnitsFn =
        unsafe extern "system" fn(u32, *mut *mut core::ffi::c_void, *mut usize) -> i32;
    type FreeFn = unsafe extern "system" fn(*mut core::ffi::c_void) -> i32;

    pub fn count() -> i64 {
        // Loader, symbol resolution, and the FFI call all
        // route to `0` on any failure — the conservative
        // "no biometric hardware" classification is safer
        // than enabling the toggle against a ghost sensor.
        // SAFETY: every `unsafe` block is bounded — symbol
        // signatures match the Win32 ABI documented for
        // `WinBioEnumBiometricUnits` / `WinBioFree`. The
        // schema buffer's lifetime is owned by WinBio and
        // freed via `WinBioFree` before this function returns.
        let lib = match unsafe { Library::new("winbio.dll") } {
            Ok(l) => l,
            Err(_) => return 0,
        };

        let enum_units: libloading::Symbol<EnumBiometricUnitsFn> =
            match unsafe { lib.get(b"WinBioEnumBiometricUnits") } {
                Ok(s) => s,
                Err(_) => return 0,
            };
        let free_fn: libloading::Symbol<FreeFn> = match unsafe { lib.get(b"WinBioFree") } {
            Ok(s) => s,
            Err(_) => return 0,
        };

        let mut schemas: *mut core::ffi::c_void = core::ptr::null_mut();
        let mut count: usize = 0;
        let hr = unsafe { enum_units(BIOMETRIC_FACTORS, &mut schemas, &mut count) };
        if !schemas.is_null() {
            unsafe {
                let _ = free_fn(schemas);
            }
        }
        if hr != 0 {
            return 0;
        }
        count as i64
    }
}
