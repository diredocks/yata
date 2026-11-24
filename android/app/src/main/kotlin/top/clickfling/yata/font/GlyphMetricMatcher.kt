package top.clickfling.yata.font

import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import java.util.Locale
import kotlin.math.abs

internal object GlyphMetricMatcher {

    private const val MAX_CANDIDATES = 64
    private const val MAX_DISTANCE = 0.01
    private const val EXACT_DISTANCE = 1e-6
    private const val PROBE_TEXT_SIZE = 48f

    private val PROBES = listOf("Hamburgefontsiv", "0123456789", "MW@#&%")

    fun findBestMatch(candidates: List<FontCandidate>): FontCandidate? {
        val upright = candidates.filterNot { it.italic }
        if (upright.isEmpty()) return null

        val pool = upright.filter { it.weight in 300..500 }.ifEmpty { upright }
        val prioritized = pool.sortedWith(
            compareBy<FontCandidate>(
                { priorityOf(it) },
                { abs(it.weight - 400) },
                { it.file.name },
            ),
        )

        val reference = runCatching { Typeface.create("sans-serif", Typeface.NORMAL) }
            .getOrNull() ?: return null
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = PROBE_TEXT_SIZE }
        val path = Path()
        val bounds = RectF()
        val referenceSignature = glyphSignature(reference, paint, path, bounds)

        var best: FontCandidate? = null
        var bestDistance = Double.MAX_VALUE
        for (candidate in prioritized.take(MAX_CANDIDATES)) {
            val typeface = typefaceOf(candidate) ?: continue
            val distance = signatureDistance(
                glyphSignature(typeface, paint, path, bounds),
                referenceSignature,
            )
            if (distance < bestDistance) {
                bestDistance = distance
                best = candidate
                if (bestDistance <= EXACT_DISTANCE) break
            }
        }

        return best?.takeIf { bestDistance <= MAX_DISTANCE }
    }

    private fun priorityOf(candidate: FontCandidate): Int {
        val lower = candidate.file.name.lowercase(Locale.ROOT)
        return when {
            !lower.startsWith("noto") -> 0
            lower.startsWith("notosans-") ||
                lower.startsWith("notoserif-") ||
                "cjk" in lower -> 1
            else -> 2
        }
    }

    private fun glyphSignature(
        typeface: Typeface,
        paint: Paint,
        path: Path,
        bounds: RectF,
    ): DoubleArray {
        paint.typeface = typeface
        val signature = DoubleArray(PROBES.size * 3)
        PROBES.forEachIndexed { index, probe ->
            val offset = index * 3
            signature[offset] = paint.measureText(probe).toDouble()
            path.reset()
            paint.getTextPath(probe, 0, probe.length, 0f, 0f, path)
            path.computeBounds(bounds, true)
            signature[offset + 1] = bounds.width().toDouble()
            signature[offset + 2] = bounds.height().toDouble()
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

    private fun typefaceOf(candidate: FontCandidate): Typeface? = runCatching {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Typeface.Builder(candidate.file)
                .setTtcIndex(candidate.ttcIndex)
                .setWeight(candidate.weight)
                .build()
        } else {
            Typeface.createFromFile(candidate.file)
        }
    }.getOrNull()
}
