//! Windows Biometric Framework — physical-unit count probe.
//!
//! Counts the biometric units the OS exposes (fingerprint
//! readers, IR cameras for Hello Face, iris scanners). Empty
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
//! Lives in `lfs_os_security` (not the FRB adapter) because
//! `lfs_core` is `unsafe_code = "forbid"` and every OS FFI
//! belongs in this crate alongside `apply_startup_hardening`,
//! `lock_memory`, `biometric_auth`, etc. The FRB shim is a
//! one-liner forwarding to [`count_units`].

/// Public probe surface. Returns the number of biometric units
/// reported by `WinBioEnumBiometricUnits` on Windows; `-1` on
/// every other target. `0` (zero units) is a real Windows result
/// distinct from the non-Windows sentinel.
pub fn count_units() -> i64 {
    inner::count()
}

#[cfg(not(target_os = "windows"))]
mod inner {
    /// Non-Windows shim — keeps the binding shape stable across
    /// platforms. Callers treat `-1` as "don't gate on this
    /// probe" so Linux / macOS / Android / iOS paths fall
    /// through to their existing availability logic.
    pub(super) fn count() -> i64 {
        -1
    }
}

#[cfg(target_os = "windows")]
mod inner {
    use libloading::Library;

    /// Bitmask passed to `WinBioEnumBiometricUnits`. Voice
    /// (0x04) is intentionally omitted — Hello does not surface
    /// it for app authentication on any SKU we ship to. Same
    /// factor set the historical Dart probe used.
    const WINBIO_TYPE_FINGERPRINT: u32 = 0x0000_0001;
    const WINBIO_TYPE_FACIAL_FEATURES: u32 = 0x0000_0002;
    const WINBIO_TYPE_IRIS: u32 = 0x0000_0008;
    const BIOMETRIC_FACTORS: u32 =
        WINBIO_TYPE_FINGERPRINT | WINBIO_TYPE_FACIAL_FEATURES | WINBIO_TYPE_IRIS;

    type EnumBiometricUnitsFn =
        unsafe extern "system" fn(u32, *mut *mut core::ffi::c_void, *mut usize) -> i32;
    type FreeFn = unsafe extern "system" fn(*mut core::ffi::c_void) -> i32;

    pub(super) fn count() -> i64 {
        // Loader, symbol resolution, and the FFI call all route
        // to `0` on any failure — the conservative "no biometric
        // hardware" classification is safer than enabling the
        // toggle against a ghost sensor.
        // SAFETY: every `unsafe` block is bounded — symbol
        // signatures match the Win32 ABI documented for
        // `WinBioEnumBiometricUnits` / `WinBioFree`. The schema
        // buffer's lifetime is owned by WinBio and freed via
        // `WinBioFree` before this function returns.
        let lib = match unsafe { Library::new("winbio.dll") } {
            Ok(l) => l,
            Err(_) => return 0,
        };

        let enum_units: libloading::Symbol<EnumBiometricUnitsFn> =
            // SAFETY: `Library::get` performs a dlsym/GetProcAddress against an `unsafe` symbol;
            // the returned `Symbol<T>` borrows from `lib` for the rest of the function and the
            // function pointer signature `T` must match the C ABI of the exported symbol (verified
            // against the Windows / Apple SDK header).
            match unsafe { lib.get(b"WinBioEnumBiometricUnits") } {
                Ok(s) => s,
                Err(_) => return 0,
            };
        // SAFETY: `Library::get` performs a dlsym/GetProcAddress against an `unsafe` symbol; the
        // returned `Symbol<T>` borrows from `lib` for the rest of the function and the function
        // pointer signature `T` must match the C ABI of the exported symbol (verified against the
        // Windows / Apple SDK header).
        let free_fn: libloading::Symbol<FreeFn> = match unsafe { lib.get(b"WinBioFree") } {
            Ok(s) => s,
            Err(_) => return 0,
        };

        let mut schemas: *mut core::ffi::c_void = core::ptr::null_mut();
        let mut count: usize = 0;
        // SAFETY: `enum_units` is the dynamically-loaded `WinBioEnumBiometricUnits` symbol; it
        // writes a +1-allocated unit array into `*schemas` and the count into `*count`, both
        // stack-local outputs we own.
        let hr = unsafe { enum_units(BIOMETRIC_FACTORS, &mut schemas, &mut count) };
        if !schemas.is_null() {
            // SAFETY: `free_fn` is the dynamically-loaded `WinBioFree` symbol; releasing the
            // buffer the matching `WinBioEnumBiometricUnits` allocated.
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn count_units_returns_without_panic() {
        // On Linux / macOS CI this is the `-1` shim path; on
        // Windows it loads winbio.dll. Either way: must return.
        let n = count_units();
        if cfg!(target_os = "windows") {
            assert!(n >= 0, "Windows path must return >= 0, got {n}");
        } else {
            assert_eq!(n, -1, "non-Windows shim must return -1");
        }
    }
}
