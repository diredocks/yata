package top.clickfling.yata.font

import android.graphics.Typeface
import android.graphics.fonts.Font
import android.graphics.fonts.FontStyle
import android.graphics.fonts.SystemFonts
import android.os.Build
import java.io.File
import java.lang.reflect.Method
import java.util.Locale
import kotlin.math.abs

internal data class FontCandidate(
    val file: File,
    val weight: Int,
    val italic: Boolean,
    val ttcIndex: Int,
    val lastModified: Long,
    val length: Long,
) {
    val key: String get() = "${file.path}#$ttcIndex@$lastModified:$length"
    val fingerprintPart: String get() = "${file.path}#$ttcIndex:$lastModified:$length"

    fun sameFaceAs(other: FontCandidate): Boolean =
        file.path == other.file.path && ttcIndex == other.ttcIndex

    companion object {
        fun from(
            file: File,
            weight: Int,
            italic: Boolean,
            ttcIndex: Int,
        ): FontCandidate {
            val absolute = file.absoluteFile
            return FontCandidate(
                file = absolute,
                weight = weight,
                italic = italic,
                ttcIndex = ttcIndex,
                lastModified = absolute.lastModified(),
                length = absolute.length(),
            )
        }
    }
}

class SystemFontResolver {

    class Payload(
        val changed: Boolean,
        val fingerprint: String,
        val fallbackFamilies: List<String>,
        val regular: ByteArray?,
        val bold: ByteArray?,
    ) {
        companion object {
            fun unchanged(fingerprint: String): Payload = Payload(
                changed = false,
                fingerprint = fingerprint,
                fallbackFamilies = emptyList(),
                regular = null,
                bold = null,
            )
        }
    }

    private class Selection(
        val familyName: String?,
        val regular: FontCandidate,
        val bold: FontCandidate?,
    ) {
        val fingerprint: String
            get() = "${familyName.orEmpty()}|${regular.fingerprintPart}|${bold?.fingerprintPart ?: "-"}"
    }

    private val familyCache = HashMap<String, Set<String>>()

    @Synchronized
    fun load(lastFingerprint: String? = null): Payload? {
        val selection = runCatching { resolve() }.getOrNull() ?: return null
        val fingerprint = selection.fingerprint
        if (fingerprint == lastFingerprint) {
            return Payload.unchanged(fingerprint)
        }

        val regular = SfntFont.readFaceBytes(selection.regular.file, selection.regular.ttcIndex)
            ?: return null
        val bold = selection.bold?.let { SfntFont.readFaceBytes(it.file, it.ttcIndex) }
        return Payload(
            changed = true,
            fingerprint = fingerprint,
            fallbackFamilies = selection.familyName
                ?.let(SystemFontConfig::fallbackFamiliesFor)
                .orEmpty(),
            regular = regular,
            bold = bold,
        )
    }

    private fun resolve(): Selection? {
        val mounted = lazy(LazyThreadSafetyMode.NONE) { mountedCandidates() }

        overlayFontSelection(mounted)?.let { return it }

        systemDefaultFamilyName()?.let { systemFamily ->
            configFamilySelection(systemFamily)?.let { return it }
            matchByFamily(mounted.value, systemFamily)?.let { return it }
        }

        metricMatch(mounted.value)?.let { return it }
        updatableFontSelection()?.let { return it }

        return singleNonStockFamily(mounted.value)
    }

    private fun overlayFontSelection(mounted: Lazy<List<FontCandidate>>): Selection? {
        for (key in OVERLAY_FONT_PROPERTIES) {
            val raw = SystemPropertiesReader.get(key) ?: continue

            // First entry is the primary font; trailing entries are script variants.
            val value = raw.split(':', ',', ';')
                .firstOrNull { it.isNotBlank() }
                ?.trim()
                ?: continue

            if (value.contains('/') || SfntFont.hasFontExtension(value)) {
                val file = File(if (value.startsWith("/")) value else "/$value")
                if (!SfntFont.isFontFile(file)) continue
                val candidate = toCandidate(file) ?: continue
                selectionFor(null, siblingCandidates(candidate))?.let { return it }
            } else {
                configFamilySelection(value)?.let { return it }
                matchByFamily(mounted.value, value, exactOnly = true)?.let { return it }
            }
        }
        return null
    }

    private fun configFamilySelection(familyName: String): Selection? {
        val candidates = SystemFontConfig.fontsFor(familyName).map { entry ->
            FontCandidate.from(entry.file, entry.weight, entry.italic, entry.ttcIndex)
        }
        return selectionFor(familyName, candidates)
    }

    private fun siblingCandidates(candidate: FontCandidate): List<FontCandidate> {
        val parent = candidate.file.parentFile ?: return listOf(candidate)
        val familyKey = primaryFamilyKey(candidate)
        val siblings = fontFilesIn(parent, depth = 0)
            .filter { it.absolutePath != candidate.file.path }
            .mapNotNull(::toCandidate)
            .filter { primaryFamilyKey(it) == familyKey }
        return (listOf(candidate) + siblings).distinctBy { it.key }
    }

