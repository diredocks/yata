package top.clickfling.yata.widget

import android.content.Context
import android.net.Uri
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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.TimeoutException

private typealias KotlinResult<T> = kotlin.Result<T>

class WidgetSyncWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : CoroutineWorker(appContext, workerParams) {

    private data class CallbackHandles(
        val dispatcherHandle: Long,
        val callbackHandle: Long,
    )

    override suspend fun doWork(): Result {
        val reason = inputData.getString(KEY_REASON) ?: ""
        val handles = resolveHandles().getOrElse { error ->
            Log.w(TAG, error.message ?: "Missing home_widget callback handles; skipping sync")
            clearRefreshingIfNeeded()
            return Result.success()
        }

        val syncCompleted = CompletableDeferred<Unit>()
        var engine: FlutterEngine? = null

        return try {
            runSync(reason, handles, syncCompleted) { engine = it }.fold(
                onSuccess = { Result.success() },
                onFailure = { error ->
                    Log.e(TAG, "Widget background sync failed (reason=$reason)", error)
                    Result.failure()
                },
            )
        } finally {
            withContext(NonCancellable) {
                destroyEngine(engine)
                clearRefreshingIfNeeded()
            }
        }
    }

    private fun resolveHandles(): KotlinResult<CallbackHandles> {
        val dispatcher = HomeWidgetPlugin.getDispatcherHandle(applicationContext)
        val callback = HomeWidgetPlugin.getHandle(applicationContext)
        if (dispatcher == 0L || callback == 0L) {
            return KotlinResult.failure(
                IllegalStateException("Missing home_widget callback handles; skipping background sync"),
            )
        }
        return KotlinResult.success(CallbackHandles(dispatcher, callback))
    }

    private suspend fun runSync(
        reason: String,
        handles: CallbackHandles,
        syncCompleted: CompletableDeferred<Unit>,
        onEngineCreated: (FlutterEngine) -> Unit,
    ): KotlinResult<Unit> = runCatching {
        val uriString = "yata://widget/sync?reason=${Uri.encode(reason)}"
        val started = startEngineOnMain(handles, uriString, syncCompleted, onEngineCreated)
        if (!started) {
            Log.w(TAG, "Failed to lookup FlutterCallbackInformation for handle=${handles.dispatcherHandle}")
            return KotlinResult.success(Unit)
        }

        val completed = withTimeoutOrNull(SYNC_TIMEOUT_MS) { syncCompleted.await() } != null
        if (!completed) {
            throw TimeoutException("Widget background sync timed out after ${SYNC_TIMEOUT_MS}ms")
        }
    }.onFailure { error ->
        if (error is CancellationException) throw error
    }

    private suspend fun startEngineOnMain(
        handles: CallbackHandles,
        uriString: String,
        syncCompleted: CompletableDeferred<Unit>,
        onEngineCreated: (FlutterEngine) -> Unit,
    ): Boolean = withContext(Dispatchers.Main) {
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)

        val callbackInfo =
            FlutterCallbackInformation.lookupCallbackInformation(handles.dispatcherHandle)
                ?: return@withContext false

        val createdEngine = FlutterEngine(applicationContext)
        onEngineCreated(createdEngine)
        registerChannels(createdEngine, handles.callbackHandle, uriString, syncCompleted)

        val callback = DartExecutor.DartCallback(
            applicationContext.assets,
            loader.findAppBundlePath(),
            callbackInfo,
        )
        createdEngine.dartExecutor.executeDartCallback(callback)
        true
    }

    private fun registerChannels(
        engine: FlutterEngine,
        callbackHandle: Long,
        uriString: String,
        syncCompleted: CompletableDeferred<Unit>,
    ) {
        val messenger = engine.dartExecutor.binaryMessenger

        val bgChannel = MethodChannel(messenger, HOME_WIDGET_BG_CHANNEL)
        bgChannel.setMethodCallHandler { call, result ->
            if (call.method == "HomeWidget.backgroundInitialized") {
                bgChannel.invokeMethod("", listOf(callbackHandle, uriString, callbackHandle))
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        val syncChannel = MethodChannel(messenger, WidgetSyncChannel.CHANNEL_NAME)
        syncChannel.setMethodCallHandler { call, result ->
            if (call.method == WidgetSyncChannel.METHOD_BACKGROUND_SYNC_COMPLETED) {
                result.success(null)
                syncCompleted.complete(Unit)
            } else {
                result.notImplemented()
            }
        }
    }

    private suspend fun destroyEngine(engine: FlutterEngine?) {
        if (engine == null) return
        withContext(Dispatchers.Main) {
            runCatching { engine.destroy() }
                .onFailure { Log.w(TAG, "Error destroying background FlutterEngine", it) }
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
