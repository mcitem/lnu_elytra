package com.mcitem.lnu_elytra

import android.content.Context
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Flutter plugin that initializes the Rust-side Android NDK context.
 *
 * `System.loadLibrary` is called in the companion-object `init` block,
 * which loads `librust_lib_lnu_elytra.so` before any Dart code runs.
 *
 * On engine attach, the application [Context] is forwarded to Rust via
 * the JNI function `Java_com_mcitem_lnu_1elytra_MyPlugin_init_1android`,
 * which stores it for `rustls-platform-verifier` to use in TLS
 * certificate verification.
 *
 * See: https://github.com/mcitem/lnu_elytra (flutter_rust_bridge Android NDK docs)
 */
class MyPlugin : FlutterPlugin, MethodCallHandler {

    companion object {
        init {
            System.loadLibrary("rust_lib_lnu_elytra")
        }
    }

    /** Forwarded to Rust; the JNI side captures the JavaVM and application Context. */
    external fun init_android(ctx: Context)

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        init_android(binding.applicationContext)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        result.notImplemented()
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {}
}
