package top.clickfling.yata.widget

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.BaseAdapter
import android.widget.ImageView
import android.widget.ListView
import android.widget.TextView
import androidx.core.content.ContextCompat
import top.clickfling.yata.R

class TodoWidgetFolderPickerActivity : Activity() {

    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private var returnResult = false

    private sealed interface PickerRow {
        data class Folder(val info: WidgetListInfo) : PickerRow
        data object Divider : PickerRow
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.todo_widget_folder_picker)

        appWidgetId = intent?.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        returnResult = intent?.getBooleanExtra(EXTRA_RETURN_RESULT, false) ?: false

        findViewById<View>(R.id.widget_picker_backdrop).setOnClickListener {
            finish()
        }

        val lists = TodoWidgetData.loadLists(this).ifEmpty {
            listOf(
                WidgetListInfo(
                    id = WidgetConfig.DEFAULT_LIST_ID,
                    title = getString(R.string.widget_my_day),
                    smartType = "myDay",
                    emoji = null,
                    activeCount = 0,
                ),
            )
        }

        val smartLists = lists.filter { it.smartType != null }
        val customLists = lists.filter { it.smartType == null }
        val rows = buildList {
            for (item in smartLists) add(PickerRow.Folder(item))
            if (smartLists.isNotEmpty() && customLists.isNotEmpty()) {
                add(PickerRow.Divider)
            }
            for (item in customLists) add(PickerRow.Folder(item))
        }

        val listView = findViewById<ListView>(R.id.widget_folder_list_view)
        listView.adapter = FolderAdapter(rows)
        listView.setOnItemClickListener { _, _, position, _ ->
            val row = rows[position]
            if (row !is PickerRow.Folder) return@setOnItemClickListener
            val selected = row.info
            if (returnResult) {
                setResult(
                    RESULT_OK,
                    Intent().putExtra(EXTRA_SELECTED_LIST_ID, selected.id),
                )
            } else if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                val prev = TodoWidgetData.loadConfig(this, appWidgetId)
                TodoWidgetData.saveConfig(this, appWidgetId, prev.copy(listId = selected.id))
                TodoWidgetProvider.updateAppWidget(
                    this,
                    AppWidgetManager.getInstance(this),
                    appWidgetId,
                )
            }
            finish()
        }

        // Cap bottom sheet height to 65% of screen height so long lists scroll cleanly.
        listView.post {
            val maxHeight = (resources.displayMetrics.heightPixels * 0.65f).toInt()
            if (listView.height > maxHeight) {
                listView.layoutParams = listView.layoutParams.apply { height = maxHeight }
            }
        }
    }

    private inner class FolderAdapter(
        private val rows: List<PickerRow>,
    ) : BaseAdapter() {
        override fun getCount(): Int = rows.size
        override fun getItem(position: Int): PickerRow = rows[position]
        override fun getItemId(position: Int): Long = position.toLong()
        override fun getViewTypeCount(): Int = 2
        override fun getItemViewType(position: Int): Int =
            if (rows[position] is PickerRow.Divider) 1 else 0

        override fun isEnabled(position: Int): Boolean = rows[position] is PickerRow.Folder

        override fun getView(position: Int, convertView: View?, parent: ViewGroup?): View {
            val row = rows[position]
            if (row is PickerRow.Divider) {
                return convertView ?: LayoutInflater.from(this@TodoWidgetFolderPickerActivity)
                    .inflate(R.layout.todo_widget_folder_divider, parent, false)
            }

            val item = (row as PickerRow.Folder).info
            val view = convertView ?: LayoutInflater.from(this@TodoWidgetFolderPickerActivity)
                .inflate(R.layout.todo_widget_folder_item, parent, false)

            val iconView = view.findViewById<ImageView>(R.id.widget_folder_icon)
            val emojiView = view.findViewById<TextView>(R.id.widget_folder_emoji)
            val titleView = view.findViewById<TextView>(R.id.widget_folder_title)
            val countView = view.findViewById<TextView>(R.id.widget_folder_count)

            if (!item.emoji.isNullOrBlank()) {
                iconView.visibility = View.GONE
                emojiView.visibility = View.VISIBLE
                emojiView.text = item.emoji
                titleView.text = item.title
            } else {
                emojiView.visibility = View.GONE
                iconView.visibility = View.VISIBLE
                iconView.setImageResource(iconResFor(item.smartType))
                val isNight =
                    (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                        Configuration.UI_MODE_NIGHT_YES
                val tint = (if (isNight) item.accentColorDark else item.accentColorLight)
                    ?: ContextCompat.getColor(
                        this@TodoWidgetFolderPickerActivity,
                        R.color.widget_accent,
                    )
                iconView.setColorFilter(tint)
                titleView.text = item.title
            }

            countView.text = if (item.activeCount > 0) item.activeCount.toString() else ""
            return view
        }

        private fun iconResFor(smartType: String?): Int {
            return when (smartType) {
                "myDay" -> R.drawable.ic_widget_list_my_day
                "important" -> R.drawable.ic_widget_list_important
                "planned" -> R.drawable.ic_widget_list_planned
                "all" -> R.drawable.ic_widget_list_all
                "completed" -> R.drawable.ic_widget_list_completed
                "tasks" -> R.drawable.ic_widget_list_tasks
                else -> R.drawable.ic_widget_list_default
            }
        }
    }

    companion object {
        const val EXTRA_RETURN_RESULT = "extra_return_result"
        const val EXTRA_SELECTED_LIST_ID = "extra_selected_list_id"
    }
}
