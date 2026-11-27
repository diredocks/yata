package top.clickfling.yata.widget

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class WidgetSyncChannel {

    companion object {
        const val CHANNEL_NAME = "top.clickfling.yata/widget_sync"
        const val METHOD_SYNC_WIDGET = "syncWidget"

        @Volatile
        private var active: WidgetSyncChannel? = null

        fun canDispatch(): Boolean {
            val current = active ?: return false
            return current.isForeground && current.channel != null
        }

        fun dispatchIfAttached(reason: String): Boolean {
            val current = active ?: return false
            if (!current.isForeground) return false
            return current.notifySyncWidget(reason)
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null

    @Volatile
    private var isForeground: Boolean = false

    fun attach(flutterEngine: FlutterEngine) {
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        active = this
    }

    fun setForeground(foreground: Boolean) {
        isForeground = foreground
    }

    fun detach() {
        isForeground = false
        if (active === this) {
            active = null
        }
        channel = null
    }

    private fun notifySyncWidget(reason: String): Boolean {
        val target = channel ?: return false
        mainHandler.post {
            if (channel === target && isForeground) {
                target.invokeMethod(METHOD_SYNC_WIDGET, reason)
            }
        }
        return true
    }
}
