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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Kopma bildirimi (Dart: lib/background.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tpcm/background")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "notifyLost" -> {
                        Notifier.showLost(
                            this,
                            call.argument<String>("id") ?: "",
                            call.argument<String>("name") ?: "Cihaz"
                        )
                        result.success(null)
                    }
                    "cancelLost" -> {
                        Notifier.cancelLost(this, call.argument<String>("id") ?: "")
                        result.success(null)
                    }
                    // Sessiz dinleme (Dart: tagManager.syncPassive)
                    "setPassiveScan" -> {
                        val ok = PassiveScan.configure(
                            applicationContext,
                            call.argument<Boolean>("enabled") ?: false,
                            call.argument<List<String>>("ids") ?: emptyList()
                        )
                        result.success(ok)
                    }
                    // Bağlanınca / bağlantı kesilince konumu hemen kaydet.
                    "recordSighting" -> {
                        val id = call.argument<String>("id") ?: ""
                        Sightings.record(applicationContext, listOf(id), force = true) {
                            runOnUiThread { result.success(null) }
                        }
                    }
                    "openMap" -> {
                        val lat = call.argument<Double>("lat") ?: 0.0
                        val lng = call.argument<Double>("lng") ?: 0.0
                        val label = Uri.encode(call.argument<String>("label") ?: "")
                        try {
                            startActivity(
                                Intent(Intent.ACTION_VIEW, Uri.parse("geo:$lat,$lng?q=$lat,$lng($label)"))
                            )
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tpcm/permissions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(
                        mapOf(
                            "bluetooth" to granted("bluetooth"),
                            "location" to granted("location"),
                            "location_bg" to granted("location_bg"),
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
        // "Her zaman izin ver": uygulama kapalıyken son görülen konumu kaydetmek için.
        // Android 11+ bunu ayrı ister ve sistem ayar sayfasına yönlendirir.
        "location_bg" ->
            if (Build.VERSION.SDK_INT >= 29)
                arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
            else
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
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
