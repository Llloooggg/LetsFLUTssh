# Keep androidx.biometric classes — R8 otherwise strips them and JNI FindClass fails with
# "class not found or linkage error" on devices that do have hardware biometrics.
-keep class com.google.android.gms.internal.** { *; }
-keep class androidx.biometric.** { *; }
-keep interface androidx.biometric.** { *; }
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# Keep BiometricManager and BiometricPrompt specifically — these are the classes
# that JNI FindClass tries to resolve in lfs_os_security::android::biometric
-keep class androidx.biometric.BiometricManager
-keep class androidx.biometric.BiometricPrompt { *; }
-keep class androidx.biometric.BiometricPrompt$* { *; }
-keep class androidx.biometric.BiometricManager$* { *; }
