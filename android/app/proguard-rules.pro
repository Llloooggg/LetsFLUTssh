# Keep androidx.biometric classes — R8 otherwise strips them and JNI FindClass fails with
# "class not found or linkage error" on devices that do have hardware biometrics.
-keep class androidx.biometric.** { *; }
-keep class com.google.android.gms.internal.** { *; }
