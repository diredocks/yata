package top.clickfling.yata.font

import java.io.File
import java.io.RandomAccessFile
import java.util.Locale

internal object SfntFont {

    const val MAX_FACE_BYTES = 48 shl 20

    private const val TAG_TTCF = 0x74746366 // 'ttcf'
    private const val TAG_OTTO = 0x4F54544F // 'OTTO'
    private const val TAG_TRUE = 0x74727565 // 'true'
    private const val TAG_TYP1 = 0x74797031 // 'typ1'
    private const val TAG_NAME = 0x6E616D65 // 'name'
    private const val TAG_HEAD = 0x68656164 // 'head'
    private const val TAG_OS2 = 0x4F532F32 // 'OS/2'
    private const val VERSION_TRUE_TYPE = 0x00010000

    private const val NAME_ID_FAMILY = 1
    private const val NAME_ID_TYPOGRAPHIC_FAMILY = 16

    private const val MAX_TABLES = 512
    private const val MAX_NAME_RECORDS = 4096
    private const val MAX_NAME_TABLE_BYTES = 1 shl 20

    private val FONT_EXTENSIONS = setOf("ttf", "otf", "ttc", "otc")

    data class FaceMetadata(
        val familyNames: List<String>,
        val weight: Int?,
        val italic: Boolean,
    )

    private class Table(
        val tag: Int,
        val checksum: Long,
        val offset: Long,
        val length: Long,
    )

    private class FaceDirectory(
        val header: ByteArray,
        val tables: List<Table>,
    )

    fun hasFontExtension(name: String): Boolean =
        name.substringAfterLast('.', "").lowercase(Locale.ROOT) in FONT_EXTENSIONS

    fun isFontFile(file: File): Boolean =
        file.isFile && file.canRead() && file.length() > 0L && hasFontExtension(file.name)

    fun familyNames(file: File, ttcIndex: Int = 0): List<String> = runCatching {
        RandomAccessFile(file, "r").use { raf ->
            val faceOffset = faceOffset(raf, ttcIndex) ?: return@use emptyList()
            val directory = readFaceDirectory(raf, faceOffset) ?: return@use emptyList()
            readFamilyNames(raf, directory.tables)
        }
    }.getOrDefault(emptyList())

    fun readMetadata(file: File, ttcIndex: Int = 0): FaceMetadata? = runCatching {
        RandomAccessFile(file, "r").use { raf ->
            val faceOffset = faceOffset(raf, ttcIndex) ?: return@use null
            val directory = readFaceDirectory(raf, faceOffset) ?: return@use null
            FaceMetadata(
                familyNames = readFamilyNames(raf, directory.tables),
                weight = readWeight(raf, directory.tables),
                italic = readItalic(raf, directory.tables),
            )
        }
    }.getOrNull()

    fun readFaceBytes(
        file: File,
        ttcIndex: Int = 0,
        maxBytes: Int = MAX_FACE_BYTES,
    ): ByteArray? = runCatching {
        RandomAccessFile(file, "r").use { raf ->
            val fileLength = raf.length()
            if (fileLength <= 0L) return@use null
            val tag = readTag(raf, 0L) ?: return@use null
            // Flutter renders face #0 of a .ttc, so extract the target face.
            if (tag == TAG_TTCF) {
                val faceOffset = ttcFaceOffset(raf, ttcIndex, fileLength) ?: return@use null
                val directory = readFaceDirectory(raf, faceOffset) ?: return@use null
                writeFace(raf, directory, maxBytes)
            } else {
                if (ttcIndex != 0 || fileLength > maxBytes.toLong()) return@use null
                val out = ByteArray(fileLength.toInt())
                raf.seek(0L)
                raf.readFully(out)
                out
            }
        }
    }.getOrNull()

    private fun readWeight(raf: RandomAccessFile, tables: List<Table>): Int? {
        val os2 = tables.firstOrNull { it.tag == TAG_OS2 } ?: return null
        if (os2.length < 6L) return null
        raf.seek(os2.offset + 4L)
        val weight = raf.readUnsignedShort()
        return weight.takeIf { it in 1..1000 }
    }

    private fun readItalic(raf: RandomAccessFile, tables: List<Table>): Boolean {
        // head.macStyle bit 1
        val head = tables.firstOrNull { it.tag == TAG_HEAD }
        if (head != null && head.length >= 46L) {
            raf.seek(head.offset + 44L)
            if (raf.readUnsignedShort() and 0x02 != 0) return true
        }

        // OS/2.fsSelection bit 0 (italic) / bit 9 (oblique)
        val os2 = tables.firstOrNull { it.tag == TAG_OS2 }
        if (os2 != null && os2.length >= 64L) {
            raf.seek(os2.offset + 62L)
            if (raf.readUnsignedShort() and 0x0201 != 0) return true
        }
        return false
    }

