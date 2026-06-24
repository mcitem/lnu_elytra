package com.mcitem.lnu_elytra

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        flutterEngine.plugins.add(MyPlugin())
        super.configureFlutterEngine(flutterEngine)
    }
}
