package top.clickfling.yata.sync

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel bridge allowing Flutter UI to register the unified headless
 * background entrypoint and enqueue lane-scoped [YataSyncWorker] jobs.
 */
class BackgroundSyncChannel(private val context: Context) {

    companion object {
        const val CHANNEL_NAME = "top.clickfling.yata/background_sync"
        const val METHOD_REGISTER_ENTRYPOINT = "registerBackgroundEntrypoint"
        const val METHOD_ENQUEUE_SYNC = "enqueueSync"
        const val METHOD_RUN_BACKGROUND_SYNC = "runBackgroundSync"
        const val METHOD_BACKGROUND_ENGINE_READY = "backgroundEngineReady"
        const val METHOD_BACKGROUND_RUN_COMPLETED = "backgroundRunCompleted"
    }

    private var channel: MethodChannel? = null

    fun attach(flutterEngine: FlutterEngine) {
        val methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        )
        methodChannel.setMethodCallHandler(::handleCall)
        channel = methodChannel
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_REGISTER_ENTRYPOINT -> {
                val handle = (call.argument<Number>("callbackHandle"))?.toLong() ?: 0L
                if (handle != 0L) {
                    YataBackgroundEngineHost.saveCallbackHandle(context.applicationContext, handle)
                }
                result.success(null)
            }

            METHOD_ENQUEUE_SYNC -> {
                val lane = call.argument<String>("lane") ?: YataSyncWorker.LANE_METADATA
                val reason = call.argument<String>("reason") ?: "app"
                val requiresNetwork = call.argument<Boolean>("requiresNetwork") ?: true
                val expedited = call.argument<Boolean>("expedited") ?: false
                YataSyncWorker.enqueue(
                    context = context.applicationContext,
                    lane = lane,
                    reason = reason,
                    requiresNetwork = requiresNetwork,
                    expedited = expedited,
                )
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }
}
