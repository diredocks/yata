package top.clickfling.yata

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import top.clickfling.yata.font.SystemFontChannel
import top.clickfling.yata.notification.NotificationSettingsChannel
import top.clickfling.yata.shortcut.ShortcutChannel
import top.clickfling.yata.widget.WidgetSyncChannel
import top.clickfling.yata.window.WindowFocusChannel

class MainActivity : FlutterActivity() {
    private var shortcutChannel: ShortcutChannel? = null
    private var systemFontChannel: SystemFontChannel? = null
    private var notificationSettingsChannel: NotificationSettingsChannel? = null
    private var windowFocusChannel: WindowFocusChannel? = null
    private var widgetSyncChannel: WidgetSyncChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        detachChannels()
        shortcutChannel = ShortcutChannel(this).also { it.attach(flutterEngine) }
        systemFontChannel = SystemFontChannel().also { it.attach(flutterEngine) }
        notificationSettingsChannel =
            NotificationSettingsChannel(this).also { it.attach(flutterEngine) }
        windowFocusChannel = WindowFocusChannel(this).also { it.attach(flutterEngine) }
        widgetSyncChannel = WidgetSyncChannel().also { it.attach(flutterEngine) }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        windowFocusChannel?.notifyWindowFocusChanged(hasFocus)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        detachChannels()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        detachChannels()
        super.onDestroy()
    }

    private fun detachChannels() {
        shortcutChannel?.detach()
        shortcutChannel = null
        systemFontChannel?.detach()
        systemFontChannel = null
        notificationSettingsChannel?.detach()
        notificationSettingsChannel = null
        windowFocusChannel?.detach()
        windowFocusChannel = null
        widgetSyncChannel?.detach()
        widgetSyncChannel = null
    }
}
