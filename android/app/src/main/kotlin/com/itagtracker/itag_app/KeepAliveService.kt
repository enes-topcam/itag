package com.itagtracker.itag_app

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * Ön plan servisi: uygulama kapatılsa (son uygulamalardan kaydırılsa) bile
 * işlemi ayakta tutar; böylece App içindeki Flutter motoru ve Bluetooth
 * bağlantıları yaşamaya devam eder. Android bunun için sürekli bir bildirim
 * gösterilmesini zorunlu tutar.
 */
class KeepAliveService : Service() {
    companion object {
        private const val TAG = "TPCM-KeepAlive"
        private const val EXTRA_COUNT = "count"

        fun start(ctx: Context, count: Int) {
            val i = Intent(ctx, KeepAliveService::class.java).putExtra(EXTRA_COUNT, count)
            try {
                if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i)
                else ctx.startService(i)
            } catch (e: Exception) {
                // Örn. Android 12+ arka plandan başlatma kısıtı.
                Log.w(TAG, "start failed: $e")
            }
        }

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, KeepAliveService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val count = intent?.getIntExtra(EXTRA_COUNT, 0) ?: 0
        val n = Notifier.keepAlive(this, count)
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(
                    Notifier.KEEPALIVE_ID, n,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
                )
            } else {
                startForeground(Notifier.KEEPALIVE_ID, n)
            }
        } catch (e: Exception) {
            // Bluetooth izni yoksa veya sistem izin vermezse servis duramaz.
            Log.w(TAG, "startForeground failed: $e")
            stopSelf()
            return START_NOT_STICKY
        }
        // Sistem işlemi öldürürse yeniden başlat: App.onCreate motoru tekrar
        // kurar, Dart tarafı kayıtlı cihazlara yeniden bağlanır.
        return START_STICKY
    }
}
