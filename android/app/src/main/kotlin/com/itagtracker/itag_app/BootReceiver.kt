package com.itagtracker.itag_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Telefon açıldığında veya uygulama güncellendiğinde çalışır.
 *
 * Neden? Bu iTag her bağlantı kopuşunda öter ve bunu kapatan bir ayarı yok;
 * ama yeniden bağlanınca susuyor. Telefon yeniden başlayınca / uygulama
 * güncellenince bağlantı kopar. Burada işlemin başlaması App.onCreate'i
 * tetikler → Flutter motoru → Dart kayıtlı cihazlara yeniden bağlanır →
 * etiket susar. KeepAliveService ise işlemi ayakta tutar.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                // shared_preferences eklentisinin dosyası; anahtarlar "flutter." önekli.
                val prefs = context.getSharedPreferences(
                    "FlutterSharedPreferences", Context.MODE_PRIVATE
                )
                val keepAlive = prefs.getBoolean("flutter.keepAlive", true)
                val hasDevices = prefs.contains("flutter.saved_tags_v1")
                if (keepAlive && hasDevices) {
                    // Sayı Dart tarafı açılınca güncellenir.
                    KeepAliveService.start(context, -1)
                }
            }
        }
    }
}
