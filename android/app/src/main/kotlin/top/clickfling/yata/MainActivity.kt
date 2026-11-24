package top.clickfling.yata

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import top.clickfling.yata.font.SystemFontChannel
import top.clickfling.yata.notification.NotificationSettingsChannel

class MainActivity : FlutterActivity() {
    private var systemFontChannel: SystemFontChannel? = null
    private var notificationSettingsChannel: NotificationSettingsChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        detachChannels()
        systemFontChannel = SystemFontChannel().also { it.attach(flutterEngine) }
        notificationSettingsChannel =
            NotificationSettingsChannel(this).also { it.attach(flutterEngine) }
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
        systemFontChannel?.detach()
        systemFontChannel = null
        notificationSettingsChannel?.detach()
        notificationSettingsChannel = null
    }
}
