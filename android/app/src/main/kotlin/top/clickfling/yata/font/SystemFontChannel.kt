package top.clickfling.yata.font

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

class SystemFontChannel {

    companion object {
        const val CHANNEL_NAME = "top.clickfling.yata/system_font"

        private val resolver: SystemFontResolver by lazy { SystemFontResolver() }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "system-font-resolver").apply { isDaemon = true }
    }

    @Volatile
    private var attached = false
    private var channel: MethodChannel? = null

    fun attach(flutterEngine: FlutterEngine) {
        attached = true
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSystemFont" -> getSystemFont(
                        lastFingerprint = call.argument<String>("lastFingerprint"),
                        result = result,
                    )
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun detach() {
        attached = false
        channel?.setMethodCallHandler(null)
        channel = null
        mainHandler.removeCallbacksAndMessages(null)
        executor.shutdownNow()
    }

    private fun getSystemFont(lastFingerprint: String?, result: MethodChannel.Result) {
        try {
            executor.execute {
                val payload = try {
                    resolver.load(lastFingerprint)
                } catch (_: Throwable) {
                    null
                }
                mainHandler.post {
                    if (!attached) return@post
                    result.success(payload?.toMap())
                }
            }
        } catch (_: RejectedExecutionException) {
        }
    }

    private fun SystemFontResolver.Payload.toMap(): Map<String, Any?> = mapOf(
        "changed" to changed,
        "fingerprint" to fingerprint,
        "fallbackFamilies" to fallbackFamilies,
        "regular" to regular,
        "bold" to bold,
    )
}
