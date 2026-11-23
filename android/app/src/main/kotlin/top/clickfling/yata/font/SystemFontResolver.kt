package top.clickfling.yata.font

import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.fonts.Font
import android.graphics.fonts.SystemFonts
import android.os.Build
import java.io.File
import java.util.Locale
import kotlin.math.abs

/**
 * Locates the font file(s) the OS currently uses as its default font, so the
 * Dart side can register them with `FontLoader`.
 *
 * Flutter resolves the default `sans-serif` family through its own font
 * manager, which does not follow runtime OEM font switches (Motorola MyUX /
 * Hello UI, Lenovo ZUI, …). The files behind the system default are therefore
 * resolved natively and streamed to Dart.
 *
 * Resolution order:
 *  1. OEM theme engines publish the file they apply in a system property.
 *  2. API 34+: `Typeface.getSystemFontFamilyName()` matched against
 *     `SystemFonts.getAvailableFonts()` by name table and file name.
 *  3. Glyph metrics compared with `Typeface.create("sans-serif")`.
 *  4. FontManager updatable fonts in `/data/fonts/files` (Android 12+).
 *  5. A single non-stock (non Roboto/Noto) mounted family.
 *
 * The result is fingerprinted by `path + ttcIndex + lastModified + size`, so a
 * repeated request can answer `changed = false` instead of transferring the
 * font bytes again.
 */
class SystemFontResolver {

    /** Result of [load]; only [changed] payloads carry font bytes. */
    data class Payload(
        val changed: Boolean,
        val familyName: String?,
        val fingerprint: String?,
        val regular: ByteArray?,
        val bold: ByteArray?,
    )

    private data class Candidate(
        val path: String,
        val weight: Int,
        val ttcIndex: Int,
        val lastModified: Long,
        val length: Long,
    ) {
        val file: File get() = File(path)
        val key: String get() = "$path#$ttcIndex@$lastModified:$length"
    }

    private class Selection(
        val familyName: String?,
        val regular: Candidate,
        val bold: Candidate?,
    ) {
        val fingerprint: String
            get() = listOf(regular, bold).joinToString("|") { candidate ->
                candidate?.let { "${it.path}#${it.ttcIndex}:${it.lastModified}:${it.length}" }
                    ?: "-"
            }
    }

    /** Fingerprint of the last snapshot handed to Dart. */
    @Volatile
    private var deliveredFingerprint: String? = null

    /** Family-name lookups, keyed by [Candidate.key]. */
    private val familyCache = HashMap<String, Set<String>>()

    /**
     * Resolves the current system font. Returns `null` when nothing usable was
     * found; with [force] the fingerprint cache is bypassed and the bytes are
     * sent again.
     */
    @Synchronized
    fun load(force: Boolean = false): Payload? {
        if (force) deliveredFingerprint = null

        val selection = try {
            resolve()
        } catch (_: Throwable) {
            null
        } ?: return null

        val fingerprint = selection.fingerprint
        if (fingerprint == deliveredFingerprint) {
            return Payload(
                changed = false,
                familyName = selection.familyName,
                fingerprint = fingerprint,
                regular = null,
                bold = null,
            )
        }

        val regular = readFontBytes(selection.regular) ?: return null
        val bold = selection.bold?.let(::readFontBytes)
        deliveredFingerprint = fingerprint
        return Payload(
            changed = true,
            familyName = selection.familyName,
            fingerprint = fingerprint,
            regular = regular,
            bold = bold,
        )
    }

    private fun resolve(): Selection? {
        // OEM theme engines are the only ones that know the applied file:
        // fontconfig keeps pointing "sans-serif" at Roboto while the theme
        // engine swaps the rendering font at runtime.
        overlayFontCandidates()?.let { return it }

        val mounted = mountedCandidates()
        val systemFamily = systemDefaultFamilyName()
        if (systemFamily != null && !isGenericFamily(systemFamily)) {
            matchByFamily(mounted, systemFamily)?.let { return it }
        }

        // Rendering must match `Typeface.create("sans-serif")`, which is the
        // authoritative signal when the family name is not available.
        metricMatch(mounted)?.let { return it }

        // FontManager updatable fonts (Android 12+).
        updatableFontCandidates()?.let { return it }

        return singleNonStockFamily(mounted)
    }

