package com.itagtracker.itag_app

import android.Manifest
import android.app.PendingIntent
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log

/**
 * Sessiz dinleme: kayıtlı etiketlerin reklam yayınını BAĞLANMADAN dinler.
 * Bağlanmadığımız için etiket ötmez (bu iTag yalnızca bağlantı kopunca öter).
 *
 * Android'e PendingIntent'li bir tarama isteği bırakılır; eşleşen yayın
 * duyulunca sistem [PassiveScanReceiver]'ı uyandırır — uygulama kapalı olsa
 * bile, kalıcı bildirim / servis gerekmeden. Filtreleme Bluetooth çipinde
 * yapıldığı için pil tüketimi düşüktür.
 */
object PassiveScan {
    private const val TAG = "TPCM-PassiveScan"
    private const val NATIVE_PREFS = "tpcm_native"
    private const val KEY_ENABLED = "passive_enabled"
    private const val KEY_IDS = "passive_ids"
    private const val ACTION = "com.itagtracker.itag_app.PASSIVE_SCAN"

    private fun pendingIntent(ctx: Context): PendingIntent {
        val i = Intent(ctx, PassiveScanReceiver::class.java).setAction(ACTION)
        // Sistem sonuçları intent'e eklediği için MUTABLE olmak zorunda.
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
        return PendingIntent.getBroadcast(ctx, 77, i, flags)
    }

    private fun scanner(ctx: Context): Pair<BluetoothAdapter, BluetoothLeScanner>? {
        if (Build.VERSION.SDK_INT >= 31 &&
            ctx.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) !=
            PackageManager.PERMISSION_GRANTED
        ) return null
        val adapter = ctx.getSystemService(BluetoothManager::class.java)?.adapter ?: return null
        if (!adapter.isEnabled) return null
        val s = adapter.bluetoothLeScanner ?: return null
        return adapter to s
    }

    /** Ayarı kaydeder ve uygular. Uygulandıysa true. */
    fun configure(ctx: Context, enabled: Boolean, ids: List<String>): Boolean {
        ctx.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_ENABLED, enabled)
            .putStringSet(KEY_IDS, ids.toSet())
            .apply()
        return apply(ctx)
    }

    /** Kayıtlı ayara göre taramayı (yeniden) kurar — açılışta/güncellemede. */
    fun apply(ctx: Context): Boolean {
        val p = ctx.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
        val enabled = p.getBoolean(KEY_ENABLED, false)
        val ids = (p.getStringSet(KEY_IDS, emptySet()) ?: emptySet())
            .filter { BluetoothAdapter.checkBluetoothAddress(it) } // iOS UUID'leri değil, MAC
        val (adapter, scanner) = scanner(ctx) ?: return false
        try {
            scanner.stopScan(pendingIntent(ctx))
        } catch (_: Exception) {}
        if (!enabled || ids.isEmpty()) return true

        val filters = ids.map { ScanFilter.Builder().setDeviceAddress(it).build() }
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_POWER)
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            // Destekleniyorsa sonuçları dakikada bir toplu teslim et (az uyanma).
            .setReportDelay(if (adapter.isOffloadedScanBatchingSupported) 60_000L else 0L)
            .build()
        return try {
            val rc = scanner.startScan(filters, settings, pendingIntent(ctx))
            Log.i(TAG, "passive scan for ${ids.size} device(s), rc=$rc")
            rc == 0
        } catch (e: Exception) {
            Log.w(TAG, "startScan failed: $e")
            false
        }
    }
}

class PassiveScanReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.hasExtra(BluetoothLeScanner.EXTRA_ERROR_CODE)) return
        val results: List<ScanResult> = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(
                BluetoothLeScanner.EXTRA_LIST_SCAN_RESULT, ScanResult::class.java
            )
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra(BluetoothLeScanner.EXTRA_LIST_SCAN_RESULT)
        } ?: return
        val ids = results.mapNotNull { it.device?.address }.distinct()
        if (ids.isEmpty()) return
        val pending = goAsync()
        Sightings.record(context.applicationContext, ids, force = false) {
            pending.finish()
        }
    }
}

/** Telefon açılınca / uygulama güncellenince sessiz dinlemeyi yeniden kurar.
 *  (Bağlanmaz — sadece dinler; etiket ötmez.) */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED ->
                PassiveScan.apply(context.applicationContext)
        }
    }
}
