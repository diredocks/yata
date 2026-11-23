package top.clickfling.yata.widget

import android.content.Context
import android.content.SharedPreferences
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONObject

data class WidgetListInfo(
    val id: String,
    val title: String,
    val smartType: String?,
    val emoji: String?,
    val activeCount: Int,
    val accentColorLight: Int? = null,
    val accentColorDark: Int? = null,
) {
    val displayTitle: String
        get() = if (!emoji.isNullOrBlank()) "$emoji $title" else title
}

data class WidgetTaskItem(
    val id: String,
    val listId: String,
    val listTitle: String,
    val title: String,
    val isCompleted: Boolean,
    val isImportant: Boolean,
    val isInMyDay: Boolean,
    val hasDueDate: Boolean,
    val hasReminder: Boolean,
    val isRecurring: Boolean,
    val isOverdue: Boolean,
    val dueLabel: String,
    val reminderLabel: String,
) {
    val hasMetadata: Boolean
        get() = isInMyDay || listTitle.isNotEmpty() || hasDueDate || hasReminder || isRecurring
}

enum class WidgetFontSize(val value: String, val titleSp: Float, val metaSp: Float) {
    SMALL("small", 13f, 11f),
    MEDIUM("medium", 15f, 12f),
    LARGE("large", 17f, 13f);

    companion object {
        fun fromValue(raw: String?): WidgetFontSize {
            return entries.firstOrNull { it.value == raw } ?: MEDIUM
        }
    }
}

data class WidgetConfig(
    val listId: String = DEFAULT_LIST_ID,
    val opacityPercent: Int = DEFAULT_OPACITY_PERCENT,
    val fontSize: WidgetFontSize = WidgetFontSize.MEDIUM,
    val showCompleted: Boolean = false,
    val showMetadata: Boolean = false,
) {
    companion object {
        const val DEFAULT_LIST_ID = "my_day"
        const val DEFAULT_OPACITY_PERCENT = 90
    }
}

object TodoWidgetData {
    private const val KEY_LISTS = "widget_lists_json"
    private const val KEY_TASKS = "widget_tasks_json"
    private const val KEY_LIST_TASK_IDS = "widget_list_task_ids_json"
    private const val KEY_ACCOUNT_NAME = "widget_account_name"
    private const val KEY_EMPTY_MESSAGE = "widget_empty_message"
    private const val KEY_MY_DAY_LABEL = "widget_my_day_label"
    private const val KEY_MOVE_STARRED_TO_TOP = "widget_move_starred_to_top"
    private const val KEY_IS_REFRESHING = "widget_is_refreshing"

    private const val CONFIG_PREFS_NAME = "yata_widget_configs"

    fun prefs(context: Context): SharedPreferences = HomeWidgetPlugin.getData(context)

    private fun configPrefs(context: Context): SharedPreferences =
        context.getSharedPreferences(CONFIG_PREFS_NAME, Context.MODE_PRIVATE)

    fun loadConfig(context: Context, appWidgetId: Int): WidgetConfig {
        val p = configPrefs(context)
        return WidgetConfig(
            listId = p.getString("w_${appWidgetId}_list_id", WidgetConfig.DEFAULT_LIST_ID)
                ?: WidgetConfig.DEFAULT_LIST_ID,
            opacityPercent = p.getInt(
                "w_${appWidgetId}_opacity",
                WidgetConfig.DEFAULT_OPACITY_PERCENT,
            ).coerceIn(20, 100),
            fontSize = WidgetFontSize.fromValue(
                p.getString("w_${appWidgetId}_font_size", WidgetFontSize.MEDIUM.value),
            ),
            showCompleted = p.getBoolean("w_${appWidgetId}_show_completed", false),
            showMetadata = p.getBoolean("w_${appWidgetId}_show_metadata", false),
        )
    }

    fun saveConfig(context: Context, appWidgetId: Int, config: WidgetConfig) {
        configPrefs(context).edit()
            .putString("w_${appWidgetId}_list_id", config.listId)
            .putInt("w_${appWidgetId}_opacity", config.opacityPercent.coerceIn(20, 100))
            .putString("w_${appWidgetId}_font_size", config.fontSize.value)
            .putBoolean("w_${appWidgetId}_show_completed", config.showCompleted)
            .putBoolean("w_${appWidgetId}_show_metadata", config.showMetadata)
            .apply()
    }