    private fun systemDefaultFamilyName(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return null

        val fromDefault = runCatching { Typeface.DEFAULT.systemFontFamilyName }
            .getOrNull()
            ?.takeIf { it.isNotBlank() && !isGenericFamily(it) }
        if (fromDefault != null) return fromDefault

        return runCatching {
            Typeface.create("sans-serif", Typeface.NORMAL).systemFontFamilyName
        }.getOrNull()?.takeIf { it.isNotBlank() && !isGenericFamily(it) }
    }

    private fun matchByFamily(
        candidates: List<FontCandidate>,
        systemFamily: String,
        exactOnly: Boolean = false,
    ): Selection? {
        if (candidates.isEmpty()) return null
        val target = normalize(systemFamily)
        if (target.isEmpty()) return null

        val best = candidates
            .asSequence()
            .filterNot { it.italic }
            .mapNotNull { candidate ->
                val score = matchScore(candidate, target, exactOnly)
                if (score > 0) candidate to score else null
            }
            .maxByOrNull { it.second }
            ?.first
            ?: return null

        return selectionForFamilyOf(systemFamily, best, candidates)
    }

    private fun matchScore(candidate: FontCandidate, target: String, exactOnly: Boolean): Int {
        val names = familyNames(candidate)
        if (target in names) return SCORE_EXACT
        val stem = stemOf(candidate)
        if (exactOnly) return if (stem == target) SCORE_FILE_NAME else 0
        if (names.any { it.startsWith(target) || target.startsWith(it) }) return SCORE_PREFIX
        if (names.any { target in it }) return SCORE_CONTAINS
        if (stem.isNotEmpty() &&
            (stem == target || stem.startsWith(target) || target.startsWith(stem))
        ) {
            return SCORE_FILE_NAME
        }
        return 0
    }

    private fun metricMatch(candidates: List<FontCandidate>): Selection? {
        val winner = GlyphMetricMatcher.findBestMatch(candidates) ?: return null
        return selectionForFamilyOf(null, winner, candidates)
    }

    private fun updatableFontSelection(): Selection? {
        val dataDirs = listOf(
            File("/data/fonts/files"),
            File("/data/fonts"),
            File("/data/system/fonts"),
        )

        val candidates = dataDirs
            .flatMap { fontFilesIn(it) }
            .mapNotNull(::toCandidate)
            .distinctBy { it.key }
        if (candidates.isEmpty()) return null

        val groups = candidates.groupBy { primaryFamilyKey(it) }
        val newestFirst = groups.values
            .map { group -> group to group.maxOf { it.lastModified } }
            .sortedByDescending { it.second }

        for ((group, _) in newestFirst) {
            selectionFor(null, group)?.let { return it }
        }
        return null
    }

    private fun fontFilesIn(dir: File, depth: Int = 2): List<File> {
        if (!dir.isDirectory || !dir.canRead()) return emptyList()
        val files = ArrayList<File>()

        fun walk(current: File, remaining: Int) {
            val children = current.listFiles() ?: return
            for (child in children) {
                if (files.size >= MAX_SCANNED_FILES) return
                if (child.isDirectory && remaining > 0) {
                    walk(child, remaining - 1)
                } else if (SfntFont.isFontFile(child)) {
                    files.add(child)
                }
            }
        }

        walk(dir, depth)
        return files
    }

    private fun toCandidate(file: File): FontCandidate? {
        if (!SfntFont.isFontFile(file)) return null
        val meta = SfntFont.readMetadata(file)
        val candidate = FontCandidate.from(
            file = file,
            weight = meta?.weight ?: weightFromName(file.name),
            italic = (meta?.italic == true) || isItalicName(file.name),
            ttcIndex = 0,
        )
        if (meta != null) {
            familyCache[candidate.key] = meta.familyNames
                .map(::normalize)
                .filterTo(LinkedHashSet()) { it.isNotEmpty() }
        }
        return candidate
    }

    private fun singleNonStockFamily(candidates: List<FontCandidate>): Selection? {
        val groups = candidates
            .groupBy { primaryFamilyKey(it) }
            .filterKeys { key -> key.isNotEmpty() && !isStockFamily(key) }
        if (groups.size != 1) return null
        return selectionFor(null, groups.values.first())
    }

    private fun mountedCandidates(): List<FontCandidate> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return emptyList()
        val fonts: Set<Font> = runCatching { SystemFonts.getAvailableFonts() }.getOrNull()
            ?: return emptyList()

