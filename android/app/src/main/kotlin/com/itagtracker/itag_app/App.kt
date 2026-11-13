package com.itagtracker.itag_app

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter motorunu Activity'den bağımsız, uygulama düzeyinde başlatır.
 *
 * Neden? Varsayılan durumda motor ekranla (Activity) birlikte ölür; uygulama
 * kapatılınca Bluetooth bağlantısı kopar ve iTag "bağlantı koptu" diye öter
 * (bu etikette öttürmeyi kapatan 1803 Link Loss servisi yok). Motor burada
 * yaşarsa ve KeepAliveService işlemi ayakta tutarsa bağlantı kopmaz.
 */
class App : Application() {
    companion object {
        const val ENGINE_ID = "main"
    }

    override fun onCreate() {
        super.onCreate()
        val engine = FlutterEngine(this)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)

        // Activity'ye bağlı olmayan kanal: arka plan servisi + bildirimler.
        MethodChannel(engine.dartExecutor.binaryMessenger, "tpcm/background")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setKeepAlive" -> {
                        val on = call.argument<Boolean>("enabled") ?: false
                        val count = call.argument<Int>("count") ?: 0
                        if (on) KeepAliveService.start(this, count)
                        else KeepAliveService.stop(this)
                        result.success(null)
                    }
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
    }
}
