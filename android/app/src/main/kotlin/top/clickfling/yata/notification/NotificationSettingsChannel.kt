package top.clickfling.yata.notification

import android.Manifest
import android.app.Activity
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
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class NotificationSettingsChannel(private val activity: Activity) {

    companion object {
        const val CHANNEL_NAME = "top.clickfling.yata/notification_settings"
    }

    private var channel: MethodChannel? = null

    fun attach(flutterEngine: FlutterEngine) {
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME).apply {
            setMethodCallHandler { call, result ->
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
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun readPermissionStatus(): Map<String, Any> {
        val notificationsEnabled =
            NotificationManagerCompat.from(activity).areNotificationsEnabled() &&
                (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                    ContextCompat.checkSelfPermission(
                        activity,
                        Manifest.permission.POST_NOTIFICATIONS,
                    ) == PackageManager.PERMISSION_GRANTED)

        val exactAlarmsEnabled =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val alarmManager =
                    activity.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                alarmManager?.canScheduleExactAlarms() ?: true
            } else {
                true
            }

        val powerManager = activity.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val ignoringBatteryOptimizations =
            powerManager?.isIgnoringBatteryOptimizations(activity.packageName) ?: true

        val backgroundRestricted =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val activityManager =
                    activity.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
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
            putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
        }
        startActivitySafely(intent) { openAppDetailsSettings() }
    }

    private fun openExactAlarmSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                data = Uri.parse("package:${activity.packageName}")
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
            data = Uri.parse("package:${activity.packageName}")
        }
        startActivitySafely(intent)
    }

    private fun startActivitySafely(
        intent: Intent,
        fallback: (() -> Unit)? = null,
    ) {
        try {
            activity.startActivity(intent)
        } catch (_: Exception) {
            fallback?.invoke()
        }
    }
}
