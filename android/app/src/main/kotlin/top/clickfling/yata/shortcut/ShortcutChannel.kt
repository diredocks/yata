package top.clickfling.yata.shortcut

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.text.TextPaint
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.DrawableCompat
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import top.clickfling.yata.MainActivity
import top.clickfling.yata.R
import kotlin.math.roundToInt

class ShortcutChannel(private val activity: Activity) {

    companion object {
        const val CHANNEL_NAME = "top.clickfling.yata/shortcut"
    }

    private var channel: MethodChannel? = null

    fun attach(flutterEngine: FlutterEngine) {
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME).apply {
            setMethodCallHandler { call, result ->
                handleMethodCall(call, result)
            }
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isShortcutSupported" -> {
                result.success(shortcutManagerOrNull() != null)
            }
            "isShortcutPinned" -> {
                val shortcutId = call.argument<String>("shortcutId") ?: ""
                result.success(isShortcutPinned(shortcutId))
            }
            "pinOrUpdateShortcut" -> {
                val shortcutId = call.argument<String>("shortcutId")
                val listId = call.argument<String>("listId")
                val label = call.argument<String>("label")
                val colorArgb = call.argument<Number>("colorArgb")?.toInt() ?: 0xFF2564CF.toInt()
                val smartType = call.argument<String>("smartType")
                val emoji = call.argument<String>("emoji")
                if (shortcutId.isNullOrEmpty() || listId.isNullOrEmpty() || label.isNullOrEmpty()) {
                    result.error("INVALID_ARGS", "shortcutId, listId, and label are required", null)
                    return
                }
                result.success(
                    pinOrUpdateShortcut(
                        shortcutId = shortcutId,
                        listId = listId,
                        label = label,
                        colorArgb = colorArgb,
                        smartType = smartType,
                        emoji = emoji,
                    ),
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun shortcutManagerOrNull(): ShortcutManager? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val manager = activity.getSystemService(Context.SHORTCUT_SERVICE) as? ShortcutManager
            ?: return null
        return if (manager.isRequestPinShortcutSupported) manager else null
    }

    private fun isShortcutPinned(shortcutId: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || shortcutId.isEmpty()) return false
        val manager = shortcutManagerOrNull() ?: return false
        return manager.pinnedShortcuts.any { it.id == shortcutId }
    }

    private fun pinOrUpdateShortcut(
        shortcutId: String,
        listId: String,
        label: String,
        colorArgb: Int,
        smartType: String?,
        emoji: String?,
    ): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val manager = shortcutManagerOrNull() ?: return null
        val launchIntent = Intent(activity, MainActivity::class.java).apply {
            action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
            data = Uri.parse("yata://widget/open_list?listId=${Uri.encode(listId)}")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val bitmap = buildShortcutBitmap(colorArgb, smartType, emoji)
        val shortcutInfo = ShortcutInfo.Builder(activity, shortcutId)
            .setShortLabel(label)
            .setLongLabel(label)
            .setIcon(Icon.createWithBitmap(bitmap))
            .setIntent(launchIntent)
            .build()

        return if (manager.pinnedShortcuts.any { it.id == shortcutId }) {
            manager.updateShortcuts(listOf(shortcutInfo))
            "updated"
        } else {
            manager.requestPinShortcut(shortcutInfo, null)
            "requested"
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun buildShortcutBitmap(
        colorArgb: Int,
        smartType: String?,
        emoji: String?,
    ): Bitmap {
        val density = activity.resources.displayMetrics.density
        val sizePx = (48f * density).roundToInt().coerceAtLeast(96)
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val circlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = colorArgb or (0xFF shl 24)
            style = Paint.Style.FILL
        }
        val radius = sizePx / 2f
        canvas.drawCircle(radius, radius, radius, circlePaint)

        if (!emoji.isNullOrEmpty()) {
            val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                textSize = sizePx * 0.46f
                textAlign = Paint.Align.CENTER
            }
            val fm = textPaint.fontMetrics
            val baseline = radius - (fm.ascent + fm.descent) / 2f
            canvas.drawText(emoji, radius, baseline, textPaint)
            return bitmap
        }

        val iconRes = when (smartType) {
            "myDay" -> R.drawable.ic_widget_list_my_day
            "important" -> R.drawable.ic_widget_list_important
            "planned" -> R.drawable.ic_widget_list_planned
            "all" -> R.drawable.ic_widget_list_all
            "completed" -> R.drawable.ic_widget_list_completed
            "tasks" -> R.drawable.ic_widget_list_tasks
            else -> R.drawable.ic_widget_list_default
        }
        val drawable = ContextCompat.getDrawable(activity, iconRes)?.mutate()
        if (drawable != null) {
            DrawableCompat.setTint(drawable, Color.WHITE)
            val inset = (sizePx * 0.25f).roundToInt()
            drawable.setBounds(inset, inset, sizePx - inset, sizePx - inset)
            drawable.draw(canvas)
        }
        return bitmap
    }
}
