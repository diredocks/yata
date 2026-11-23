package top.clickfling.yata.font

import android.util.Xml
import java.io.File
import org.xmlpull.v1.XmlPullParser

/**
 * Resolves OEM named font families from the platform font configuration.
 *
 * Preloaded theme fonts (e.g. Motorola's "Rookery-Regular") only exist as named
 * families in `fonts_customization.xml`; the font files themselves carry a
 * different family name in their `name` table, so they cannot be found by
 * comparing name tables.
 */
internal object SystemFontConfig {

    data class Entry(
        val file: File,
        val weight: Int,
        val italic: Boolean,
        val ttcIndex: Int,
        /** Enclosing `<family name="…">`, if any. */
        val familyName: String?,
        /** `<font fallbackFor="…">` of the font, if any. */
        val fallbackFor: String?,
    )

    private val CONFIGS = listOf(
        File("/product/etc/fonts_customization.xml") to "/product/fonts",
        File("/system_ext/etc/fonts_customization.xml") to "/system_ext/fonts",
        File("/vendor/etc/fonts_customization.xml") to "/vendor/fonts",
        File("/product/etc/fonts.xml") to "/product/fonts",
        File("/system/etc/fonts.xml") to "/system/fonts",
    )

    /** All `<font>` entries of every readable configuration file. */
    private val entries: List<Entry> by lazy {
        CONFIGS.flatMap { (config, baseDir) ->
            if (!config.isFile || !config.canRead()) {
                emptyList()
            } else {
                runCatching { parse(config, baseDir) }.getOrDefault(emptyList())
            }
        }
    }

    /** Font faces declared for [familyName], or empty when unknown. */
    fun fontsFor(familyName: String): List<Entry> =
        entries.filter { it.familyName == familyName }

    /**
     * Font families the configuration declares as `fallbackFor` [familyName]
     * (typically CJK faces), in weight order.
     *
     * Only the family names are needed: they belong to real system font files,
     * so the Flutter font manager resolves them like any other system family.
     */
    fun fallbackFamiliesFor(familyName: String): List<String> =
        entries
            .filter { it.fallbackFor == familyName && !it.italic }
            .sortedBy { it.weight }
            .mapNotNull { entry -> SfntFont.familyNames(entry.file, entry.ttcIndex).firstOrNull() }
            .distinct()

    private fun parse(config: File, baseDir: String): List<Entry> =
        config.inputStream().bufferedReader().use { reader ->
            val parser = Xml.newPullParser()
            parser.setInput(reader)

            val entries = ArrayList<Entry>()
            var familyName: String? = null
            while (parser.eventType != XmlPullParser.END_DOCUMENT) {
                when (parser.eventType) {
                    XmlPullParser.START_TAG -> when (parser.name) {
                        "family" -> familyName = parser.getAttributeValue(null, "name")
                        "font" -> {
                            val weight = parser.getAttributeValue(null, "weight")
                                ?.toIntOrNull() ?: 400
                            val style = parser.getAttributeValue(null, "style")
                            val ttcIndex = parser.getAttributeValue(null, "index")
                                ?.toIntOrNull() ?: 0
                            val fallbackFor = parser.getAttributeValue(null, "fallbackFor")
                            val file = resolve(baseDir, readText(parser))
                            if (file != null) {
                                entries += Entry(
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
            entries
        }

    private fun resolve(baseDir: String, name: String): File? {
        if (name.isEmpty()) return null
        val file = if (name.startsWith("/")) File(name) else File(baseDir, name)
        return file.takeIf { it.isFile && it.canRead() }
    }

    /**
     * Reads the text of the current element, skipping nested elements such as
     * the `<axis>` entries of variable fonts.
     */
    private fun readText(parser: XmlPullParser): String {
        val text = StringBuilder()
        var depth = 1
        while (depth > 0) {
            when (parser.next()) {
                XmlPullParser.START_TAG -> depth++
                XmlPullParser.END_TAG -> depth--
                XmlPullParser.TEXT -> text.append(parser.text)
            }
        }
        return text.toString().trim()
    }
}
