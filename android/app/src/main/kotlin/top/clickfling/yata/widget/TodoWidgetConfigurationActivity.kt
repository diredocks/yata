package top.clickfling.yata.widget

import android.app.Activity
import android.app.AlertDialog
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.SeekBar
import android.widget.Switch
import android.widget.TextView
import top.clickfling.yata.R

class TodoWidgetConfigurationActivity : Activity() {

    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private var currentConfig = WidgetConfig()

    private lateinit var opacityBar: SeekBar
    private lateinit var opacityCurrentView: TextView
    private lateinit var fontCurrentView: TextView
    private lateinit var completedSwitch: Switch
    private lateinit var metadataSwitch: Switch

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)

        appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        setContentView(R.layout.todo_widget_config)
        currentConfig = TodoWidgetData.loadConfig(this, appWidgetId)

        opacityBar = findViewById(R.id.widget_opacity_bar)
        opacityCurrentView = findViewById(R.id.widget_opacity_current)
        fontCurrentView = findViewById(R.id.widget_font_current)
        completedSwitch = findViewById(R.id.widget_toggle_completed)
        metadataSwitch = findViewById(R.id.widget_toggle_metadata)

        bindConfig()

        findViewById<View>(R.id.widget_config_backdrop).setOnClickListener {
            saveAndFinish()
        }

        opacityBar.setOnSeekBarChangeListener(
            object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                    val percent = (progress + 20).coerceIn(20, 100)
                    currentConfig = currentConfig.copy(opacityPercent = percent)
                    opacityCurrentView.text = "$percent%"
                    if (fromUser) {
                        applyConfigLive()
                    }
                }

                override fun onStartTrackingTouch(seekBar: SeekBar?) {}
                override fun onStopTrackingTouch(seekBar: SeekBar?) {}
            },
        )

        findViewById<View>(R.id.widget_font_option).setOnClickListener {
            showFontSizeDialog()
        }

        completedSwitch.setOnCheckedChangeListener { _, isChecked ->
            currentConfig = currentConfig.copy(showCompleted = isChecked)
            applyConfigLive()
        }

        metadataSwitch.setOnCheckedChangeListener { _, isChecked ->
            currentConfig = currentConfig.copy(showMetadata = isChecked)
            applyConfigLive()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        saveAndFinish()
    }

    private fun bindConfig() {
        opacityBar.progress = (currentConfig.opacityPercent - 20).coerceIn(0, 80)
        opacityCurrentView.text = "${currentConfig.opacityPercent}%"
        updateFontLabel()
        completedSwitch.isChecked = currentConfig.showCompleted
        metadataSwitch.isChecked = currentConfig.showMetadata
    }

    private fun updateFontLabel() {
        fontCurrentView.text = fontLabel(currentConfig.fontSize)
    }

    private fun fontLabel(size: WidgetFontSize): String {
        return when (size) {
            WidgetFontSize.SMALL -> getString(R.string.widget_font_small)
            WidgetFontSize.MEDIUM -> getString(R.string.widget_font_medium)
            WidgetFontSize.LARGE -> getString(R.string.widget_font_large)
        }
    }

    private fun showFontSizeDialog() {
        val options = WidgetFontSize.entries
        val labels = options.map { fontLabel(it) }.toTypedArray()
        val checkedIndex = options.indexOf(currentConfig.fontSize).coerceAtLeast(0)

        AlertDialog.Builder(this)
            .setTitle(R.string.widget_font_size)
            .setSingleChoiceItems(labels, checkedIndex) { dialog, which ->
                currentConfig = currentConfig.copy(fontSize = options[which])
                updateFontLabel()
                applyConfigLive()
                dialog.dismiss()
            }
            .show()
    }

    private fun applyConfigLive() {
        TodoWidgetData.saveConfig(this, appWidgetId, currentConfig)
        TodoWidgetProvider.updateAppWidget(
            this,
            AppWidgetManager.getInstance(this),
            appWidgetId,
        )
    }

    private fun saveAndFinish() {
        applyConfigLive()
        val resultValue = Intent().apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        }
        setResult(RESULT_OK, resultValue)
        finish()
    }
}
