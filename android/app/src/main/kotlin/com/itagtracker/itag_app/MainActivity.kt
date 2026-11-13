package com.itagtracker.itag_app

import android.Manifest
import android.app.NotificationManager
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
        cleanupRemovedFeatures()
    }

    /**
     * Önceki sürümlerden kalanları temizler (2026-11-13):
     *  - Harita / sessiz dinleme: sisteme bırakılan PendingIntent'li BLE
     *    taramasını durdurur, kaydedilmiş konum verilerini siler.
     *  - Kayıp modu / bildirimler: eski bildirim kanallarını ve bekleyen
     *    bildirimleri kaldırır.
     * Zararsız; yapacak bir şey yoksa hiçbir şey yapmaz.
     */
    private fun cleanupRemovedFeatures() {
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
        try {
            val nm = getSystemService(NotificationManager::class.java)
            nm.cancelAll()
            if (Build.VERSION.SDK_INT >= 26) {
                nm.deleteNotificationChannel("alerts")
                nm.deleteNotificationChannel("keepalive")
            }
        } catch (_: Exception) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tpcm/permissions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(
                        mapOf("bluetooth" to granted("bluetooth"))
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
