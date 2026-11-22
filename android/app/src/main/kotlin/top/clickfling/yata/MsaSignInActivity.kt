package top.clickfling.yata

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.Toolbar

class MsaSignInActivity : Activity() {
    companion object {
        const val EXTRA_AUTHORIZE_URL = "authorize_url"
        const val EXTRA_REDIRECT_URI = "redirect_uri"
        const val EXTRA_CLEAR_COOKIES = "clear_cookies"
        const val EXTRA_RESULT_CODE = "auth_code"
        const val EXTRA_RESULT_URL = "redirect_result_url"
        const val EXTRA_RESULT_ERROR = "auth_error"
    }

    private var webView: WebView? = null
    private lateinit var progressBar: ProgressBar
    private lateinit var redirectUri: String
    private var handledRedirect = false

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val authorizeUrl = intent.getStringExtra(EXTRA_AUTHORIZE_URL)
        val redirect = intent.getStringExtra(EXTRA_REDIRECT_URI)
        if (authorizeUrl.isNullOrEmpty() || redirect.isNullOrEmpty()) {
            setResult(RESULT_CANCELED)
            finish()
            return
        }
        redirectUri = redirect

        val clearCookies = intent.getBooleanExtra(EXTRA_CLEAR_COOKIES, true)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }

        val toolbar = Toolbar(this).apply {
            title = "Microsoft"
            setNavigationIcon(android.R.drawable.ic_menu_close_clear_cancel)
            setNavigationOnClickListener {
                setResult(RESULT_CANCELED)
                finish()
            }
        }
        root.addView(
            toolbar,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )

        progressBar = ProgressBar(
            this,
            null,
            android.R.attr.progressBarStyleHorizontal,
        ).apply {
            max = 100
            visibility = View.VISIBLE
        }
        root.addView(
            progressBar,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                6,
            ),
        )

        val wv = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            webChromeClient = object : WebChromeClient() {
                override fun onProgressChanged(view: WebView?, newProgress: Int) {
                    progressBar.progress = newProgress
                    progressBar.visibility =
                        if (newProgress in 1..99) View.VISIBLE else View.GONE
                }
            }
            webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(
                    view: WebView?,
                    request: WebResourceRequest?,
                ): Boolean {
                    val uri = request?.url ?: return false
                    return maybeHandleRedirect(uri)
                }

                override fun onPageStarted(
                    view: WebView?,
                    url: String?,
                    favicon: Bitmap?,
                ) {
                    if (!url.isNullOrEmpty()) {
                        maybeHandleRedirect(Uri.parse(url))
                    }
                    super.onPageStarted(view, url, favicon)
                }
            }
        }
        webView = wv
        root.addView(
            wv,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )

        setContentView(root)

        if (clearCookies) {
            val cookieManager = CookieManager.getInstance()
            cookieManager.removeAllCookies {
                cookieManager.flush()
                wv.loadUrl(authorizeUrl)
            }
        } else {
            wv.loadUrl(authorizeUrl)
        }
    }

    private fun maybeHandleRedirect(uri: Uri): Boolean {
        val urlString = uri.toString()
        if (!urlString.startsWith(redirectUri, ignoreCase = true)) {
            return false
        }
        if (handledRedirect) {
            return true
        }
        handledRedirect = true

        val code = uri.getQueryParameter("code")
        if (!code.isNullOrEmpty()) {
            val data = Intent().apply {
                putExtra(EXTRA_RESULT_CODE, code)
                putExtra(EXTRA_RESULT_URL, urlString)
            }
            setResult(RESULT_OK, data)
            finish()
            return true
        }

        val error = uri.getQueryParameter("error")
        val errorDesc = uri.getQueryParameter("error_description")
        val message = when {
            !errorDesc.isNullOrEmpty() -> errorDesc
            !error.isNullOrEmpty() -> error
            else -> null
        }
        val data = Intent().apply {
            if (!message.isNullOrEmpty()) {
                putExtra(EXTRA_RESULT_ERROR, message)
            }
        }
        setResult(RESULT_CANCELED, data)
        finish()
        return true
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        val wv = webView
        if (wv != null && wv.canGoBack()) {
            wv.goBack()
        } else {
            setResult(RESULT_CANCELED)
            finish()
        }
    }

    override fun onDestroy() {
        webView?.apply {
            stopLoading()
            destroy()
        }
        webView = null
        super.onDestroy()
    }
}
