package com.diamond.printer.diamond_printer.protocol

import android.graphics.Bitmap
import android.util.Log
import java.io.ByteArrayOutputStream
import java.nio.charset.Charset

/**
 * ESC/POS printer command generator
 * Supports thermal printers using ESC/POS protocol (Epson compatible)
 */
class ESCPOSCommandGenerator : PrinterCommandGenerator {
    
    companion object {
        private const val TAG = "ESCPOSCommandGen"
        
        // ESC/POS Commands
        private val ESC = 0x1B.toByte()
        private val GS = 0x1D.toByte()
        private val LF = 0x0A.toByte()
        private val CR = 0x0D.toByte()
        
        // Initialize printer
        private val INIT = byteArrayOf(ESC, '@'.code.toByte())
        
        // Text formatting
        private val BOLD_ON = byteArrayOf(ESC, 'E'.code.toByte(), 1)
        private val BOLD_OFF = byteArrayOf(ESC, 'E'.code.toByte(), 0)
        
        // Alignment
        private val ALIGN_LEFT = byteArrayOf(ESC, 'a'.code.toByte(), 0)
        private val ALIGN_CENTER = byteArrayOf(ESC, 'a'.code.toByte(), 1)
        private val ALIGN_RIGHT = byteArrayOf(ESC, 'a'.code.toByte(), 2)
        
        // Cut paper
        private val CUT_PAPER = byteArrayOf(GS, 'V'.code.toByte(), 1)
        
        // Line feed
        private val LINE_FEED = byteArrayOf(LF)
    }
    
    override fun generateTextCommand(text: String): ByteArray {
        val outputStream = ByteArrayOutputStream()
        
        // Initialize printer
        outputStream.write(INIT)
        
        // Write text
        outputStream.write(text.toByteArray(Charset.forName("UTF-8")))
        
        // Multiple line feeds - Bixolon printers often need extra feeds to trigger printing
        // This ensures the text buffer is flushed and printed
        outputStream.write(LINE_FEED)
        outputStream.write(LINE_FEED)
        outputStream.write(LINE_FEED)
        
        return outputStream.toByteArray()
    }
    
    override fun generateImageCommand(bitmap: Bitmap, maxWidth: Int): ByteArray {
        Log.d(TAG, "Generating ESC/POS image command for ${bitmap.width}x${bitmap.height}")
        
        val outputStream = ByteArrayOutputStream()
        
        // Initialize printer
        outputStream.write(INIT)
        
        // Resize image to fit printer width
        val resizedBitmap = if (bitmap.width > maxWidth) {
            val ratio = maxWidth.toFloat() / bitmap.width
            val newHeight = (bitmap.height * ratio).toInt()
            Bitmap.createScaledBitmap(bitmap, maxWidth, newHeight, true)
        } else {
            bitmap
        }
        
        // Convert bitmap to monochrome with dithering
        val monoImage = convertToMonochromeWithDithering(resizedBitmap)
        
        // Generate ESC/POS image command
        val imageData = convertBitmapToESCPOS(monoImage)
        outputStream.write(imageData)
        
        // Clean up
        if (resizedBitmap != bitmap) {
            resizedBitmap.recycle()
        }
        monoImage.recycle()
        
        // Multiple line feeds - Bixolon printers need extra feeds to trigger printing
        // This ensures the image buffer is flushed and printed
        outputStream.write(generateFeedCommand(5))
        
        // Form feed command (0x0C) - standard ESC/POS command to trigger printing
        // This explicitly tells the printer to print the buffered data
        val FORM_FEED = 0x0C
        outputStream.write(FORM_FEED)
        
        // Additional line feeds to ensure printing completes
        outputStream.write(generateFeedCommand(3))
        
        Log.d(TAG, "✓ Successfully encoded image (${outputStream.size()} bytes)")
        return outputStream.toByteArray()
    }
    
    override fun generateCutCommand(): ByteArray {
        return CUT_PAPER
    }
    
    override fun generateFeedCommand(lines: Int): ByteArray {
        val outputStream = ByteArrayOutputStream()
        repeat(lines) {
            outputStream.write(LINE_FEED)
        }
        return outputStream.toByteArray()
    }
    
    /**
     * Convert bitmap to monochrome (black and white) with Floyd-Steinberg dithering
     * This produces much better quality for photos and complex images
     */
    private fun convertToMonochromeWithDithering(bitmap: Bitmap): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        val monoBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        
        // Create a copy of grayscale values for dithering
        val grayValues = Array(height) { IntArray(width) }
        
