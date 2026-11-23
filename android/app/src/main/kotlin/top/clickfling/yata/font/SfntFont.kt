package top.clickfling.yata.font

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale

/**
 * Minimal `sfnt` container reader used by [SystemFontResolver].
 *
 * Supports plain TrueType (`0x00010000`), OpenType/CFF (`OTTO`), Apple `true`
 * and font collections (`ttcf`). Only what is needed to identify a face is
 * implemented: the table directory, the `name` table (family names), the
 * `OS/2` weight and extraction of a single face out of a collection — the
 * Flutter engine always renders face #0 of a multi-face blob, which would be
 * the wrong family for most `.ttc` system fonts.
 */
internal object SfntFont {

    private const val TAG_TTCF = 0x74746366 // 'ttcf'
    private const val TAG_OTTO = 0x4F54544F // 'OTTO'
    private const val TAG_TRUE = 0x74727565 // 'true'
    private const val TAG_TYP1 = 0x74797031 // 'typ1'
    private const val VERSION_TRUE_TYPE = 0x00010000

    private const val NAME_ID_FAMILY = 1
    private const val NAME_ID_TYPOGRAPHIC_FAMILY = 16

    private const val MAX_TABLES = 512
    private const val MAX_NAME_RECORDS = 4096
    private const val MAX_NAME_TABLE_BYTES = 1 shl 20
    private const val MAX_FACE_BYTES = 48 shl 20

    private val FONT_EXTENSIONS = setOf("ttf", "otf", "ttc", "otc")

    data class Table(
        val tag: Int,
        val checksum: Long,
        val offset: Long,
        val length: Long,
    ) {
        val name: String get() = tagToString(tag)
    }

    fun extension(file: File): String =
        file.name.substringAfterLast('.', "").lowercase(Locale.ROOT)

    /** `true` when [file] looks like a readable sfnt container. */
    fun isFontFile(file: File): Boolean =
        file.isFile && file.canRead() && file.length() > 0L && extension(file) in FONT_EXTENSIONS

    /** `true` when [name] carries a font file extension. */
    fun hasFontExtension(name: String): Boolean =
        name.substringAfterLast('.', "").lowercase(Locale.ROOT) in FONT_EXTENSIONS

    /** `true` when [file] is a font collection (`.ttc` / `.otc`). */
    fun isCollection(file: File): Boolean = runCatching {
        RandomAccessFile(file, "r").use { raf -> readTag(raf, 0L) == TAG_TTCF }
    }.getOrDefault(false)

    /**
     * Family names declared in the `name` table of [file], most specific first
     * (`nameID = 16`, typographic family, then `nameID = 1`).
     */
    fun familyNames(file: File, ttcIndex: Int = 0): List<String> = runCatching {
        RandomAccessFile(file, "r").use { raf ->
            val faceOffset = faceOffset(raf, ttcIndex) ?: return@use emptyList()
            val tables = tableDirectory(raf, faceOffset) ?: return@use emptyList()
            val nameTable = tables.firstOrNull { it.name == "name" } ?: return@use emptyList()
            readFamilyNames(raf, nameTable)
        }
    }.getOrDefault(emptyList())

    /** `true` when the face is italic or oblique. */
    fun isItalic(file: File, ttcIndex: Int = 0): Boolean = runCatching {
        RandomAccessFile(file, "r").use { raf ->
            val faceOffset = faceOffset(raf, ttcIndex) ?: return@use false
            val tables = tableDirectory(raf, faceOffset) ?: return@use false

            // head.macStyle, bit 1
            val head = tables.firstOrNull { it.name == "head" }
            if (head != null && head.length >= 46L) {
                raf.seek(head.offset + 44L)
                if (raf.readUnsignedShort() and 0x02 != 0) return@use true
            }

            // OS/2.fsSelection, bit 0
            val os2 = tables.firstOrNull { it.name == "OS/2" }
            if (os2 != null && os2.length >= 64L) {
                raf.seek(os2.offset + 62L)
                if (raf.readUnsignedShort() and 0x01 != 0) return@use true
            }
            false
        }
    }.getOrDefault(false)