        val result = LinkedHashMap<String, FontCandidate>()
        for (font in fonts) {
            val file = runCatching { font.file }.getOrNull() ?: continue
            if (!SfntFont.isFontFile(file)) continue
            val weight = runCatching { font.style.weight }.getOrDefault(WEIGHT_NORMAL)
            val candidate = FontCandidate.from(
                file = file,
                weight = weight.takeIf { it in 1..1000 } ?: WEIGHT_NORMAL,
                italic = runCatching {
                    font.style.slant != FontStyle.FONT_SLANT_UPRIGHT
                }.getOrDefault(false),
                ttcIndex = runCatching { font.ttcIndex }.getOrDefault(0),
            )
            result[candidate.key] = candidate
        }
        return result.values.toList()
    }

    private fun selectionForFamilyOf(
        familyName: String?,
        winner: FontCandidate,
        candidates: List<FontCandidate>,
    ): Selection? {
        val familyKey = primaryFamilyKey(winner)
        if (familyKey.isEmpty()) return selectionFor(familyName, listOf(winner))
        val group = candidates.filter { primaryFamilyKey(it) == familyKey }
        return selectionFor(familyName, group.ifEmpty { listOf(winner) })
    }

    private fun selectionFor(familyName: String?, group: List<FontCandidate>): Selection? {
        val upright = group.filterNot { it.italic }
        if (upright.isEmpty()) return null
        val regular = upright.minByOrNull { abs(it.weight - WEIGHT_NORMAL) } ?: return null
        val bold = upright
            .filter { it.weight in 600..800 && !it.sameFaceAs(regular) }
            .minByOrNull { abs(it.weight - WEIGHT_BOLD) }
        return Selection(familyName, regular, bold)
    }

    private fun familyNames(candidate: FontCandidate): Set<String> =
        familyCache.getOrPut(candidate.key) {
            val names = LinkedHashSet<String>()
            SfntFont.familyNames(candidate.file, candidate.ttcIndex)
                .map(::normalize)
                .filterTo(names) { it.isNotEmpty() }
            names
        }

    private fun primaryFamilyKey(candidate: FontCandidate): String =
        familyNames(candidate).firstOrNull() ?: stemOf(candidate)

    private fun stemOf(candidate: FontCandidate): String {
        val base = candidate.file.name.substringBeforeLast('.', candidate.file.name)
        val tokens = base.split('-', '_', ' ', '.').filter { it.isNotEmpty() }
        val kept = tokens.dropLastWhile { normalize(it) in VARIANT_TOKENS }
        return normalize(if (kept.isEmpty()) base else kept.joinToString(separator = ""))
    }

    private fun isItalicName(name: String): Boolean {
        val lower = name.lowercase(Locale.ROOT)
        return "italic" in lower || "oblique" in lower
    }

    private fun weightFromName(name: String): Int {
        val lower = name.lowercase(Locale.ROOT)
        return when {
            "black" in lower -> 900
            "extrabold" in lower || "ultrabold" in lower || "heavy" in lower -> 800
            "semibold" in lower || "demibold" in lower -> 600
            "bold" in lower -> WEIGHT_BOLD
            "medium" in lower -> 500
            "extralight" in lower || "ultralight" in lower -> 200
            "light" in lower -> 300
            "thin" in lower -> 100
            else -> WEIGHT_NORMAL
        }
    }

    private fun normalize(value: String): String =
        value.lowercase(Locale.ROOT).filter { it.isLetterOrDigit() }

    private fun isGenericFamily(family: String): Boolean {
        val normalized = normalize(family)
        return normalized.isEmpty() || normalized == "sansserif" || normalized == "default"
    }

    private fun isStockFamily(key: String): Boolean = STOCK_FAMILY_MARKERS.any { it in key }

    private object SystemPropertiesReader {
        private val getMethod: Method? by lazy {
            runCatching {
                Class.forName("android.os.SystemProperties")
                    .getMethod("get", String::class.java)
            }.getOrNull()
        }

        fun get(key: String): String? {
            val method = getMethod
            if (method != null) {
                val reflected = runCatching { method.invoke(null, key) as? String }
                if (reflected.isSuccess) {
                    return reflected.getOrNull()?.trim()?.ifEmpty { null }
                }
            }

            return runCatching {
                val process = ProcessBuilder("getprop", key).redirectErrorStream(true).start()
                try {
                    val value = process.inputStream.bufferedReader().use { it.readText() }.trim()
                    process.waitFor()
                    value.ifEmpty { null }
                } finally {
                    process.destroy()
                }
            }.getOrNull()
        }
    }

    private companion object {
        const val WEIGHT_NORMAL = 400
        const val WEIGHT_BOLD = 700
        const val SCORE_EXACT = 100
        const val SCORE_PREFIX = 60
        const val SCORE_CONTAINS = 40
        const val SCORE_FILE_NAME = 30

        const val MAX_SCANNED_FILES = 256

        val OVERLAY_FONT_PROPERTIES = listOf(
            "persist.sys.overlayfonts",
            "persist.sys.overlay.font",
            "persist.sys.theme.font",
            "persist.sys.font.path",
        )

        val STOCK_FAMILY_MARKERS = listOf("roboto", "noto", "droid", "googlesans")

        val VARIANT_TOKENS = setOf(
            "thin", "extralight", "ultralight", "light", "regular", "book",
            "normal", "medium", "semibold", "demibold", "bold", "extrabold",
            "ultrabold", "black", "heavy", "italic", "oblique", "roman",
            "variable", "vf", "regularitalic",
        )
    }
}
