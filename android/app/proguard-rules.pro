# Keep androidx.biometric classes — R8 otherwise strips them and JNI FindClass fails with
# "class not found or linkage error" on devices that do have hardware biometrics.
# R8 requires explicit keep rules for classes loaded via JNI FindClass —
# the generic -keep class androidx.biometric.** { *; } is not enough because
# R8 cannot statically resolve the JNI dependency.

# Keep all androidx.biometric classes and their members
-keep class androidx.biometric.BiometricManager { *; }
-keep class androidx.biometric.BiometricPrompt { *; }
-keep class androidx.biometric.BiometricPrompt$* { *; }
-keep class androidx.biometric.BiometricManager$* { *; }
-keep class androidx.biometric.BiometricResult { *; }
-keep class androidx.biometric.BiometricPrompt$AuthenticationResult { *; }
-keep class androidx.biometric.BiometricPrompt$PromptInfo { *; }
-keep class androidx.biometric.BiometricPrompt$PromptInfo$* { *; }
-keep class androidx.biometric.BiometricManager$* { *; }
-keep class androidx.biometric.** { *; }

# Keep the LfsBiometricCallback Kotlin adapter
-keep class com.llloooggg.letsflutssh.LfsBiometricCallback { *; }
-keep class com.llloooggg.letsflutssh.LfsKeystoreSignCallback { *; }

# Keep ProGuard attributes
-keepattributes *Annotation*,InnerClasses,Signature,EnclosingMethod

# Suppress warnings for androidx.biometric (safe — we explicitly keep the classes above)
-dontwarn androidx.biometric.**
