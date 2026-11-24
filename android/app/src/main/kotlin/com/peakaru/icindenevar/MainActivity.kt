package com.peakaru.icindenevar

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Uygulama ayarlarını (kamera izni) ve tarayıcıda bağlantı açmak için;
        // bunun için ayrı bir eklenti paketi eklemeye gerek yok
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "icindenevar/system")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "openAppSettings" -> {
                            startActivity(
                                Intent(
                                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    Uri.fromParts("package", packageName, null)
                                )
                            )
                            result.success(true)
                        }
                        "openUrl" -> {
                            val url = call.argument<String>("url")
                            if (url == null || !url.startsWith("https://")) {
                                result.success(false)
                            } else {
                                startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                                result.success(true)
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: ActivityNotFoundException) {
                    result.success(false)
                }
            }
    }
}