    /** `usWeightClass` from the `OS/2` table, or `null` when unavailable. */
    fun weight(file: File, ttcIndex: Int = 0): Int? = runCatching {
        RandomAccessFile(file, "r").use { raf ->
            val faceOffset = faceOffset(raf, ttcIndex) ?: return@use null
            val tables = tableDirectory(raf, faceOffset) ?: return@use null
            val os2 = tables.firstOrNull { it.name == "OS/2" } ?: return@use null
            if (os2.length < 6L) return@use null
            raf.seek(os2.offset + 4L)
            val weight = raf.readUnsignedShort()
            // A zero weight is invalid; treat it as unknown.
            weight.takeIf { it in 1..1000 }
        }
    }.getOrNull()

    /**
     * Rebuilds the face at [ttcIndex] of [file] as a standalone font so that it
     * can be handed to `FontLoader` unchanged.
     *
     * Returns `null` when [file] is not a collection or when extraction fails;
     * callers should then fall back to the raw file bytes.
     */
    fun extractFace(file: File, ttcIndex: Int): ByteArray? = runCatching {
        RandomAccessFile(file, "r").use { raf ->
            val faceOffset = faceOffset(raf, ttcIndex) ?: return@use null
            val tables = tableDirectory(raf, faceOffset) ?: return@use null
            if (tables.isEmpty()) return@use null
            writeFace(raf, faceOffset, tables)
        }
    }.getOrNull()

    private fun writeFace(
        raf: RandomAccessFile,
        faceOffset: Long,
        tables: List<Table>,
    ): ByteArray? {
        raf.seek(faceOffset)
        val header = ByteArray(12)
        raf.readFully(header)
        if (u16(header, 4) != tables.size) return null

        val dataStart = 12L + tables.size * 16L
        var total = dataStart
        for (table in tables) {
            total += align4(table.length)
        }
        if (total > MAX_FACE_BYTES) return null

        val offsets = LongArray(tables.size)
        var cursor = dataStart
        for ((index, table) in tables.withIndex()) {
            offsets[index] = cursor
            cursor += align4(table.length)
        }

        val out = ByteArray(total.toInt())
        System.arraycopy(header, 0, out, 0, 12)
        var record = 12
        for ((index, table) in tables.withIndex()) {
            putU32(out, record, table.tag.toLong() and 0xFFFFFFFFL)
            putU32(out, record + 4, table.checksum)
            putU32(out, record + 8, offsets[index])
            putU32(out, record + 12, table.length)
            record += 16
        }
        for ((index, table) in tables.withIndex()) {
            if (table.length <= 0L) continue
            raf.seek(table.offset)
            raf.readFully(out, offsets[index].toInt(), table.length.toInt())
        }
        return out
    }

    private fun readFamilyNames(raf: RandomAccessFile, table: Table): List<String> {
        val length = minOf(table.length, MAX_NAME_TABLE_BYTES.toLong()).toInt()
        if (length < 6) return emptyList()
        raf.seek(table.offset)
        val data = ByteArray(length)
        raf.readFully(data)

        val count = u16(data, 2)
        val storageStart = u16(data, 4)
        if (count <= 0) return emptyList()

        // LinkedHashMap keeps the first-seen order; typographic names
        // (nameID 16) win over legacy family names (nameID 1).
        val names = LinkedHashMap<String, Int>()
        for (index in 0 until minOf(count, MAX_NAME_RECORDS)) {
            val record = 6 + index * 12
            if (record + 12 > data.size) break
            val platform = u16(data, record)
            val encoding = u16(data, record + 2)
            val nameId = u16(data, record + 6)
            if (nameId != NAME_ID_FAMILY && nameId != NAME_ID_TYPOGRAPHIC_FAMILY) continue
            val stringLength = u16(data, record + 8)
            val stringStart = storageStart + u16(data, record + 10)
            if (stringLength <= 0 || stringStart + stringLength > data.size) continue
            val value = decodeName(data, platform, encoding, stringStart, stringLength).trim()
            if (value.isEmpty()) continue
            val priority = if (nameId == NAME_ID_TYPOGRAPHIC_FAMILY) 0 else 1
            val existing = names[value]
            if (existing == null || priority < existing) names[value] = priority
        }
        return names.entries.sortedBy { it.value }.map { it.key }
    }

