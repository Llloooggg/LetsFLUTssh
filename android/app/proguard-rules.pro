# The Rust security layer resolves these classes BY NAME at runtime
# through JNI; R8 cannot see those lookups and would otherwise strip
# or rename them even when they are reachable. Keep rules below pin
# every name-resolved surface.
#
# androidx.biometric.* — BiometricManager / BiometricPrompt /
# PromptInfo.Builder, looked up via jni_helpers::load_class.
-keep class androidx.biometric.** { *; }

# Keep the Kotlin glue classes the Rust side resolves BY NAME at
# runtime — via loadClass through the captured app ClassLoader
# (LfsBiometricCallback, KeystoreSshSigner) or via JNI external-fun
# binding derived from the runtime class name (LfsJniBootstrap).
# R8 renaming any of them breaks the lookup with no build-time error.
-keep class com.llloooggg.letsflutssh.LfsBiometricCallback { *; }
-keep class com.llloooggg.letsflutssh.LfsKeystoreSignCallback { *; }
-keep class com.llloooggg.letsflutssh.LfsJniBootstrap { *; }
-keep class com.llloooggg.letsflutssh.KeystoreSshSigner { *; }

# Keep ProGuard attributes
-keepattributes *Annotation*,InnerClasses,Signature,EnclosingMethod

# Suppress warnings for androidx.biometric (safe — we explicitly keep the classes above)
-dontwarn androidx.biometric.**
