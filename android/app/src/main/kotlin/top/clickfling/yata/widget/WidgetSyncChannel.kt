package top.clickfling.yata.widget

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class WidgetSyncChannel {

    companion object {
        const val CHANNEL_NAME = "top.clickfling.yata/widget_sync"

        @Volatile
        private var active: WidgetSyncChannel? = null

        fun dispatchIfAttached(reason: String): Boolean {
            return active?.notifySyncWidget(reason) ?: false
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null

    fun attach(flutterEngine: FlutterEngine) {
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        active = this
    }

    fun detach() {
        if (active === this) {
            active = null
        }
        channel = null
    }

    private fun notifySyncWidget(reason: String): Boolean {
        val target = channel ?: return false
        mainHandler.post {
            if (channel === target) {
                target.invokeMethod("syncWidget", reason)
            }
        }
        return true
    }
}
