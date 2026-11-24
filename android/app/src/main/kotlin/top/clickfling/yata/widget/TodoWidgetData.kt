package top.clickfling.yata.widget

import android.content.Context
import android.content.SharedPreferences
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit

data class WidgetListInfo(
    val id: String,
    val title: String,
    val smartType: String?,
    val emoji: String?,
    val activeCount: Int,
    val sortOption: String = "defaultOrder",
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
    val dueDateYmd: String? = null,
    val hasReminder: Boolean,
    val reminderAtMs: Long? = null,
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

data class WidgetPendingOp(
    val opId: Int,
    val type: String,
    val taskId: String,
    val value: Boolean,
    val accountId: String?,
    val timestampMs: Long,
)

data class WidgetSnapshot(
    val accountId: String? = null,
    val accountName: String = "",
    val dateKey: String = "",
    val emptyMessage: String = "",
    val myDayLabel: String = "",
    val todayLabel: String = "",
    val tomorrowLabel: String = "",
    val yesterdayLabel: String = "",
    val moveStarredToTop: Boolean = true,
    val lists: List<WidgetListInfo> = emptyList(),
    val tasks: List<WidgetTaskItem> = emptyList(),
    val listTaskIds: Map<String, List<String>> = emptyMap(),
) {
    fun resolveList(listId: String): WidgetListInfo? {
        return lists.firstOrNull { it.id == listId }
            ?: lists.firstOrNull { it.id == WidgetConfig.DEFAULT_LIST_ID }
            ?: lists.firstOrNull()
    }
}

object TodoWidgetData {
    const val OP_TOGGLE_COMPLETE = "toggle_complete"
    const val OP_TOGGLE_IMPORTANT = "toggle_important"

    private const val KEY_SNAPSHOT = "widget_snapshot_json"
    private const val KEY_PENDING_OPS = "widget_pending_ops_json"
    private const val KEY_NEXT_OP_ID = "widget_next_op_id"
    private const val KEY_ACKED_OP_ID = "widget_acked_op_id"
    private const val KEY_REFRESH_REQUESTED = "widget_refresh_requested"
    private const val KEY_IS_REFRESHING = "widget_is_refreshing"
    private const val KEY_REFRESH_STARTED_MS = "widget_refresh_started_ms"

    private const val CONFIG_PREFS_NAME = "yata_widget_configs"
    private const val REFRESH_TIMEOUT_MS = 30_000L

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

    fun currentLocalDateYmd(): String {
        return SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
    }

    private fun readAckedOpId(p: SharedPreferences): Int {
        return (p.all[KEY_ACKED_OP_ID] as? Number)?.toInt() ?: 0
    }

    fun loadEffectiveSnapshot(context: Context): WidgetSnapshot {
        val p = prefs(context)
        val base = loadBaseSnapshot(p)
        val ackedOpId = readAckedOpId(p)
        val pendingOps = loadPendingOps(p)
            .filter { it.opId > ackedOpId }
            .sortedBy { it.opId }
        val listById = base.lists.associateBy { it.id }

        val taskOrder = ArrayList<String>(base.tasks.size)
        val tasksById = LinkedHashMap<String, WidgetTaskItem>(base.tasks.size)
        for (task in base.tasks) {
            taskOrder.add(task.id)
            tasksById[task.id] = task
        }

        val mutableListTaskIds = LinkedHashMap<String, MutableList<String>>(base.listTaskIds.size)
        for ((listId, ids) in base.listTaskIds) {
            mutableListTaskIds[listId] = ids.toMutableList()
        }

        for (op in pendingOps) {
            if (op.accountId != null && base.accountId != null && op.accountId != base.accountId) {
                continue
            }
            val current = tasksById[op.taskId] ?: continue
            when (op.type) {
                OP_TOGGLE_COMPLETE -> {
                    tasksById[op.taskId] = current.copy(isCompleted = op.value)
                    mutableListTaskIds["completed"]?.let { ids ->
                        ids.remove(op.taskId)
                        if (op.value) ids.add(0, op.taskId)
                    }
                    mutableListTaskIds["all"]?.let { ids ->
                        ids.remove(op.taskId)
                        if (!op.value) ids.add(0, op.taskId)
                    }
                }

                OP_TOGGLE_IMPORTANT -> {
                    tasksById[op.taskId] = current.copy(isImportant = op.value)
                    mutableListTaskIds["important"]?.let { ids ->
                        ids.remove(op.taskId)
                        if (op.value) ids.add(0, op.taskId)
                    }
                    if (op.value && base.moveStarredToTop) {
                        for ((listId, ids) in mutableListTaskIds) {
                            if (listId == "important") continue
                            val listInfo = listById[listId]
                            if (listInfo?.smartType == "completed") continue
                            val sortOption = listInfo?.sortOption ?: "defaultOrder"
                            if (sortOption == "defaultOrder" && ids.contains(op.taskId)) {
                                ids.remove(op.taskId)
                                ids.add(0, op.taskId)
                            }
                        }
                    }
                }
            }
        }

        val todayDay = parseYmdEpochDays(currentLocalDateYmd())
        if (todayDay != null) {
            for (id in taskOrder) {
                val task = tasksById[id] ?: continue
                val dueYmd = task.dueDateYmd ?: continue
                val dueDay = parseYmdEpochDays(dueYmd) ?: continue
                val dynamicOverdue = !task.isCompleted && dueDay < todayDay
                val dynamicDueLabel = computeDynamicDueLabel(
                    task = task,
                    dueDay = dueDay,
                    todayDay = todayDay,
                    dueYmd = dueYmd,
                    snapshot = base,
                )
                if (dynamicOverdue != task.isOverdue || dynamicDueLabel != task.dueLabel) {
                    tasksById[id] = task.copy(
                        isOverdue = dynamicOverdue,
                        dueLabel = dynamicDueLabel,
                    )
                }
            }
        }

        val finalTasks = taskOrder.mapNotNull { tasksById[it] }
        val finalListTaskIds = mutableListTaskIds.mapValues { it.value.toList() }
        val finalLists = base.lists.map { list ->
            val ids = finalListTaskIds[list.id] ?: emptyList()
            val count = if (list.smartType == "completed") {
                ids.count { tasksById.containsKey(it) }
            } else {
                ids.count { id -> tasksById[id]?.isCompleted == false }
            }
            list.copy(activeCount = count)
        }

        return base.copy(
            lists = finalLists,
            tasks = finalTasks,
            listTaskIds = finalListTaskIds,
        )
    }

    fun tasksForWidget(snapshot: WidgetSnapshot, config: WidgetConfig): List<WidgetTaskItem> {
        val taskMap = snapshot.tasks.associateBy { it.id }
        val ids = snapshot.listTaskIds[config.listId]
            ?: snapshot.listTaskIds[WidgetConfig.DEFAULT_LIST_ID]
            ?: return emptyList()
        val orderedTasks = ids.mapNotNull { taskMap[it] }
        val effectiveList = snapshot.lists.firstOrNull { it.id == config.listId }
        val isCompletedList =
            effectiveList?.smartType == "completed" || config.listId == "completed"
        return if (config.showCompleted || isCompletedList) {
            orderedTasks
        } else {
            orderedTasks.filter { !it.isCompleted }
        }
    }

    fun isRefreshing(context: Context): Boolean {
        val p = prefs(context)
        if (!p.getBoolean(KEY_IS_REFRESHING, false)) return false
        val startedMs = (p.all[KEY_REFRESH_STARTED_MS] as? Number)?.toLong() ?: 0L
        if (startedMs > 0L && System.currentTimeMillis() - startedMs > REFRESH_TIMEOUT_MS) {
            p.edit()
                .putBoolean(KEY_IS_REFRESHING, false)
                .remove(KEY_REFRESH_STARTED_MS)
                .apply()
            return false
        }
        return true
    }

    fun markRefreshRequested(context: Context) {
        prefs(context).edit()
            .putBoolean(KEY_REFRESH_REQUESTED, true)
            .putBoolean(KEY_IS_REFRESHING, true)
            .putLong(KEY_REFRESH_STARTED_MS, System.currentTimeMillis())
            .commit()
    }

    fun isDateStale(context: Context): Boolean {
        val base = loadBaseSnapshot(prefs(context))
        return base.dateKey.isNotEmpty() && base.dateKey != currentLocalDateYmd()
    }

    fun enqueueOptimisticOp(
        context: Context,
        type: String,
        taskId: String,
    ): WidgetPendingOp? {
        if (type != OP_TOGGLE_COMPLETE && type != OP_TOGGLE_IMPORTANT) return null
        val snapshot = loadEffectiveSnapshot(context)
        val task = snapshot.tasks.firstOrNull { it.id == taskId } ?: return null
        val nextValue = when (type) {
            OP_TOGGLE_COMPLETE -> !task.isCompleted
            OP_TOGGLE_IMPORTANT -> !task.isImportant
            else -> return null
        }

        val p = prefs(context)
        val ackedOpId = readAckedOpId(p)
        val unackedOps = loadPendingOps(p).filter { it.opId > ackedOpId }
        val nextOpId = ((p.all[KEY_NEXT_OP_ID] as? Number)?.toInt() ?: 0) + 1
        val op = WidgetPendingOp(
            opId = nextOpId,
            type = type,
            taskId = taskId,
            value = nextValue,
            accountId = snapshot.accountId,
            timestampMs = System.currentTimeMillis(),
        )
        p.edit()
            .putInt(KEY_NEXT_OP_ID, nextOpId)
            .putString(KEY_PENDING_OPS, encodeOps(unackedOps + op))
            .commit()
        return op
    }

    private fun computeDynamicDueLabel(
        task: WidgetTaskItem,
        dueDay: Long,
        todayDay: Long,
        dueYmd: String,
        snapshot: WidgetSnapshot,
    ): String {
        val diff = dueDay - todayDay
        if (diff == 0L && snapshot.todayLabel.isNotEmpty()) return snapshot.todayLabel
        if (diff == 1L && snapshot.tomorrowLabel.isNotEmpty()) return snapshot.tomorrowLabel
        if (diff == -1L && snapshot.yesterdayLabel.isNotEmpty()) return snapshot.yesterdayLabel
        val wasRelativeLabel =
            task.dueLabel.isNotEmpty() &&
                (task.dueLabel == snapshot.todayLabel ||
                    task.dueLabel == snapshot.tomorrowLabel ||
                    task.dueLabel == snapshot.yesterdayLabel)
        if (wasRelativeLabel) {
            return formatMonthDayFallback(dueYmd) ?: task.dueLabel
        }
        return task.dueLabel
    }

    private fun parseYmdEpochDays(ymd: String): Long? {
        val parts = ymd.split("-")
        if (parts.size != 3) return null
        val year = parts[0].toIntOrNull() ?: return null
        val month = parts[1].toIntOrNull() ?: return null
        val day = parts[2].toIntOrNull() ?: return null
        val cal = Calendar.getInstance(TimeZone.getTimeZone("UTC")).apply {
            clear()
            set(year, month - 1, day, 0, 0, 0)
        }
        return TimeUnit.MILLISECONDS.toDays(cal.timeInMillis)
    }

    private fun formatMonthDayFallback(ymd: String): String? {
        val parts = ymd.split("-")
        if (parts.size != 3) return null
        val year = parts[0].toIntOrNull() ?: return null
        val month = parts[1].toIntOrNull() ?: return null
        val day = parts[2].toIntOrNull() ?: return null
        val cal = Calendar.getInstance().apply {
            clear()
            set(year, month - 1, day, 12, 0, 0)
        }
        return SimpleDateFormat("MMM d", Locale.getDefault()).format(cal.time)
    }

    private fun loadBaseSnapshot(p: SharedPreferences): WidgetSnapshot {
        val raw = p.getString(KEY_SNAPSHOT, null)
        if (raw.isNullOrBlank()) return WidgetSnapshot()
        return try {
            parseSnapshot(JSONObject(raw))
        } catch (_: Exception) {
            WidgetSnapshot()
        }
    }

    private fun parseSnapshot(obj: JSONObject): WidgetSnapshot {
        val listsArray = obj.optJSONArray("lists")
        val lists = if (listsArray != null) parseLists(listsArray) else emptyList()
        val tasksArray = obj.optJSONArray("tasks")
        val tasks = if (tasksArray != null) parseTasks(tasksArray) else emptyList()
        val listTaskIdsObj = obj.optJSONObject("listTaskIds")
        val listTaskIds = if (listTaskIdsObj != null) {
            parseListTaskIds(listTaskIdsObj)
        } else {
            emptyMap()
        }
        return WidgetSnapshot(
            accountId = obj.optNullableString("accountId"),
            accountName = obj.optNullableString("accountName") ?: "",
            dateKey = obj.optNullableString("dateKey") ?: "",
            emptyMessage = obj.optNullableString("emptyMessage") ?: "",
            myDayLabel = obj.optNullableString("myDayLabel") ?: "",
            todayLabel = obj.optNullableString("todayLabel") ?: "",
            tomorrowLabel = obj.optNullableString("tomorrowLabel") ?: "",
            yesterdayLabel = obj.optNullableString("yesterdayLabel") ?: "",
            moveStarredToTop = obj.optBoolean("moveStarredToTop", true),
            lists = lists,
            tasks = tasks,
            listTaskIds = listTaskIds,
        )
    }

    private fun parseLists(array: JSONArray): List<WidgetListInfo> {
        return buildList(array.length()) {
            for (i in 0 until array.length()) {
                val obj = array.optJSONObject(i) ?: continue
                add(
                    WidgetListInfo(
                        id = obj.optString("id"),
                        title = obj.optString("title"),
                        smartType = obj.optNullableString("smartType"),
                        emoji = obj.optNullableString("emoji"),
                        activeCount = obj.optInt("activeCount", 0),
                        sortOption = obj.optNullableString("sortOption") ?: "defaultOrder",
                        accentColorLight = obj.optNullableInt("accentColorLight"),
                        accentColorDark = obj.optNullableInt("accentColorDark"),
                    ),
                )
            }
        }
    }

    private fun parseTasks(array: JSONArray): List<WidgetTaskItem> {
        return buildList(array.length()) {
            for (i in 0 until array.length()) {
                val obj = array.optJSONObject(i) ?: continue
                add(parseTask(obj))
            }
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
            dueDateYmd = obj.optNullableString("dueDateYmd"),
            hasReminder = obj.optBoolean("hasReminder", false),
            reminderAtMs = obj.optNullableLong("reminderAtMs"),
            isRecurring = obj.optBoolean("isRecurring", false),
            isOverdue = obj.optBoolean("isOverdue", false),
            dueLabel = obj.optString("dueLabel"),
            reminderLabel = obj.optString("reminderLabel"),
        )
    }

    private fun parseListTaskIds(mapObj: JSONObject): Map<String, List<String>> {
        val result = LinkedHashMap<String, List<String>>()
        val keys = mapObj.keys()
        while (keys.hasNext()) {
            val listId = keys.next()
            val arr = mapObj.optJSONArray(listId) ?: continue
            result[listId] = buildList(arr.length()) {
                for (i in 0 until arr.length()) {
                    val id = arr.optString(i)
                    if (id.isNotEmpty()) add(id)
                }
            }
        }
        return result
    }

    private fun loadPendingOps(p: SharedPreferences): List<WidgetPendingOp> {
        val raw = p.getString(KEY_PENDING_OPS, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            buildList(array.length()) {
                for (i in 0 until array.length()) {
                    val obj = array.optJSONObject(i) ?: continue
                    val opId = obj.optInt("opId", 0)
                    val type = obj.optNullableString("type") ?: continue
                    val taskId = obj.optNullableString("taskId") ?: continue
                    if (opId <= 0) continue
                    add(
                        WidgetPendingOp(
                            opId = opId,
                            type = type,
                            taskId = taskId,
                            value = obj.optBoolean("value", false),
                            accountId = obj.optNullableString("accountId"),
                            timestampMs = obj.optLong("timestampMs", 0L),
                        ),
                    )
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun encodeOps(ops: List<WidgetPendingOp>): String {
        val array = JSONArray()
        for (op in ops) {
            val obj = JSONObject().apply {
                put("opId", op.opId)
                put("type", op.type)
                put("taskId", op.taskId)
                put("value", op.value)
                if (op.accountId != null) {
                    put("accountId", op.accountId)
                } else {
                    put("accountId", JSONObject.NULL)
                }
                put("timestampMs", op.timestampMs)
            }
            array.put(obj)
        }
        return array.toString()
    }

    private fun JSONObject.optNullableString(key: String): String? {
        if (!has(key) || isNull(key)) return null
        val value = optString(key)
        return value.takeIf { it.isNotEmpty() && it != "null" }
    }

    private fun JSONObject.optNullableInt(key: String): Int? {
        return if (has(key) && !isNull(key)) optInt(key) else null
    }

    private fun JSONObject.optNullableLong(key: String): Long? {
        return if (has(key) && !isNull(key)) optLong(key) else null
    }
}
