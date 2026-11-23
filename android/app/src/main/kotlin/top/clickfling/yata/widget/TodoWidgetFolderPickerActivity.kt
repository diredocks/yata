package top.clickfling.yata.widget

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.BaseAdapter
import android.widget.ListView
import android.widget.TextView
import top.clickfling.yata.R

class TodoWidgetFolderPickerActivity : Activity() {

    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private var returnResult = false

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

        val listView = findViewById<ListView>(R.id.widget_folder_list_view)
        listView.adapter = FolderAdapter(lists)
        listView.setOnItemClickListener { _, _, position, _ ->
            val selected = lists[position]
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
    }

    private inner class FolderAdapter(
        private val items: List<WidgetListInfo>,
    ) : BaseAdapter() {
        override fun getCount(): Int = items.size
        override fun getItem(position: Int): WidgetListInfo = items[position]
        override fun getItemId(position: Int): Long = position.toLong()

        override fun getView(position: Int, convertView: View?, parent: ViewGroup?): View {
            val view = convertView ?: LayoutInflater.from(this@TodoWidgetFolderPickerActivity)
                .inflate(R.layout.todo_widget_folder_item, parent, false)
            val item = items[position]
            view.findViewById<TextView>(R.id.widget_folder_title).text = item.displayTitle
            val countView = view.findViewById<TextView>(R.id.widget_folder_count)
            countView.text = if (item.activeCount > 0) item.activeCount.toString() else ""
            return view
        }
    }

    companion object {
        const val EXTRA_RETURN_RESULT = "extra_return_result"
        const val EXTRA_SELECTED_LIST_ID = "extra_selected_list_id"
    }
}