    // region OEM theme engine overlay font

    /**
     * Motorola/Lenovo theme engines (MyUX "Hello UI", ZUI) extract the chosen
     * font to `/data/misc/theme/` and publish the active file in a system
     * property. The file is world readable and `appdomain` is allowed to read
     * `themeservice_app_data_file`, so the exact bytes can be streamed.
     */
    private fun overlayFontCandidates(): Selection? {
        for (key in OVERLAY_FONT_PROPERTIES) {
            val raw = readSystemProperty(key)
            if (raw.isNullOrBlank()) continue

            for (entry in raw.split(':', ',', ';')) {
                val value = entry.trim()
                if (value.isEmpty()) continue

                val file = File(if (value.startsWith("/")) value else "/$value")
                if (!SfntFont.isFontFile(file)) continue

                val candidate = toCandidate(file) ?: continue
                selectionFor(null, siblingCandidates(candidate))?.let { return it }
            }
        }
        return null
    }

    /** The overlay font plus same-family files from its directory, if listable. */
    private fun siblingCandidates(candidate: Candidate): List<Candidate> {
        val parent = candidate.file.parentFile ?: return listOf(candidate)
        val familyKey = primaryFamilyKey(candidate)
        val siblings = fontFilesIn(parent)
            .filter { it.absolutePath != candidate.path }
            .mapNotNull(::toCandidate)
            .filter { primaryFamilyKey(it) == familyKey }
        return (listOf(candidate) + siblings).distinctBy { it.key }
    }

    private fun readSystemProperty(key: String): String? {
        runCatching {
            // `android.os.SystemProperties` is @hide; reflection works on most
            // builds and returns immediately.
            val type = Class.forName("android.os.SystemProperties")
            val get = type.getMethod("get", String::class.java)
            val value = get.invoke(null, key) as? String
            if (!value.isNullOrBlank()) return value
        }

        // Fallback for builds that block hidden APIs.
        return runCatching {
            val process = ProcessBuilder("getprop", key).redirectErrorStream(true).start()
            val value = process.inputStream.bufferedReader().use { it.readText() }.trim()
            process.waitFor()
            value.ifEmpty { null }
        }.getOrNull()
    }

    // endregion

    // region API 34 family name

    private fun systemDefaultFamilyName(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return null

        val fromDefault = runCatching { Typeface.DEFAULT.systemFontFamilyName }.getOrNull()
        val fromSansSerif = runCatching {
            Typeface.create("sans-serif", Typeface.NORMAL).systemFontFamilyName
        }.getOrNull()
        return (fromDefault ?: fromSansSerif)?.takeIf { it.isNotBlank() }
    }

    private fun matchByFamily(candidates: List<Candidate>, systemFamily: String): Selection? {
        if (candidates.isEmpty()) return null
        val target = normalize(systemFamily)
        if (target.isEmpty()) return null

        val scored = candidates.mapNotNull { candidate ->
            val score = matchScore(candidate, target)
            if (score > 0) candidate to score else null
        }
        if (scored.isEmpty()) return null

        val bestScore = scored.maxOf { it.second }
        val best = scored.first { it.second == bestScore }.first
        val familyKey = primaryFamilyKey(best)
        val group = candidates.filter { primaryFamilyKey(it) == familyKey }
        return selectionFor(systemFamily, group.ifEmpty { listOf(best) })
    }

    private fun matchScore(candidate: Candidate, target: String): Int {
        val names = familyNames(candidate)
        if (names.any { it == target }) return SCORE_EXACT
        if (names.any { it.startsWith(target) || target.startsWith(it) }) return SCORE_PREFIX
        if (names.any { it.contains(target) }) return SCORE_CONTAINS
        val stem = stemOf(candidate)
        if (stem == target || stem.startsWith(target) || target.startsWith(stem)) {
            return SCORE_FILE_NAME
        }
        return 0
    }

    // endregion

    // region Glyph-shape comparison

