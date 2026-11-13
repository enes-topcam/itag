package com.itagtracker.itag_app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

/** Bildirim kanalları ve bildirimler. */
object Notifier {
    private const val CH_ALERTS = "alerts"

    private fun ensureChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = ctx.getSystemService(NotificationManager::class.java)
        // Önceki sürümün "hep bağlı kal" kanalını temizle.
        nm.deleteNotificationChannel("keepalive")
        nm.createNotificationChannel(
            NotificationChannel(
                CH_ALERTS, "Kopma uyarıları",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Bir cihazla bağlantı kesildiğinde"
                enableVibration(true)
            }
        )
    }

    private fun openApp(ctx: Context): PendingIntent {
        val i = Intent(ctx, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            ctx, 0, i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    @Suppress("DEPRECATION")
    private fun builder(ctx: Context, channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) Notification.Builder(ctx, channel)
        else Notification.Builder(ctx)

    private fun canNotify(ctx: Context): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun lostId(id: String) = 1000 + (id.hashCode() and 0x7fff)

    fun showLost(ctx: Context, id: String, name: String) {
        if (!canNotify(ctx)) return
        ensureChannels(ctx)
        val n = builder(ctx, CH_ALERTS)
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setContentTitle("$name ile bağlantı kesildi")
            .setContentText("Cihaz uzakta olabilir. Menzile girince yeniden bağlanılacak.")
            .setContentIntent(openApp(ctx))
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_ALARM)
            .build()
        ctx.getSystemService(NotificationManager::class.java).notify(lostId(id), n)
    }

    fun cancelLost(ctx: Context, id: String) {
        ctx.getSystemService(NotificationManager::class.java).cancel(lostId(id))
    }
}