    private fun decodeName(
        data: ByteArray,
        platform: Int,
        encoding: Int,
        start: Int,
        length: Int,
    ): String = when (platform) {
        // Unicode (0) and Windows (3) strings are UTF-16BE, except for the
        // symbol encoding, which carries single-byte data.
        0, 3 -> if (platform == 3 && encoding == 0) {
            String(data, start, length, Charsets.ISO_8859_1)
        } else {
            String(data, start, length - length % 2, Charsets.UTF_16BE)
        }
        // Macintosh Roman; good enough for ASCII family names.
        1 -> String(data, start, length, Charsets.ISO_8859_1)
        else -> ""
    }

    private fun faceOffset(raf: RandomAccessFile, ttcIndex: Int): Long? {
        val tag = readTag(raf, 0L) ?: return null
        if (tag != TAG_TTCF) return if (ttcIndex == 0) 0L else null

        val fileLength = raf.length()
        raf.seek(8)
        val faceCount = raf.readInt()
        if (faceCount <= 0 || faceCount > MAX_TABLES) return null
        val index = ttcIndex.coerceIn(0, faceCount - 1)
        raf.seek(12L + index * 4L)
        val offset = raf.readInt().toLong() and 0xFFFFFFFFL
        return offset.takeIf { it in 0 until fileLength }
    }

    private fun tableDirectory(raf: RandomAccessFile, faceOffset: Long): List<Table>? {
        val fileLength = raf.length()
        if (faceOffset + 12L > fileLength) return null

        raf.seek(faceOffset)
        val header = ByteArray(12)
        raf.readFully(header)
        val version = ByteBuffer.wrap(header, 0, 4).order(ByteOrder.BIG_ENDIAN).int
        if (version != VERSION_TRUE_TYPE && version != TAG_OTTO &&
            version != TAG_TRUE && version != TAG_TYP1
        ) {
            return null
        }

        val numTables = u16(header, 4)
        if (numTables <= 0 || numTables > MAX_TABLES) return null
        val directoryLength = 12 + numTables * 16
        if (faceOffset + directoryLength > fileLength) return null

        raf.seek(faceOffset)
        val directory = ByteArray(directoryLength)
        raf.readFully(directory)

        val tables = ArrayList<Table>(numTables)
        var offset = 12
        repeat(numTables) {
            val tableOffset = u32(directory, offset + 8)
            val tableLength = u32(directory, offset + 12)
            if (tableOffset + tableLength <= fileLength) {
                tables += Table(
                    tag = u32(directory, offset).toInt(),
                    checksum = u32(directory, offset + 4),
                    offset = tableOffset,
                    length = tableLength,
                )
            }
            offset += 16
        }
        return tables
    }

    private fun readTag(raf: RandomAccessFile, position: Long): Int? {
        if (position + 4 > raf.length()) return null
        raf.seek(position)
        return raf.readInt()
    }

    private fun tagToString(tag: Int): String = String(
        byteArrayOf(
            (tag ushr 24).toByte(),
            (tag ushr 16).toByte(),
            (tag ushr 8).toByte(),
            tag.toByte(),
        ),
        Charsets.ISO_8859_1,
    )

    private fun u16(data: ByteArray, offset: Int): Int {
        if (offset + 2 > data.size) return 0
        return ((data[offset].toInt() and 0xFF) shl 8) or (data[offset + 1].toInt() and 0xFF)
    }

    private fun u32(data: ByteArray, offset: Int): Long {
        if (offset + 4 > data.size) return 0L
        return ((data[offset].toLong() and 0xFF) shl 24) or
            ((data[offset + 1].toLong() and 0xFF) shl 16) or
            ((data[offset + 2].toLong() and 0xFF) shl 8) or
            (data[offset + 3].toLong() and 0xFF)
    }

    private fun putU32(data: ByteArray, offset: Int, value: Long) {
        data[offset] = (value ushr 24).toByte()
        data[offset + 1] = (value ushr 16).toByte()
        data[offset + 2] = (value ushr 8).toByte()
        data[offset + 3] = value.toByte()
    }

    private fun align4(value: Long): Long = (value + 3L) and 3L.inv()
}
