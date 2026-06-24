# Keep rustls-platform-verifier Kotlin component.
# It is called from Rust via JNI so R8 sees it as unused code.
-keep, includedescriptorclasses class org.rustls.platformverifier.** { *; }
-keepclassmembers class org.rustls.platformverifier.** { *; }
