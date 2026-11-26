package top.clickfling.yata.widget

import android.content.Context
import android.os.Build
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import es.antonborri.home_widget.HomeWidgetPlugin
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

class WidgetSyncWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result {
        val reason = inputData.getString(KEY_REASON) ?: ""
        val dispatcherHandle = HomeWidgetPlugin.getDispatcherHandle(applicationContext)
        val callbackHandle = HomeWidgetPlugin.getHandle(applicationContext)
        if (dispatcherHandle == 0L || callbackHandle == 0L) {
            Log.w(TAG, "Missing home_widget callback handles; skipping background sync")
            clearRefreshingIfNeeded()
            return Result.success()
        }

        val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(dispatcherHandle)
        if (callbackInfo == null) {
            Log.w(TAG, "Failed to lookup FlutterCallbackInformation for handle=$dispatcherHandle")
            clearRefreshingIfNeeded()
            return Result.success()
        }

        val syncCompleted = CompletableDeferred<Unit>()
        var engine: FlutterEngine? = null

        return try {
            val uriString = "yata://widget/sync?reason=${android.net.Uri.encode(reason)}"
            withContext(Dispatchers.Main) {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(applicationContext)
                loader.ensureInitializationComplete(applicationContext, null)

                val createdEngine = FlutterEngine(applicationContext)
                engine = createdEngine

                val bgChannel = MethodChannel(
                    createdEngine.dartExecutor.binaryMessenger,
                    HOME_WIDGET_BG_CHANNEL,
                )
                bgChannel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "HomeWidget.backgroundInitialized" -> {
                            bgChannel.invokeMethod("", listOf(callbackHandle, uriString, callbackHandle))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }

                val syncChannel = MethodChannel(
                    createdEngine.dartExecutor.binaryMessenger,
                    WidgetSyncChannel.CHANNEL_NAME,
                )
                syncChannel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        WidgetSyncChannel.METHOD_BACKGROUND_SYNC_COMPLETED -> {
                            result.success(null)
                            syncCompleted.complete(Unit)
                        }
                        else -> result.notImplemented()
                    }
                }

                val callback = DartExecutor.DartCallback(
                    applicationContext.assets,
                    loader.findAppBundlePath(),
                    callbackInfo,
                )
                createdEngine.dartExecutor.executeDartCallback(callback)
            }

            val completed = withTimeoutOrNull(SYNC_TIMEOUT_MS) {
                syncCompleted.await()
            } != null

            if (!completed) {
                Log.w(TAG, "Widget background sync timed out after ${SYNC_TIMEOUT_MS}ms (reason=$reason)")
                Result.failure()
            } else {
                Result.success()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Widget background sync failed (reason=$reason)", e)
            Result.failure()
        } finally {
            withContext(NonCancellable) {
                val engineToDestroy = engine
                if (engineToDestroy != null) {
                    withContext(Dispatchers.Main) {
                        try {
                            engineToDestroy.destroy()
                        } catch (e: Exception) {
                            Log.w(TAG, "Error destroying background FlutterEngine", e)
                        }
                    }
                }
                clearRefreshingIfNeeded()
            }
        }
    }

    private fun clearRefreshingIfNeeded() {
        if (TodoWidgetData.isRefreshing(applicationContext)) {
            TodoWidgetData.clearRefreshing(applicationContext)
            TodoWidgetProvider.refreshAllWidgets(applicationContext, notifyList = false)
        }
    }

    companion object {
        private const val TAG = "WidgetSyncWorker"
        private const val UNIQUE_WORK_NAME = "yata_widget_sync"
        private const val HOME_WIDGET_BG_CHANNEL = "home_widget/background"
        private const val KEY_REASON = "reason"
        private const val SYNC_TIMEOUT_MS = 25_000L

        fun enqueue(context: Context, reason: String) {
            val builder = OneTimeWorkRequestBuilder<WidgetSyncWorker>()
                .setInputData(workDataOf(KEY_REASON to reason))

            if (reason == "refresh" && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            }

            WorkManager.getInstance(context).enqueueUniqueWork(
                UNIQUE_WORK_NAME,
                ExistingWorkPolicy.APPEND_OR_REPLACE,
                builder.build(),
            )
        }
    }
}
