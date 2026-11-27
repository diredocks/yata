package top.clickfling.yata.sync

import android.content.Context
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.TimeoutException

private typealias KotlinResult<T> = kotlin.Result<T>

/**
 * Process-scoped host for Yata's single headless background [FlutterEngine].
 *
 * Uses [FlutterEngineGroup] so sequential WorkManager runs share one
 * serialized engine lifecycle without racing on SQLite, and tears the engine
 * down automatically after each pass completes.
 */
object YataBackgroundEngineHost {
    private const val TAG = "YataBgEngineHost"
    private const val PREFS_NAME = "yata_background_sync_prefs"
    private const val KEY_CALLBACK_HANDLE = "background_callback_handle"
    private const val ENGINE_READY_TIMEOUT_MS = 15_000L

    private val lifecycleMutex = Mutex()
    private var engineGroup: FlutterEngineGroup? = null
    private var sharedEngine: FlutterEngine? = null
    private var sharedChannel: MethodChannel? = null
    private var pendingCompletion: CompletableDeferred<BackgroundRunOutcome>? = null

    data class BackgroundRunOutcome(
        val shouldRetry: Boolean,
        val hasPendingTransfers: Boolean,
    )

    fun saveCallbackHandle(context: Context, handle: Long) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_CALLBACK_HANDLE, handle)
            .apply()
    }

    fun getCallbackHandle(context: Context): Long {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getLong(KEY_CALLBACK_HANDLE, 0L)
    }

    fun isRegistered(context: Context): Boolean = getCallbackHandle(context) != 0L

    suspend fun runPass(
        context: Context,
        lane: String,
        reason: String,
        timeoutMs: Long,
    ): KotlinResult<BackgroundRunOutcome> = lifecycleMutex.withLock {
        val handle = getCallbackHandle(context)
        if (handle == 0L) {
            return KotlinResult.failure(
                IllegalStateException("Background sync entrypoint handle is not registered"),
            )
        }

        return try {
            val channel = ensureEngineReady(context, handle).getOrElse { error ->
                return KotlinResult.failure(error)
            }
            val completed = CompletableDeferred<BackgroundRunOutcome>()
            pendingCompletion = completed

            withContext(Dispatchers.Main) {
                channel.invokeMethod(
                    BackgroundSyncChannel.METHOD_RUN_BACKGROUND_SYNC,
                    mapOf("lane" to lane, "reason" to reason),
                )
            }

            val outcome = withTimeoutOrNull(timeoutMs) { completed.await() }
                ?: return KotlinResult.failure(
                    TimeoutException("Background sync timed out after ${timeoutMs}ms (lane=$lane)"),
                )
            KotlinResult.success(outcome)
        } finally {
            pendingCompletion = null
            destroyEngineLocked()
        }
    }

    private suspend fun ensureEngineReady(
        context: Context,
        callbackHandle: Long,
    ): KotlinResult<MethodChannel> {
        sharedChannel?.let { return KotlinResult.success(it) }

        val appContext = context.applicationContext
        val ready = CompletableDeferred<Unit>()
        val created = withContext(Dispatchers.Main) {
            runCatching {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(appContext)
                loader.ensureInitializationComplete(appContext, null)

                val callbackInfo =
                    FlutterCallbackInformation.lookupCallbackInformation(callbackHandle)
                        ?: throw IllegalStateException(
                            "Unable to resolve FlutterCallbackInformation for handle=$callbackHandle",
                        )

                val group = engineGroup ?: FlutterEngineGroup(appContext).also { engineGroup = it }
                val engine = group.createAndRunEngine(
                    appContext,
                    DartExecutor.DartEntrypoint(
                        loader.findAppBundlePath(),
                        callbackInfo.callbackLibraryPath,
                        callbackInfo.callbackName,
                    ),
                )
                val channel = MethodChannel(
                    engine.dartExecutor.binaryMessenger,
                    BackgroundSyncChannel.CHANNEL_NAME,
                )
                channel.setMethodCallHandler { call, result ->
                    handleWorkerCall(call.method, call.arguments, ready, result)
                }
                sharedEngine = engine
                sharedChannel = channel
                channel
            }
        }
        val channel = created.getOrElse { error ->
            destroyEngineLocked()
            return KotlinResult.failure(error)
        }

        val isReady = withTimeoutOrNull(ENGINE_READY_TIMEOUT_MS) { ready.await() } != null
        if (!isReady) {
            destroyEngineLocked()
            return KotlinResult.failure(
                TimeoutException("Background FlutterEngine did not signal ready within ${ENGINE_READY_TIMEOUT_MS}ms"),
            )
        }
        return KotlinResult.success(channel)
    }

    private fun handleWorkerCall(
        method: String,
        arguments: Any?,
        ready: CompletableDeferred<Unit>,
        result: MethodChannel.Result,
    ) {
        when (method) {
            BackgroundSyncChannel.METHOD_BACKGROUND_ENGINE_READY -> {
                result.success(null)
                if (!ready.isCompleted) ready.complete(Unit)
            }

            BackgroundSyncChannel.METHOD_BACKGROUND_RUN_COMPLETED -> {
                result.success(null)
                val map = arguments as? Map<*, *>
                val outcome = BackgroundRunOutcome(
                    shouldRetry = map?.get("shouldRetry") as? Boolean ?: false,
                    hasPendingTransfers = map?.get("hasPendingTransfers") as? Boolean ?: false,
                )
                pendingCompletion?.complete(outcome)
            }

            else -> result.notImplemented()
        }
    }

    private suspend fun destroyEngineLocked() {
        val engine = sharedEngine
        sharedChannel?.setMethodCallHandler(null)
        sharedChannel = null
        sharedEngine = null
        if (engine == null) return
        withContext(Dispatchers.Main) {
            runCatching { engine.destroy() }
                .onFailure { Log.w(TAG, "Error destroying shared background FlutterEngine", it) }
        }
    }
}
