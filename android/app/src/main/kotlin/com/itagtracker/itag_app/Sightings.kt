package com.itagtracker.itag_app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.json.JSONObject

/**
 * "Son görülme" kayıtları: bir etiket en son ne zaman duyuldu ve o sırada
 * telefon neredeydi. (Etiketin GPS'i yok; konum TELEFONUN konumudur.)
 *
 * Dart tarafının okuyabilmesi için shared_preferences eklentisinin dosyasına
 * ("FlutterSharedPreferences", anahtar "flutter.sightings_v1") JSON yazar:
 *   { "<cihaz id>": { "t": görülme ms, "lt": konum ms, "lat", "lng", "acc" } }
 *
 * Pil için: görülme zamanı en fazla dakikada bir, konum en fazla 5 dakikada
 * bir güncellenir; konum GPS yerine ağ (Wi-Fi/baz) sağlayıcısından alınır.
 */
object Sightings {
    private const val TAG = "TPCM-Sightings"
    private const val PREFS = "FlutterSharedPreferences"
    private const val KEY = "flutter.sightings_v1"
    private const val SEEN_THROTTLE_MS = 60_000L
    private const val LOCATION_THROTTLE_MS = 5 * 60_000L

    @Synchronized
    private fun readAll(ctx: Context): JSONObject {
        val raw = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
        return try {
            if (raw == null) JSONObject() else JSONObject(raw)
        } catch (_: Exception) {
            JSONObject()
        }
    }

    @Synchronized
    private fun write(ctx: Context, ids: List<String>, loc: Location?) {
        val all = readAll(ctx)
        val now = System.currentTimeMillis()
        for (id in ids) {
            val o = all.optJSONObject(id) ?: JSONObject()
            o.put("t", now)
            if (loc != null) {
                o.put("lt", now)
                o.put("lat", loc.latitude)
                o.put("lng", loc.longitude)
                o.put("acc", loc.accuracy.toDouble())
            }
            all.put(id, o)
        }
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY, all.toString()).apply()
    }

    /**
     * [force]: kullanıcı bağlandı/bağlantıyı kesti — kısıtlama olmadan kaydet.
     * [done] her durumda bir kez çağrılır (BroadcastReceiver.goAsync için).
     */
    fun record(ctx: Context, ids: List<String>, force: Boolean, done: () -> Unit) {
        val now = System.currentTimeMillis()
        val all = readAll(ctx)
        val due = if (force) ids else ids.filter {
            now - (all.optJSONObject(it)?.optLong("t") ?: 0L) >= SEEN_THROTTLE_MS
        }
        if (due.isEmpty()) return done()
        val needLoc = force || due.any {
            now - (all.optJSONObject(it)?.optLong("lt") ?: 0L) >= LOCATION_THROTTLE_MS
        }
        if (!needLoc) {
            write(ctx, due, null)
            return done()
        }
        currentLocation(ctx) { loc ->
            try {
                write(ctx, due, loc)
            } finally {
                done()
            }
        }
    }

    private fun hasLocationPermission(ctx: Context): Boolean =
        ctx.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            ctx.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    /** Ağ tabanlı (az pil) tek seferlik konum; 8 sn'de gelmezse son bilinen. */
    private fun currentLocation(ctx: Context, cb: (Location?) -> Unit) {
        if (!hasLocationPermission(ctx)) return cb(null)
        try {
            val lm = ctx.getSystemService(LocationManager::class.java) ?: return cb(null)
            val candidates = mutableListOf(LocationManager.NETWORK_PROVIDER)
            if (Build.VERSION.SDK_INT >= 31) candidates.add(LocationManager.FUSED_PROVIDER)
            candidates.add(LocationManager.GPS_PROVIDER)
            val provider = candidates.firstOrNull {
                try { lm.isProviderEnabled(it) } catch (_: Exception) { false }
            } ?: return cb(null)

            fun lastKnown(): Location? = try {
                lm.getLastKnownLocation(provider)
            } catch (_: SecurityException) { null }

            if (Build.VERSION.SDK_INT < 30) return cb(lastKnown())

            var finished = false
            val cancel = CancellationSignal()
            val handler = Handler(Looper.getMainLooper())
            handler.postDelayed({
                if (!finished) {
                    finished = true
                    cancel.cancel()
                    cb(lastKnown())
                }
            }, 8_000)
            lm.getCurrentLocation(provider, cancel, ctx.mainExecutor) { loc ->
                if (!finished) {
                    finished = true
                    cb(loc ?: lastKnown())
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "location failed: $e")
            cb(null)
        }
    }
}
