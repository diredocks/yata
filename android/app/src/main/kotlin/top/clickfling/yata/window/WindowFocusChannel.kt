package top.clickfling.yata.window

import android.app.Activity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class WindowFocusChannel(private val activity: Activity) {

    companion object {
        const val CHANNEL_NAME = "top.clickfling.yata/window_focus"
    }

    private var channel: MethodChannel? = null

    fun attach(flutterEngine: FlutterEngine) {
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
    }

    fun notifyWindowFocusChanged(hasFocus: Boolean) {
        if (!hasFocus) return
        // Post to the decorView queue so any in-flight HIDE_UNSPECIFIED_WINDOW
        // message from WindowManager settles before Flutter re-checks IME state.
        activity.window?.decorView?.post {
            channel?.invokeMethod("windowFocusGained", null)
        }
    }

    fun detach() {
        channel = null
    }
}
