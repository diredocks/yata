package top.clickfling.yata.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Paint
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import androidx.core.content.ContextCompat
import top.clickfling.yata.R

class TodoWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        val appWidgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        )
        return TodoWidgetRemoteViewsFactory(applicationContext, appWidgetId)
    }
}

private class TodoWidgetRemoteViewsFactory(
    private val context: Context,
    private val appWidgetId: Int,
) : RemoteViewsService.RemoteViewsFactory {

    private var config = WidgetConfig()
    private var resolvedListId = WidgetConfig.DEFAULT_LIST_ID
    private var isSmartList = true
    private var isMyDayList = true
    private var myDayLabel = ""
    private var listAccentColor: Int = 0
    private var tasks: List<WidgetTaskItem> = emptyList()

    override fun onCreate() {
        loadData()
    }

    override fun onDataSetChanged() {
        loadData()
    }

    override fun onDestroy() {
        tasks = emptyList()
    }

    private fun loadData() {
        config = TodoWidgetData.loadConfig(context, appWidgetId)
        val snapshot = TodoWidgetData.loadEffectiveSnapshot(context)
        val resolved = snapshot.resolveList(config.listId)
        resolvedListId = resolved?.id ?: config.listId
        isSmartList = resolved?.smartType != null
        isMyDayList = resolved?.smartType == "myDay" || resolvedListId == "my_day"
        val isNight = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES
        listAccentColor = (if (isNight) resolved?.accentColorDark else resolved?.accentColorLight)
            ?: ContextCompat.getColor(context, R.color.widget_accent)
        myDayLabel = snapshot.myDayLabel.takeIf { it.isNotBlank() }
            ?: context.getString(R.string.widget_my_day)
        tasks = TodoWidgetData.tasksForWidget(
            snapshot,
            config.copy(listId = resolvedListId),
        )
    }

    override fun getCount(): Int = tasks.size

    override fun getViewAt(position: Int): RemoteViews {
        if (position < 0 || position >= tasks.size) {
            return RemoteViews(context.packageName, R.layout.todo_widget_task_item)
        }

        val task = tasks[position]
        val views = RemoteViews(context.packageName, R.layout.todo_widget_task_item)

        // Task title & strikethrough (colors resolved via XML night/day resources)
        if (task.isCompleted) {
            views.setViewVisibility(R.id.widget_text_task, View.GONE)
            views.setViewVisibility(R.id.widget_text_task_completed, View.VISIBLE)
            views.setTextViewText(R.id.widget_text_task_completed, task.title)
            views.setTextViewTextSize(
                R.id.widget_text_task_completed,
                TypedValue.COMPLEX_UNIT_SP,
                config.fontSize.titleSp,
            )
            views.setInt(
                R.id.widget_text_task_completed,
                "setPaintFlags",
                Paint.STRIKE_THRU_TEXT_FLAG or Paint.ANTI_ALIAS_FLAG,
            )
        } else {
            views.setViewVisibility(R.id.widget_text_task, View.VISIBLE)
            views.setViewVisibility(R.id.widget_text_task_completed, View.GONE)
            views.setTextViewText(R.id.widget_text_task, task.title)
            views.setTextViewTextSize(
                R.id.widget_text_task,
                TypedValue.COMPLEX_UNIT_SP,
                config.fontSize.titleSp,
            )
        }

        // Checkbox & star icons follow current list accent color
        views.setImageViewResource(
            R.id.widget_completed_task,
            if (task.isCompleted) {
                R.drawable.ic_widget_checkbox_checked
            } else {
                R.drawable.ic_widget_checkbox_unchecked
            },
        )
        views.setInt(
            R.id.widget_completed_task,
            "setColorFilter",
            listAccentColor,
        )
        views.setImageViewResource(
            R.id.widget_important_task,
            if (task.isImportant) {
                R.drawable.ic_widget_star_filled
            } else {
                R.drawable.ic_widget_star_outline
            },
        )
        views.setInt(
            R.id.widget_important_task,
            "setColorFilter",
            listAccentColor,
        )

        // Metadata row
        val showMyDayChip = task.isInMyDay && !isMyDayList
        val showFolderChip = isSmartList && task.listTitle.isNotEmpty()
        val showDueChip = task.hasDueDate && task.dueLabel.isNotEmpty()
        val showRepeatChip = task.isRecurring
        val showReminderChip = task.hasReminder && task.reminderLabel.isNotEmpty()
        val hasVisibleMetadata = config.showMetadata &&
            (showMyDayChip || showFolderChip || showDueChip || showRepeatChip || showReminderChip)

        if (hasVisibleMetadata) {
            views.setViewVisibility(R.id.widget_task_metadata_container, View.VISIBLE)

            if (showMyDayChip) {
                views.setViewVisibility(R.id.my_day_indicator_icon, View.VISIBLE)
                views.setViewVisibility(R.id.my_day_indicator, View.VISIBLE)
                views.setTextViewText(R.id.my_day_indicator, myDayLabel)
                views.setTextViewTextSize(
                    R.id.my_day_indicator,
                    TypedValue.COMPLEX_UNIT_SP,
                    config.fontSize.metaSp,
                )
            } else {
                views.setViewVisibility(R.id.my_day_indicator_icon, View.GONE)
                views.setViewVisibility(R.id.my_day_indicator, View.GONE)
            }

            if (showFolderChip) {
                views.setViewVisibility(R.id.folder_indicator, View.VISIBLE)
                views.setTextViewText(R.id.folder_indicator, task.listTitle)
                views.setTextViewTextSize(
                    R.id.folder_indicator,
                    TypedValue.COMPLEX_UNIT_SP,
                    config.fontSize.metaSp,
                )
            } else {
                views.setViewVisibility(R.id.folder_indicator, View.GONE)
            }

            if (showDueChip) {
                views.setViewVisibility(R.id.duedate_indicator_icon, View.VISIBLE)
                val targetId = if (task.isOverdue) {
                    R.id.duedate_indicator_overdue
                } else {
                    R.id.duedate_indicator
                }
                val hiddenId = if (task.isOverdue) {
                    R.id.duedate_indicator
                } else {
                    R.id.duedate_indicator_overdue
                }
                views.setViewVisibility(targetId, View.VISIBLE)
                views.setViewVisibility(hiddenId, View.GONE)
                views.setTextViewText(targetId, task.dueLabel)
                views.setTextViewTextSize(
                    targetId,
                    TypedValue.COMPLEX_UNIT_SP,
                    config.fontSize.metaSp,
                )
            } else {
                views.setViewVisibility(R.id.duedate_indicator_icon, View.GONE)
                views.setViewVisibility(R.id.duedate_indicator, View.GONE)
                views.setViewVisibility(R.id.duedate_indicator_overdue, View.GONE)
            }

            views.setViewVisibility(
                R.id.recurrence_indicator,
                if (showRepeatChip) View.VISIBLE else View.GONE,
            )

            if (showReminderChip) {
                views.setViewVisibility(R.id.reminder_indicator, View.VISIBLE)
                views.setViewVisibility(R.id.reminder_label, View.VISIBLE)
                views.setTextViewText(R.id.reminder_label, task.reminderLabel)
                views.setTextViewTextSize(
                    R.id.reminder_label,
                    TypedValue.COMPLEX_UNIT_SP,
                    config.fontSize.metaSp,
                )
            } else {
                views.setViewVisibility(R.id.reminder_indicator, View.GONE)
                views.setViewVisibility(R.id.reminder_label, View.GONE)
            }
        } else {
            views.setViewVisibility(R.id.widget_task_metadata_container, View.GONE)
        }

        // Fill-in intents
        val completeFillIn = Intent().apply {
            putExtra(TodoWidgetProvider.EXTRA_ITEM_ACTION, TodoWidgetProvider.ITEM_ACTION_TOGGLE_COMPLETE)
            putExtra(TodoWidgetProvider.EXTRA_TASK_ID, task.id)
        }
        views.setOnClickFillInIntent(R.id.widget_completed_task, completeFillIn)

        val importantFillIn = Intent().apply {
            putExtra(TodoWidgetProvider.EXTRA_ITEM_ACTION, TodoWidgetProvider.ITEM_ACTION_TOGGLE_IMPORTANT)
            putExtra(TodoWidgetProvider.EXTRA_TASK_ID, task.id)
        }
        views.setOnClickFillInIntent(R.id.widget_important_task, importantFillIn)

        val openFillIn = Intent().apply {
            putExtra(TodoWidgetProvider.EXTRA_ITEM_ACTION, TodoWidgetProvider.ITEM_ACTION_OPEN_TASK)
            putExtra(TodoWidgetProvider.EXTRA_TASK_ID, task.id)
            putExtra(TodoWidgetProvider.EXTRA_LIST_ID, resolvedListId)
        }
        views.setOnClickFillInIntent(R.id.widget_task_text_container, openFillIn)

        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false
}
