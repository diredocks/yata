package top.clickfling.yata.sync

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import top.clickfling.yata.R
import top.clickfling.yata.widget.TodoWidgetData
import top.clickfling.yata.widget.TodoWidgetProvider
import java.util.concurrent.TimeUnit

/**
 * Unified WorkManager [CoroutineWorker] for Yata's background execution lanes:
 * - `metadata`: fast outbox push / delta sync (expedited when requested)
 * - `transfer`: attachment uploads & downloads promoted on-demand to a
 *   `dataSync` foreground service while active, then torn down automatically
 * - `widget`: Android home widget optimistic op processing & refresh
 */
class YataSyncWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result {
        val lane = inputData.getString(KEY_LANE) ?: LANE_METADATA
        val reason = inputData.getString(KEY_REASON) ?: "background"

        if (lane == LANE_TRANSFER) {
            runCatching { setForeground(createTransferForegroundInfo()) }
                .onFailure { Log.w(TAG, "Unable to promote transfer worker to foreground", it) }
        }

        val timeoutMs = if (lane == LANE_TRANSFER) TRANSFER_TIMEOUT_MS else METADATA_TIMEOUT_MS

        return try {
            val outcome = YataBackgroundEngineHost.runPass(
                context = applicationContext,
                lane = lane,
                reason = reason,
                timeoutMs = timeoutMs,
            )
            outcome.fold(
                onSuccess = { summary ->
                    if (summary.hasPendingTransfers && lane != LANE_TRANSFER) {
                        enqueue(
                            context = applicationContext,
                            lane = LANE_TRANSFER,
                            reason = "pending_transfers",
                            requiresNetwork = true,
                            expedited = false,
                        )
                    }
                    if (summary.shouldRetry) Result.retry() else Result.success()
                },
                onFailure = { error ->
                    if (error is CancellationException) throw error
                    Log.e(TAG, "YataSyncWorker failed (lane=$lane reason=$reason)", error)
                    Result.retry()
                },
            )
        } finally {
            if (lane == LANE_WIDGET) {
                withContext(NonCancellable) { clearWidgetRefreshingIfNeeded() }
            }
        }
    }

    private fun createTransferForegroundInfo(): ForegroundInfo {
        ensureNotificationChannel()
        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_todo_24)
            .setContentTitle(applicationContext.applicationInfo.loadLabel(applicationContext.packageManager))
            .setContentText("Syncing attachments in background")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(0, 0, true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(NOTIFICATION_ID, notification)
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = applicationContext.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Background Sync & Transfers",
            NotificationManager.IMPORTANCE_LOW,
        )
        manager.createNotificationChannel(channel)
    }

    private fun clearWidgetRefreshingIfNeeded() {
        if (TodoWidgetData.isRefreshing(applicationContext)) {
            TodoWidgetData.clearRefreshing(applicationContext)
            TodoWidgetProvider.refreshAllWidgets(applicationContext, notifyList = false)
        }
    }

    companion object {
        private const val TAG = "YataSyncWorker"
        const val LANE_METADATA = "metadata"
        const val LANE_TRANSFER = "transfer"
        const val LANE_WIDGET = "widget"

        private const val KEY_LANE = "lane"
        private const val KEY_REASON = "reason"
        private const val CHANNEL_ID = "yata_sync_transfers"
        private const val NOTIFICATION_ID = 41021

        private const val METADATA_TIMEOUT_MS = 30_000L
        private const val TRANSFER_TIMEOUT_MS = 180_000L

        fun enqueue(
            context: Context,
            lane: String,
            reason: String,
            requiresNetwork: Boolean = true,
            expedited: Boolean = false,
        ) {
            val builder = OneTimeWorkRequestBuilder<YataSyncWorker>()
                .setInputData(workDataOf(KEY_LANE to lane, KEY_REASON to reason))
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 10, TimeUnit.SECONDS)

            if (requiresNetwork) {
                builder.setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .build(),
                )
            }
            if (expedited && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            }

            val uniqueName = "yata_sync_$lane"
            val policy = if (lane == LANE_WIDGET) {
                ExistingWorkPolicy.APPEND_OR_REPLACE
            } else {
                ExistingWorkPolicy.KEEP
            }
            WorkManager.getInstance(context).enqueueUniqueWork(
                uniqueName,
                policy,
                builder.build(),
            )
        }
    }
}
