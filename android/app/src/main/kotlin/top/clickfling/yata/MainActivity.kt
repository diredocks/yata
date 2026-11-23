package top.clickfling.yata

import android.app.ActivityManager
import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import top.clickfling.yata.font.SystemFontChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val NOTIFICATION_SETTINGS_CHANNEL =
            "top.clickfling.yata/notification_settings"
    }

    private var systemFontChannel: SystemFontChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        systemFontChannel = SystemFontChannel().also { it.attach(flutterEngine) }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATION_SETTINGS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPermissionStatus" -> result.success(readPermissionStatus())
                "openNotificationSettings" -> {
                    openNotificationSettings()
                    result.success(null)
                }
                "openExactAlarmSettings" -> {
                    openExactAlarmSettings()
                    result.success(null)
                }
                "openBatteryOptimizationSettings" -> {
                    openBatteryOptimizationSettings()
                    result.success(null)
                }
                "openAppDetailsSettings" -> {
                    openAppDetailsSettings()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        systemFontChannel?.detach()
        systemFontChannel = null
        super.onDestroy()
    }

    private fun readPermissionStatus(): Map<String, Any> {
        val notificationsEnabled =
            NotificationManagerCompat.from(this).areNotificationsEnabled() &&
                (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                    ContextCompat.checkSelfPermission(
                        this,
                        android.Manifest.permission.POST_NOTIFICATIONS,
                    ) == PackageManager.PERMISSION_GRANTED)

        val exactAlarmsEnabled =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val alarmManager =
                    getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                alarmManager?.canScheduleExactAlarms() ?: true
            } else {
                true
            }

        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        val ignoringBatteryOptimizations =
            powerManager?.isIgnoringBatteryOptimizations(packageName) ?: true

        val backgroundRestricted =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val activityManager =
                    getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                activityManager?.isBackgroundRestricted ?: false
            } else {
                false
            }

        return mapOf(
            "notificationsEnabled" to notificationsEnabled,
            "exactAlarmsEnabled" to exactAlarmsEnabled,
            "ignoringBatteryOptimizations" to ignoringBatteryOptimizations,
            "backgroundRestricted" to backgroundRestricted,
            "isAndroid" to true,
            "androidSdkInt" to Build.VERSION.SDK_INT,
        )
    }

    private fun openNotificationSettings() {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        }
        startActivitySafely(intent) { openAppDetailsSettings() }
    }

    private fun openExactAlarmSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivitySafely(intent) { openAppDetailsSettings() }
        } else {
            openAppDetailsSettings()
        }
    }

    private fun openBatteryOptimizationSettings() {
        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        startActivitySafely(intent) { openAppDetailsSettings() }
    }

    private fun openAppDetailsSettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
        }
        startActivitySafely(intent)
    }

    private fun startActivitySafely(
        intent: Intent,
        fallback: (() -> Unit)? = null,
    ) {
        try {
            startActivity(intent)
        } catch (_: Exception) {
            fallback?.invoke()
        }
    }
}
