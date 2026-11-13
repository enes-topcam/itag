package com.itagtracker.itag_app

import android.Manifest
import android.app.PendingIntent
import android.bluetooth.BluetoothManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        cleanupRemovedMapFeature()
    }

    /**
     * Harita / sessiz dinleme özelliği kaldırıldı (2026-11-13). Önceki sürümün
     * sisteme bıraktığı PendingIntent'li BLE taramasını durdur ve kaydedilmiş
     * konum verilerini sil. Zararsız; artık yapacak bir şey yoksa hiçbir şey yapmaz.
     */
    private fun cleanupRemovedMapFeature() {
        try {
            val i = Intent("com.itagtracker.itag_app.PASSIVE_SCAN")
                .setClassName(packageName, "com.itagtracker.itag_app.PassiveScanReceiver")
            val flags = PendingIntent.FLAG_NO_CREATE or
                (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
            val pi = PendingIntent.getBroadcast(this, 77, i, flags)
            if (pi != null) {
                val scanAllowed = Build.VERSION.SDK_INT < 31 ||
                    checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) ==
                    PackageManager.PERMISSION_GRANTED
                val scanner = getSystemService(BluetoothManager::class.java)
                    ?.adapter?.bluetoothLeScanner
                if (scanAllowed && scanner != null) scanner.stopScan(pi)
                pi.cancel()
            }
        } catch (_: Exception) {}
        getSharedPreferences("tpcm_native", MODE_PRIVATE).edit().clear().apply()
        getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE).edit()
            .remove("flutter.sightings_v1")
            .remove("flutter.passiveTracking")
            .apply()
    }

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
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tpcm/permissions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(
                        mapOf(
                            "bluetooth" to granted("bluetooth"),
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