    fun deleteConfig(context: Context, appWidgetId: Int) {
        configPrefs(context).edit()
            .remove("w_${appWidgetId}_list_id")
            .remove("w_${appWidgetId}_opacity")
            .remove("w_${appWidgetId}_font_size")
            .remove("w_${appWidgetId}_show_completed")
            .remove("w_${appWidgetId}_show_metadata")
            .apply()
    }

    fun loadLists(context: Context): List<WidgetListInfo> {
        val raw = prefs(context).getString(KEY_LISTS, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            buildList(array.length()) {
                for (i in 0 until array.length()) {
                    val obj = array.optJSONObject(i) ?: continue
                    add(
                        WidgetListInfo(
                            id = obj.optString("id"),
                            title = obj.optString("title"),
                            smartType = obj.optString("smartType").takeIf { it.isNotEmpty() && it != "null" },
                            emoji = obj.optString("emoji").takeIf { it.isNotEmpty() && it != "null" },
                            activeCount = obj.optInt("activeCount", 0),
                            accentColorLight = if (obj.has("accentColorLight") && !obj.isNull("accentColorLight")) {
                                obj.optInt("accentColorLight")
                            } else {
                                null
                            },
                            accentColorDark = if (obj.has("accentColorDark") && !obj.isNull("accentColorDark")) {
                                obj.optInt("accentColorDark")
                            } else {
                                null
                            },
                        ),
                    )
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun resolveList(context: Context, listId: String): WidgetListInfo? {
        val lists = loadLists(context)
        return lists.firstOrNull { it.id == listId }
            ?: lists.firstOrNull { it.id == WidgetConfig.DEFAULT_LIST_ID }
            ?: lists.firstOrNull()
    }

    fun loadAccountName(context: Context): String? {
        return prefs(context).getString(KEY_ACCOUNT_NAME, null)?.takeIf { it.isNotBlank() }
    }

    fun loadEmptyMessage(context: Context): String? {
        return prefs(context).getString(KEY_EMPTY_MESSAGE, null)?.takeIf { it.isNotBlank() }
    }

    fun loadMyDayLabel(context: Context): String? {
        return prefs(context).getString(KEY_MY_DAY_LABEL, null)?.takeIf { it.isNotBlank() }
    }

    fun isRefreshing(context: Context): Boolean {
        return prefs(context).getBoolean(KEY_IS_REFRESHING, false)
    }

    fun setRefreshing(context: Context, refreshing: Boolean) {
        prefs(context).edit().putBoolean(KEY_IS_REFRESHING, refreshing).apply()
    }

    fun loadTasksForWidget(context: Context, config: WidgetConfig): List<WidgetTaskItem> {
        val p = prefs(context)
        val tasksRaw = p.getString(KEY_TASKS, null) ?: return emptyList()
        val listTaskIdsRaw = p.getString(KEY_LIST_TASK_IDS, null)
        return try {
            val tasksArray = JSONArray(tasksRaw)
            val taskMap = HashMap<String, WidgetTaskItem>(tasksArray.length())
            val fallbackTasks = ArrayList<WidgetTaskItem>(tasksArray.length())
            for (i in 0 until tasksArray.length()) {
                val obj = tasksArray.optJSONObject(i) ?: continue
                val item = parseTask(obj)
                taskMap[item.id] = item
                fallbackTasks.add(item)
            }

            val orderedTasks: List<WidgetTaskItem> = if (listTaskIdsRaw != null) {
                val mapObj = JSONObject(listTaskIdsRaw)
                val idsArray = mapObj.optJSONArray(config.listId)
                    ?: mapObj.optJSONArray(WidgetConfig.DEFAULT_LIST_ID)
                if (idsArray != null) {
                    buildList(idsArray.length()) {
                        for (i in 0 until idsArray.length()) {
                            val id = idsArray.optString(i)
                            taskMap[id]?.let { add(it) }
                        }
                    }
                } else {
                    fallbackTasks.filter { it.listId == config.listId }
                }
            } else {
                fallbackTasks.filter { it.listId == config.listId }
            }

            if (config.showCompleted || config.listId == "completed") {
                orderedTasks
            } else {
                orderedTasks.filter { !it.isCompleted }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun optimisticToggleComplete(context: Context, taskId: String): Boolean? {
        return updateTaskField(context, taskId) { obj ->
            val next = !obj.optBoolean("isCompleted", false)
            obj.put("isCompleted", next)
            next
        }
    }

    fun optimisticToggleImportant(context: Context, taskId: String): Boolean? {
        val next = updateTaskField(context, taskId) { obj ->
            val value = !obj.optBoolean("isImportant", false)
            obj.put("isImportant", value)
            value
        } ?: return null

        updateListTaskIdsOnImportantChange(context, taskId, next)
        return next
    }

    private fun updateListTaskIdsOnImportantChange(
        context: Context,
        taskId: String,
        isImportant: Boolean,
    ) {
        val p = prefs(context)
        val raw = p.getString(KEY_LIST_TASK_IDS, null) ?: return
        val moveStarredToTop = p.getBoolean(KEY_MOVE_STARRED_TO_TOP, true)
        try {
            val mapObj = JSONObject(raw)
            var changed = false
            val keys = mapObj.keys()
            while (keys.hasNext()) {
                val listId = keys.next()
                val arr = mapObj.optJSONArray(listId) ?: continue
                if (listId == "important") {
                    val updated = JSONArray()
                    if (isImportant) {
                        updated.put(taskId)
                    }
                    for (i in 0 until arr.length()) {
                        val id = arr.optString(i)
                        if (id != taskId) {
                            updated.put(id)
                        }
                    }
                    mapObj.put(listId, updated)
                    changed = true
                } else if (isImportant && moveStarredToTop) {
                    var found = false
                    for (i in 0 until arr.length()) {
                        if (arr.optString(i) == taskId) {
                            found = true
                            break
                        }
                    }
                    if (found) {
                        val updated = JSONArray()
                        updated.put(taskId)
                        for (i in 0 until arr.length()) {
                            val id = arr.optString(i)
                            if (id != taskId) {
                                updated.put(id)
                            }
                        }
                        mapObj.put(listId, updated)
                        changed = true
                    }
                }
            }
            if (changed) {
                p.edit().putString(KEY_LIST_TASK_IDS, mapObj.toString()).apply()
            }
        } catch (_: Exception) {
            // Best-effort optimistic reorder.
        }
    }

    private fun updateTaskField(
        context: Context,
        taskId: String,
        mutator: (JSONObject) -> Boolean,
    ): Boolean? {
        val p = prefs(context)
        val tasksRaw = p.getString(KEY_TASKS, null) ?: return null
        return try {
            val tasksArray = JSONArray(tasksRaw)
            var result: Boolean? = null
            for (i in 0 until tasksArray.length()) {
                val obj = tasksArray.optJSONObject(i) ?: continue
                if (obj.optString("id") == taskId) {
                    result = mutator(obj)
                    break
                }
            }
            if (result != null) {
                p.edit().putString(KEY_TASKS, tasksArray.toString()).apply()
            }
            result
        } catch (_: Exception) {
            null
        }
    }

    private fun parseTask(obj: JSONObject): WidgetTaskItem {
        return WidgetTaskItem(
            id = obj.optString("id"),
            listId = obj.optString("listId"),
            listTitle = obj.optString("listTitle"),
            title = obj.optString("title"),
            isCompleted = obj.optBoolean("isCompleted", false),
            isImportant = obj.optBoolean("isImportant", false),
            isInMyDay = obj.optBoolean("isInMyDay", false),
            hasDueDate = obj.optBoolean("hasDueDate", false),
            hasReminder = obj.optBoolean("hasReminder", false),
            isRecurring = obj.optBoolean("isRecurring", false),
            isOverdue = obj.optBoolean("isOverdue", false),
            dueLabel = obj.optString("dueLabel"),
            reminderLabel = obj.optString("reminderLabel"),
        )
    }
}
