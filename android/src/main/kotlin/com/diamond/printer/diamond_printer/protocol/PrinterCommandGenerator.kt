package com.diamond.printer.diamond_printer.protocol

import android.graphics.Bitmap

/**
 * Base interface for printer command generators
 */
interface PrinterCommandGenerator {
    fun generateTextCommand(text: String, alignment: String? = null): ByteArray
    fun generateImageCommand(bitmap: Bitmap, maxWidth: Int = 576, alignment: String? = null): ByteArray
    fun generateCutCommand(): ByteArray
    fun generateFeedCommand(lines: Int = 3): ByteArray
}