    private fun metricMatch(candidates: List<Candidate>): Selection? {
        if (candidates.isEmpty()) return null
        val regulars = candidates.filter { it.weight in 300..500 }.ifEmpty { candidates }
        val reference = runCatching { Typeface.create("sans-serif", Typeface.NORMAL) }
            .getOrNull() ?: return null
        val referenceSignature = glyphSignature(reference)

        var best: Candidate? = null
        var bestDistance = Double.MAX_VALUE
        for (candidate in regulars.take(MAX_METRIC_CANDIDATES)) {
            val typeface = typefaceOf(candidate) ?: continue
            val distance = signatureDistance(glyphSignature(typeface), referenceSignature)
            if (distance < bestDistance) {
                bestDistance = distance
                best = candidate
            }
        }

        val winner = best ?: return null
        if (bestDistance > MAX_METRIC_DISTANCE) return null

        val familyKey = primaryFamilyKey(winner)
        val group = candidates.filter { primaryFamilyKey(it) == familyKey }
        return selectionFor(null, group.ifEmpty { listOf(winner) })
    }

    private fun glyphSignature(typeface: Typeface): DoubleArray {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.typeface = typeface
            textSize = 48f
        }
        val path = Path()
        val bounds = RectF()
        val signature = DoubleArray(PROBES.size * 2)
        PROBES.forEachIndexed { index, probe ->
            signature[index * 2] = paint.measureText(probe).toDouble()
            path.reset()
            paint.getTextPath(probe, 0, probe.length, 0f, 0f, path)
            path.computeBounds(bounds, true)
            signature[index * 2 + 1] = bounds.width().toDouble() * 1000.0 + bounds.height()
        }
        return signature
    }

    private fun signatureDistance(candidate: DoubleArray, reference: DoubleArray): Double {
        if (candidate.isEmpty() || candidate.size != reference.size) return Double.MAX_VALUE
        var sum = 0.0
        for (index in candidate.indices) {
            val expected = abs(reference[index]).coerceAtLeast(1.0)
            sum += abs(candidate[index] - reference[index]) / expected
        }
        return sum / candidate.size
    }

    private fun typefaceOf(candidate: Candidate): Typeface? = runCatching {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Typeface.Builder(candidate.file)
                .setTtcIndex(candidate.ttcIndex)
                .setWeight(candidate.weight)
                .build()
        } else {
            Typeface.createFromFile(candidate.file)
        }
    }.getOrNull()

    // endregion

    // region FontManager updatable fonts

    private fun updatableFontCandidates(): Selection? {
        val dataDirs = listOf(
            File("/data/fonts/files"), // Android 12+ FontManager updates
            File("/data/fonts"),
            File("/data/system/fonts"),
        )

        val candidates = dataDirs.flatMap { fontFilesIn(it) }.mapNotNull(::toCandidate)
        if (candidates.isEmpty()) return null

        val groups = candidates.groupBy { primaryFamilyKey(it) }
        // FontManager writes the freshly selected family last; the newest file
        // therefore identifies the active override.
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
                } else if (SfntFont.isFontFile(child) && child.length() > 0L) {
                    files.add(child)
                }
            }
        }

        walk(dir, depth)
        return files
    }

    private fun toCandidate(file: File): Candidate? {
        if (!SfntFont.isFontFile(file)) return null
        return Candidate(
            path = file.absolutePath,
            weight = SfntFont.weight(file) ?: weightFromName(file.name),
            ttcIndex = 0,
            lastModified = file.lastModified(),
            length = file.length(),
        )
    }

    // endregion

    // region Last resort

    private fun singleNonStockFamily(candidates: List<Candidate>): Selection? {
        val groups = candidates
            .groupBy { primaryFamilyKey(it) }
            .filterKeys { key -> key.isNotEmpty() && !isStockFamily(key) }
        if (groups.size != 1) return null
        return selectionFor(null, groups.values.first())
    }

    // endregion

    // region Font enumeration

    private fun mountedCandidates(): List<Candidate> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return emptyList()
        val fonts: Set<Font> = runCatching { SystemFonts.getAvailableFonts() }.getOrNull()
            ?: return emptyList()

        val result = LinkedHashMap<String, Candidate>()
        for (font in fonts) {
            val file = runCatching { font.file }.getOrNull() ?: continue
            if (!SfntFont.isFontFile(file)) continue
            val weight = runCatching { font.style.weight }.getOrDefault(WEIGHT_NORMAL)
            val candidate = Candidate(
                path = file.absolutePath,
                weight = weight.takeIf { it in 1..1000 } ?: WEIGHT_NORMAL,
                ttcIndex = runCatching { font.ttcIndex }.getOrDefault(0),
                lastModified = file.lastModified(),
                length = file.length(),
            )
            result[candidate.key] = candidate
        }
        return result.values.toList()
    }

    private fun selectionFor(familyName: String?, group: List<Candidate>): Selection? {
        if (group.isEmpty()) return null
        val regular = group.filter { it.weight in 300..500 }.minByOrNull { abs(it.weight - 400) }
            ?: group.minByOrNull { abs(it.weight - 400) }
            ?: return null
        val bold = group
            .filter { it.weight in 600..800 && !sameFace(it, regular) }
            .minByOrNull { abs(it.weight - 700) }
        return Selection(familyName, regular, bold)
    }

    private fun sameFace(a: Candidate, b: Candidate): Boolean =
        a.path == b.path && a.ttcIndex == b.ttcIndex

    private fun readFontBytes(candidate: Candidate): ByteArray? = try {
        val file = candidate.file
        if (!file.canRead()) {
            null
        } else {
            val bytes = if (SfntFont.isCollection(file)) {
                SfntFont.extractFace(file, candidate.ttcIndex) ?: file.readBytes()
            } else {
                file.readBytes()
            }
            bytes.takeIf { it.isNotEmpty() && it.size <= MAX_FONT_BYTES }
        }
    } catch (_: Throwable) {
        null
    }

    // endregion

    // region Helpers

    private fun familyNames(candidate: Candidate): Set<String> =
        familyCache.getOrPut(candidate.key) {
            val names = LinkedHashSet<String>()
            SfntFont.familyNames(candidate.file, candidate.ttcIndex)
                .map(::normalize)
                .filterTo(names) { it.isNotEmpty() }
            names.add(stemOf(candidate))
            names
        }

    private fun primaryFamilyKey(candidate: Candidate): String =
        familyNames(candidate).firstOrNull() ?: stemOf(candidate)

    private fun stemOf(candidate: Candidate): String {
        val base = candidate.file.name.substringBeforeLast('.', candidate.file.name)
        val tokens = base.split('-', '_', ' ', '.').filter { it.isNotEmpty() }
        val kept = tokens.dropLastWhile { normalize(it) in VARIANT_TOKENS }
        return normalize(if (kept.isEmpty()) base else kept.joinToString(separator = ""))
    }

    private fun weightFromName(name: String): Int {
        val lower = name.lowercase(Locale.ROOT)
        return when {
            "black" in lower -> 900
            "extrabold" in lower || "ultrabold" in lower || "heavy" in lower -> 800
            "semibold" in lower || "demibold" in lower || "bold" in lower -> 700
            "medium" in lower -> 500
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

    // endregion

    private companion object {
        const val WEIGHT_NORMAL = 400
        const val SCORE_EXACT = 100
        const val SCORE_PREFIX = 60
        const val SCORE_CONTAINS = 40
        const val SCORE_FILE_NAME = 30

        const val MAX_SCANNED_FILES = 256
        const val MAX_METRIC_CANDIDATES = 32
        const val MAX_METRIC_DISTANCE = 0.01
        const val MAX_FONT_BYTES = 48 shl 20

        val PROBES = listOf("Hamburgefontsiv", "0123456789", "MW@#&%")

        /**
         * OEM theme engines publish the font file they currently apply. Values
         * are either absolute or relative to `/`, and may be separated by
         * `:`, `,` or `;`.
         */
        val OVERLAY_FONT_PROPERTIES = listOf(
            "persist.sys.overlayfonts", // Motorola MyUX / Lenovo ZUI
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
