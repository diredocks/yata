package top.clickfling.yata.font

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Bridges [SystemFontResolver] to Dart over `top.clickfling.yata/system_font`.
 *
 * Resolution and font reads happen on a worker thread because they touch the
 * file system and may move several megabytes; only the reply is posted back to
 * the platform thread.
 */
class SystemFontChannel {

    companion object {
        const val CHANNEL_NAME = "top.clickfling.yata/system_font"

        // Process-wide so the fingerprint cache survives activity recreation.
        private val resolver: SystemFontResolver by lazy { SystemFontResolver() }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "system-font-resolver").apply { isDaemon = true }
    }

    @Volatile
    private var attached = false

    fun attach(flutterEngine: FlutterEngine) {
        attached = true
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSystemFont" -> getSystemFont(
                        force = call.argument<Boolean>("force") == true,
                        result = result,
                    )
                    else -> result.notImplemented()
                }
            }
    }

    /** Stops delivering replies once the engine is going away. */
    fun detach() {
        attached = false
        executor.shutdownNow()
    }

    private fun getSystemFont(force: Boolean, result: MethodChannel.Result) {
        executor.execute {
            val payload = try {
                resolver.load(force)
            } catch (_: Throwable) {
                null
            }
            mainHandler.post {
                if (!attached) return@post
                result.success(payload?.toMap())
            }
        }
    }

    private fun SystemFontResolver.Payload.toMap(): Map<String, Any?> = mapOf(
        "changed" to changed,
        "familyName" to familyName,
        "fingerprint" to fingerprint,
        "fallbackFamilies" to fallbackFamilies,
        "regular" to regular,
        "bold" to bold,
    )
}