    private fun writeFace(
        raf: RandomAccessFile,
        directory: FaceDirectory,
        maxBytes: Int,
    ): ByteArray? {
        val header = directory.header
        val tables = directory.tables
        if (u16(header, 4) != tables.size) return null

        val dataStart = 12L + tables.size * 16L
        var total = dataStart
        for (table in tables) {
            if (table.length > maxBytes.toLong()) return null
            total += align4(table.length)
            if (total > maxBytes.toLong()) return null
        }

        val offsets = IntArray(tables.size)
        var cursor = dataStart.toInt()
        for ((index, table) in tables.withIndex()) {
            offsets[index] = cursor
            cursor += align4(table.length).toInt()
        }

        val out = ByteArray(total.toInt())
        System.arraycopy(header, 0, out, 0, 12)
        var record = 12
        for ((index, table) in tables.withIndex()) {
            putU32(out, record, table.tag.toLong() and 0xFFFFFFFFL)
            putU32(out, record + 4, table.checksum)
            putU32(out, record + 8, offsets[index].toLong() and 0xFFFFFFFFL)
            putU32(out, record + 12, table.length)
            record += 16
        }
        for ((index, table) in tables.withIndex()) {
            if (table.length <= 0L) continue
            raf.seek(table.offset)
            raf.readFully(out, offsets[index], table.length.toInt())
        }
        return out
    }

    private fun readFamilyNames(raf: RandomAccessFile, tables: List<Table>): List<String> {
        val table = tables.firstOrNull { it.tag == TAG_NAME } ?: return emptyList()
        val length = minOf(table.length, MAX_NAME_TABLE_BYTES.toLong()).toInt()
        if (length < 6) return emptyList()
        raf.seek(table.offset)
        val data = ByteArray(length)
        raf.readFully(data)

        val count = u16(data, 2)
        val storageStart = u16(data, 4)
        if (count <= 0) return emptyList()

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
        // Platform 0 (Unicode), 3 (Windows; encoding 0 = symbol), 1 (Mac Roman)
        0, 3 -> if (platform == 3 && encoding == 0) {
            String(data, start, length, Charsets.ISO_8859_1)
        } else {
            String(data, start, length - length % 2, Charsets.UTF_16BE)
        }
        1 -> String(data, start, length, Charsets.ISO_8859_1)
        else -> ""
    }

    private fun faceOffset(raf: RandomAccessFile, ttcIndex: Int): Long? {
        val fileLength = raf.length()
        val tag = readTag(raf, 0L) ?: return null
        if (tag != TAG_TTCF) return if (ttcIndex == 0) 0L else null
        return ttcFaceOffset(raf, ttcIndex, fileLength)
    }

    private fun ttcFaceOffset(
        raf: RandomAccessFile,
        ttcIndex: Int,
        fileLength: Long,
    ): Long? {
        if (fileLength < 12L || ttcIndex < 0) return null
        raf.seek(8L)
        val faceCount = raf.readInt()
        if (faceCount <= 0 || faceCount > MAX_TABLES || ttcIndex >= faceCount) return null
        val entryPos = 12L + ttcIndex * 4L
        if (entryPos + 4L > fileLength) return null
        raf.seek(entryPos)
        val offset = raf.readInt().toLong() and 0xFFFFFFFFL
        return offset.takeIf { it in 0L until fileLength }
    }

    private fun readFaceDirectory(raf: RandomAccessFile, faceOffset: Long): FaceDirectory? {
        val fileLength = raf.length()
        if (faceOffset < 0L || faceOffset + 12L > fileLength) return null

        raf.seek(faceOffset)
        val header = ByteArray(12)
        raf.readFully(header)
        val version = u32(header, 0).toInt()
        if (version != VERSION_TRUE_TYPE && version != TAG_OTTO &&
            version != TAG_TRUE && version != TAG_TYP1
        ) {
            return null
        }

        val numTables = u16(header, 4)
        if (numTables <= 0 || numTables > MAX_TABLES) return null
        val entriesLength = numTables * 16
        if (faceOffset + 12L + entriesLength > fileLength) return null

        val entries = ByteArray(entriesLength)
        raf.readFully(entries)

        val tables = ArrayList<Table>(numTables)
        var offset = 0
        repeat(numTables) {
            val tableOffset = u32(entries, offset + 8)
            val tableLength = u32(entries, offset + 12)
            if (tableOffset + tableLength <= fileLength) {
                tables += Table(
                    tag = u32(entries, offset).toInt(),
                    checksum = u32(entries, offset + 4),
                    offset = tableOffset,
                    length = tableLength,
                )
            }
            offset += 16
        }
        if (tables.isEmpty()) return null
        return FaceDirectory(header, tables)
    }

    private fun readTag(raf: RandomAccessFile, position: Long): Int? {
        if (position + 4 > raf.length()) return null
        raf.seek(position)
        return raf.readInt()
    }

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
