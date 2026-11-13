package com.itagtracker.itag_app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * İzinleri Android'in kendi API'siyle isteyen küçük köprü.
 * (permission_handler eklentisi bu projenin Gradle sürümüyle derlenmediği için.)
 *
 * Dart tarafı: lib/permissions.dart  —  kanal adı "tpcm/permissions"
 */
class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private val requestCode = 4242

    // App.kt'de başlatılan, ekrandan bağımsız yaşayan motoru kullan.
    // Ekran kapanınca motor (ve Bluetooth bağlantıları) yok edilmez.
    override fun getCachedEngineId(): String = App.ENGINE_ID

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tpcm/permissions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(
                        mapOf(
                            "bluetooth" to granted("bluetooth"),
                            "location" to granted("location"),
                            "notification" to granted("notification"),
                        )
                    )
                    "request" -> {
                        val group = call.argument<String>("group") ?: ""
                        val perms = permsFor(group)
                        when {
                            perms.isEmpty() || granted(group) -> result.success(true)
                            pending != null -> result.error("busy", "İzin isteği sürüyor", null)
                            else -> {
                                pending = result
                                requestPermissions(perms, requestCode)
                            }
                        }
                    }
                    "openSettings" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.fromParts("package", packageName, null)
                            )
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun permsFor(group: String): Array<String> = when (group) {
        "bluetooth" ->
            if (Build.VERSION.SDK_INT >= 31)
                arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
            else
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        "location" -> arrayOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION
        )
        "notification" ->
            if (Build.VERSION.SDK_INT >= 33) arrayOf(Manifest.permission.POST_NOTIFICATIONS)
            else emptyArray()
        else -> emptyArray()
    }

    private fun granted(group: String): Boolean =
        permsFor(group).all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == this.requestCode) {
            val ok = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pending?.success(ok)
            pending = null
        }
    }
}
