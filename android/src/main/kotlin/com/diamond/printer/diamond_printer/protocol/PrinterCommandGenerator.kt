package com.diamond.printer.diamond_printer.protocol

import android.graphics.Bitmap

/**
 * Base interface for printer command generators
 */
interface PrinterCommandGenerator {
    fun generateTextCommand(text: String): ByteArray
    fun generateImageCommand(bitmap: Bitmap, maxWidth: Int = 576): ByteArray
    fun generateCutCommand(): ByteArray
    fun generateFeedCommand(lines: Int = 3): ByteArray
}

