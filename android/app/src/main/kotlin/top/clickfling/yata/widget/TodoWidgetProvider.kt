package top.clickfling.yata.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import top.clickfling.yata.MainActivity
import top.clickfling.yata.R

class TodoWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        for (appWidgetId in appWidgetIds) {
            TodoWidgetData.deleteConfig(context, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_WIDGET_REFRESH) {
            TodoWidgetData.setRefreshing(context, true)
            refreshAllWidgets(context)
            dispatchBackgroundEvent(context, Uri.parse("yata://widget/refresh"))
            return
        }
        if (intent.action != ACTION_WIDGET_ITEM_CLICK) return

        val itemAction = intent.getStringExtra(EXTRA_ITEM_ACTION) ?: return
        val taskId = intent.getStringExtra(EXTRA_TASK_ID) ?: return
        val listId = intent.getStringExtra(EXTRA_LIST_ID) ?: WidgetConfig.DEFAULT_LIST_ID

        when (itemAction) {
            ITEM_ACTION_TOGGLE_COMPLETE -> {
                val newValue = TodoWidgetData.optimisticToggleComplete(context, taskId)
                refreshAllWidgets(context)
                val uri = Uri.parse(
                    "yata://widget/toggle_complete?taskId=${Uri.encode(taskId)}" +
                        if (newValue != null) "&completed=$newValue" else "",
                )
                dispatchBackgroundEvent(context, uri)
            }
            ITEM_ACTION_TOGGLE_IMPORTANT -> {
                val newValue = TodoWidgetData.optimisticToggleImportant(context, taskId)
                refreshAllWidgets(context)
                val uri = Uri.parse(
                    "yata://widget/toggle_important?taskId=${Uri.encode(taskId)}" +
                        if (newValue != null) "&important=$newValue" else "",
                )
                dispatchBackgroundEvent(context, uri)
            }
            ITEM_ACTION_OPEN_TASK -> {
                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
                    data = Uri.parse(
                        "yata://widget/open_task?taskId=${Uri.encode(taskId)}&listId=${Uri.encode(listId)}",
                    )
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                context.startActivity(launchIntent)
            }
        }
    }

    private fun dispatchBackgroundEvent(context: Context, uri: Uri) {
        val bgIntent = Intent(context, HomeWidgetBackgroundReceiver::class.java).apply {
            action = "es.antonborri.home_widget.action.BACKGROUND"
            data = uri
        }
        HomeWidgetBackgroundReceiver().onReceive(context, bgIntent)
    }

    companion object {
        const val ACTION_WIDGET_ITEM_CLICK = "top.clickfling.yata.widget.ACTION_ITEM_CLICK"
        const val ACTION_WIDGET_REFRESH = "top.clickfling.yata.widget.ACTION_REFRESH"
        const val EXTRA_ITEM_ACTION = "extra_item_action"
        const val EXTRA_TASK_ID = "extra_task_id"
        const val EXTRA_LIST_ID = "extra_list_id"

        const val ITEM_ACTION_TOGGLE_COMPLETE = "toggle_complete"
        const val ITEM_ACTION_TOGGLE_IMPORTANT = "toggle_important"
        const val ITEM_ACTION_OPEN_TASK = "open_task"

        fun refreshAllWidgets(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, TodoWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isEmpty()) return
            for (id in ids) {
                updateAppWidget(context, manager, id)
            }
            manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_tasks_list_view)
        }

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val config = TodoWidgetData.loadConfig(context, appWidgetId)
            val resolvedList = TodoWidgetData.resolveList(context, config.listId)
            val effectiveListId = resolvedList?.id ?: config.listId
            val listTitle = resolvedList?.displayTitle
                ?: context.getString(R.string.widget_my_day)
            val emptyMessage = TodoWidgetData.loadEmptyMessage(context)
                ?: context.getString(R.string.widget_empty_state)

            val views = RemoteViews(context.packageName, R.layout.todo_widget_layout)

            // Apply opacity (20% - 100%)
            val bodyAlpha = (config.opacityPercent.coerceIn(20, 100) * 255) / 100
            val headerAlpha = ((config.opacityPercent + 10).coerceIn(30, 100) * 255) / 100
            views.setInt(R.id.widget_background, "setImageAlpha", bodyAlpha)
            views.setInt(R.id.widget_header_background, "setImageAlpha", headerAlpha)

            // Header labels
            views.setTextViewText(R.id.widget_list_name, listTitle)
            views.setViewVisibility(R.id.widget_account_name, View.GONE)
            views.setTextViewText(R.id.widget_empty_list, emptyMessage)

            // Header blank area -> open currently selected list in app
            val openListUri = Uri.parse(
                "yata://widget/open_list?listId=${Uri.encode(effectiveListId)}&widgetId=$appWidgetId",
            )
            views.setOnClickPendingIntent(
                R.id.widget_header_container,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, openListUri),
            )

            // Header title -> folder picker
            val pickerIntent = Intent(context, TodoWidgetFolderPickerActivity::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                data = Uri.parse("yata://widget/picker/$appWidgetId")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            views.setOnClickPendingIntent(
                R.id.widget_headline_container,
                PendingIntent.getActivity(
                    context,
                    appWidgetId * 10 + 1,
                    pickerIntent,
                    immutableFlags(),
                ),
            )

            // Refresh button -> show progress spinner & trigger background refresh
            val isRefreshing = TodoWidgetData.isRefreshing(context)
            views.setViewVisibility(
                R.id.widget_refresh_button,
                if (isRefreshing) View.GONE else View.VISIBLE,
            )
            views.setViewVisibility(
                R.id.widget_refresh_progress,
                if (isRefreshing) View.VISIBLE else View.GONE,
            )
            val refreshIntent = Intent(context, TodoWidgetProvider::class.java).apply {
                action = ACTION_WIDGET_REFRESH
            }
            views.setOnClickPendingIntent(
                R.id.widget_refresh_button,
                PendingIntent.getBroadcast(
                    context,
                    appWidgetId * 10 + 4,
                    refreshIntent,
                    immutableFlags(),
                ),
            )

            // Add task button -> open app quick add for this list
            val addUri = Uri.parse(
                "yata://widget/add?listId=${Uri.encode(effectiveListId)}&widgetId=$appWidgetId",
            )
            views.setOnClickPendingIntent(
                R.id.widget_add_task,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, addUri),
            )

            // Settings button -> widget configuration
            val configIntent = Intent(context, TodoWidgetConfigurationActivity::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                data = Uri.parse("yata://widget/config/$appWidgetId")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            views.setOnClickPendingIntent(
                R.id.widget_settings,
                PendingIntent.getActivity(
                    context,
                    appWidgetId * 10 + 2,
                    configIntent,
                    immutableFlags(),
                ),
            )

            // Tasks ListView adapter
            val serviceIntent = Intent(context, TodoWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                data = Uri.parse("yata://widget/service/$appWidgetId")
            }
            views.setRemoteAdapter(R.id.widget_tasks_list_view, serviceIntent)
            views.setEmptyView(R.id.widget_tasks_list_view, R.id.widget_empty_list)

            // Item click template (mutable so fillInIntent can populate extras)
            val itemClickIntent = Intent(context, TodoWidgetProvider::class.java).apply {
                action = ACTION_WIDGET_ITEM_CLICK
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            }
            views.setPendingIntentTemplate(
                R.id.widget_tasks_list_view,
                PendingIntent.getBroadcast(
                    context,
                    appWidgetId * 10 + 3,
                    itemClickIntent,
                    mutableFlags(),
                ),
            )

            appWidgetManager.updateAppWidget(appWidgetId, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_tasks_list_view)
        }

        private fun immutableFlags(): Int {
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                flags = flags or PendingIntent.FLAG_IMMUTABLE
            }
            return flags
        }

        private fun mutableFlags(): Int {
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                flags = flags or PendingIntent.FLAG_MUTABLE
            }
            return flags
        }
    }
}