        // Convert to grayscale first
        for (y in 0 until height) {
            for (x in 0 until width) {
                val pixel = bitmap.getPixel(x, y)
                grayValues[y][x] = (android.graphics.Color.red(pixel) * 0.299 +
                        android.graphics.Color.green(pixel) * 0.587 +
                        android.graphics.Color.blue(pixel) * 0.114).toInt()
            }
        }
        
        // Floyd-Steinberg dithering
        for (y in 0 until height) {
            for (x in 0 until width) {
                val oldPixel = grayValues[y][x]
                val newPixel = if (oldPixel > 128) 255 else 0
                grayValues[y][x] = newPixel
                
                val error = oldPixel - newPixel
                
                // Distribute error to neighboring pixels
                if (x + 1 < width) {
                    grayValues[y][x + 1] += (error * 7 / 16)
                }
                if (y + 1 < height) {
                    if (x > 0) {
                        grayValues[y + 1][x - 1] += (error * 3 / 16)
                    }
                    grayValues[y + 1][x] += (error * 5 / 16)
                    if (x + 1 < width) {
                        grayValues[y + 1][x + 1] += (error * 1 / 16)
                    }
                }
                
                // Set the pixel in output bitmap
                val color = if (newPixel == 255) {
                    android.graphics.Color.WHITE
                } else {
                    android.graphics.Color.BLACK
                }
                monoBitmap.setPixel(x, y, color)
            }
        }
        
        return monoBitmap
    }
    
    /**
     * Simple threshold conversion (faster but lower quality)
     */
    private fun convertToMonochrome(bitmap: Bitmap): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        val monoBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        
        for (y in 0 until height) {
            for (x in 0 until width) {
                val pixel = bitmap.getPixel(x, y)
                val gray = (android.graphics.Color.red(pixel) * 0.299 +
                        android.graphics.Color.green(pixel) * 0.587 +
                        android.graphics.Color.blue(pixel) * 0.114).toInt()
                
                val monoColor = if (gray > 128) {
                    android.graphics.Color.WHITE
                } else {
                    android.graphics.Color.BLACK
                }
                
                monoBitmap.setPixel(x, y, monoColor)
            }
        }
        
        return monoBitmap
    }
    
    /**
     * Convert bitmap to ESC/POS image format
     * Uses ESC * m nL nH d1...dk format
     */
    private fun convertBitmapToESCPOS(bitmap: Bitmap): ByteArray {
        val outputStream = ByteArrayOutputStream()
        val width = bitmap.width
        val height = bitmap.height
        
        // Align center for better appearance
        outputStream.write(ALIGN_CENTER)
        
        // Process image in 24-dot lines (3 bytes per column)
        var y = 0
        while (y < height) {
            // ESC * m nL nH - Select bit-image mode
            outputStream.write(ESC.toInt())
            outputStream.write('*'.code)
            outputStream.write(33) // 24-dot double-density mode
            
            // Width in bytes (little-endian)
            outputStream.write(width and 0xFF)
            outputStream.write((width shr 8) and 0xFF)
            
            // Process each column
            for (x in 0 until width) {
                // Process 24 pixels (3 bytes) in this column
                for (byteIndex in 0..2) {
                    var byteValue = 0
                    for (bit in 0..7) {
                        val pixelY = y + byteIndex * 8 + bit
                        if (pixelY < height) {
                            val pixel = bitmap.getPixel(x, pixelY)
                            // If pixel is black, set bit
                            if (android.graphics.Color.red(pixel) < 128) {
                                byteValue = byteValue or (1 shl (7 - bit))
                            }
                        }
                    }
                    outputStream.write(byteValue)
                }
            }
            
            outputStream.write(LF.toInt())
            y += 24
        }
        
        // Reset alignment
        outputStream.write(ALIGN_LEFT)
        
        return outputStream.toByteArray()
    }
    
    /**
     * Generate bold text command
     */
    fun generateBoldText(text: String): ByteArray {
        val outputStream = ByteArrayOutputStream()
        outputStream.write(BOLD_ON)
        outputStream.write(text.toByteArray(Charset.forName("UTF-8")))
        outputStream.write(BOLD_OFF)
        outputStream.write(LINE_FEED)
        return outputStream.toByteArray()
    }
}

