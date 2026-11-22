package top.clickfling.yata

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val REQUEST_MSA_SIGN_IN = 4201
    }

    private var pendingMsaResult: MethodChannel.Result? = null

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_MSA_SIGN_IN) {
            val pending = pendingMsaResult
            pendingMsaResult = null
            if (pending != null) {
                if (resultCode == Activity.RESULT_OK && data != null) {
                    pending.success(
                        mapOf(
                            "cancelled" to false,
                            "code" to data.getStringExtra(MsaSignInActivity.EXTRA_RESULT_CODE),
                            "redirectUrl" to data.getStringExtra(MsaSignInActivity.EXTRA_RESULT_URL),
                        ),
                    )
                } else {
                    val error = data?.getStringExtra(MsaSignInActivity.EXTRA_RESULT_ERROR)
                    pending.success(
                        mapOf(
                            "cancelled" to true,
                            "error" to error,
                        ),
                    )
                }
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "top.clickfling.yata/msa_auth",
        ).setMethodCallHandler { call, result ->
            if (call.method == "signIn") {
                val authorizeUrl = call.argument<String>("authorizeUrl")
                val redirectUri = call.argument<String>("redirectUri")
                val clearCookies = call.argument<Boolean>("clearCookies") ?: true
                if (authorizeUrl.isNullOrEmpty() || redirectUri.isNullOrEmpty()) {
                    result.error("INVALID_ARGS", "Missing authorizeUrl or redirectUri", null)
                    return@setMethodCallHandler
                }
                if (pendingMsaResult != null) {
                    result.error("IN_PROGRESS", "Sign-in already in progress", null)
                    return@setMethodCallHandler
                }
                pendingMsaResult = result
                val intent = Intent(this, MsaSignInActivity::class.java).apply {
                    putExtra(MsaSignInActivity.EXTRA_AUTHORIZE_URL, authorizeUrl)
                    putExtra(MsaSignInActivity.EXTRA_REDIRECT_URI, redirectUri)
                    putExtra(MsaSignInActivity.EXTRA_CLEAR_COOKIES, clearCookies)
                }
                startActivityForResult(intent, REQUEST_MSA_SIGN_IN)
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "top.clickfling.yata/browser",
        ).setMethodCallHandler { call, result ->
            if (call.method == "openUrl") {
                val url = call.argument<String>("url")
                if (url != null) {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                } else {
                    result.success(false)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
