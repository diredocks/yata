package top.clickfling.yata.font

import android.util.Xml
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.abs
import org.xmlpull.v1.XmlPullParser

internal object SystemFontConfig {

    data class Entry(
        val file: File,
        val weight: Int,
        val italic: Boolean,
        val ttcIndex: Int,
        val familyName: String?,
        val fallbackFor: String?,
    )

    private val CONFIGS = listOf(
        File("/product/etc/fonts_customization.xml") to "/product/fonts",
        File("/system_ext/etc/fonts_customization.xml") to "/system_ext/fonts",
        File("/vendor/etc/fonts_customization.xml") to "/vendor/fonts",
        File("/product/etc/fonts.xml") to "/product/fonts",
        File("/system/etc/fonts.xml") to "/system/fonts",
    )

    private val entries: List<Entry> by lazy {
        CONFIGS.flatMap { (config, baseDir) ->
            if (!config.isFile || !config.canRead()) {
                emptyList()
            } else {
                runCatching { parse(config, baseDir) }.getOrDefault(emptyList())
            }
        }
    }

    private val fallbackCache = ConcurrentHashMap<String, List<String>>()

    fun fontsFor(familyName: String): List<Entry> =
        entries.filter { it.familyName == familyName }

    fun fallbackFamiliesFor(familyName: String): List<String> {
        fallbackCache[familyName]?.let { return it }
        val result = entries
            .filter { it.fallbackFor == familyName && !it.italic }
            .sortedBy { abs(it.weight - 400) }
            .mapNotNull { entry -> SfntFont.familyNames(entry.file, entry.ttcIndex).firstOrNull() }
            .distinct()
        return fallbackCache.putIfAbsent(familyName, result) ?: result
    }

    private fun parse(config: File, baseDir: String): List<Entry> =
        config.inputStream().bufferedReader().use { reader ->
            val parser = Xml.newPullParser()
            parser.setInput(reader)

            val parsed = ArrayList<Entry>()
            var familyName: String? = null
            while (parser.eventType != XmlPullParser.END_DOCUMENT) {
                when (parser.eventType) {
                    XmlPullParser.START_TAG -> when (parser.name) {
                        "family" -> familyName = parser.getAttributeValue(null, "name")
                        "font" -> {
                            val weight = parser.getAttributeValue(null, "weight")
                                ?.toIntOrNull()
                                ?.takeIf { it in 1..1000 }
                                ?: 400
                            val style = parser.getAttributeValue(null, "style")
                            val ttcIndex = parser.getAttributeValue(null, "index")
                                ?.toIntOrNull()
                                ?.takeIf { it >= 0 }
                                ?: 0
                            val fallbackFor = parser.getAttributeValue(null, "fallbackFor")
                            val file = resolve(baseDir, readText(parser))
                            if (file != null) {
                                parsed += Entry(
                                    file = file,
                                    weight = weight,
                                    italic = style == "italic" || style == "oblique",
                                    ttcIndex = ttcIndex,
                                    familyName = familyName,
                                    fallbackFor = fallbackFor,
                                )
                            }
                        }
                    }
                    XmlPullParser.END_TAG -> if (parser.name == "family") familyName = null
                }
                parser.next()
            }
            parsed
        }

    private fun resolve(baseDir: String, name: String): File? {
        if (name.isEmpty()) return null
        val file = if (name.startsWith("/")) File(name) else File(baseDir, name)
        return file.takeIf(SfntFont::isFontFile)
    }

    private fun readText(parser: XmlPullParser): String {
        val text = StringBuilder()
        var depth = 1
        while (depth > 0) {
            when (parser.next()) {
                XmlPullParser.START_TAG -> depth++
                XmlPullParser.END_TAG -> depth--
                XmlPullParser.TEXT -> if (depth == 1) text.append(parser.text)
                XmlPullParser.END_DOCUMENT -> break
            }
        }
        return text.toString().trim()
    }
}
