package com.diamond.printer.diamond_printer.protocol

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
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
    
    override fun generateTextCommand(text: String, alignment: String?): ByteArray {
        val outputStream = ByteArrayOutputStream()
        
        // Initialize printer
        outputStream.write(INIT)
        
        // Set proper character encoding for international characters
        // ESC t n - Select character code table (n=28 for UTF-8 on most printers)
        outputStream.write(byteArrayOf(ESC, 't'.code.toByte(), 28))
        
        // Set alignment: ESC a n where n = 0 (left), 1 (center), 2 (right)
        val alignValue: Byte = when ((alignment ?: "left").lowercase()) {
            "center" -> 1
            "right" -> 2
            else -> 0 // left (default)
        }
        outputStream.write(byteArrayOf(ESC, 'a'.code.toByte(), alignValue))
        
        // Set optimal line spacing for text readability (30/180 inch ≈ 4.2mm)
        outputStream.write(byteArrayOf(ESC, '3'.code.toByte(), 30))
        
        // Write text
        outputStream.write(text.toByteArray(Charset.forName("UTF-8")))
        
        // Single line feed - enough to trigger printing without causing gaps
        // Bixolon printers need at least one line feed to flush the buffer
        outputStream.write(LINE_FEED)
        
        // Restore default line spacing after text
        outputStream.write(byteArrayOf(ESC, '2'.code.toByte()))
        
        // Reset to left alignment
        outputStream.write(ALIGN_LEFT)
        
        return outputStream.toByteArray()
    }
    
    override fun generateImageCommand(bitmap: Bitmap, maxWidth: Int, alignment: String?): ByteArray {
        Log.d(TAG, "Generating ESC/POS image command for ${bitmap.width}x${bitmap.height}")
        
        val outputStream = ByteArrayOutputStream()
        
        // Initialize printer
        outputStream.write(INIT)
        
        // Resize image to fit printer width using high-quality scaling
        // Scale up if smaller, scale down if larger, to always fill paper width
        val resizedBitmap = if (bitmap.width != maxWidth) {
            scaleWithHighQuality(bitmap, maxWidth)
        } else {
            bitmap
        }
        
        // Safety check: ensure width doesn't exceed maxWidth (prevent right-side cutoff)
        val finalBitmap = if (resizedBitmap.width > maxWidth) {
            Log.w(TAG, "⚠️ Resized bitmap width (${resizedBitmap.width}) exceeds maxWidth ($maxWidth), scaling down again")
            scaleWithHighQuality(resizedBitmap, maxWidth)
        } else {
            resizedBitmap
        }
        
        // Final width check and logging - ensure width never exceeds maxWidth
        Log.d(TAG, "Final bitmap dimensions: ${finalBitmap.width}x${finalBitmap.height}, maxWidth: $maxWidth")
        if (finalBitmap.width > maxWidth) {
            Log.e(TAG, "❌ ERROR: Final bitmap width (${finalBitmap.width}) still exceeds maxWidth ($maxWidth)! This will cause right-side cutoff.")
            // Force resize to maxWidth as last resort
            val correctedBitmap = scaleWithHighQuality(finalBitmap, maxWidth)
            if (finalBitmap != correctedBitmap && finalBitmap != bitmap && finalBitmap != resizedBitmap) {
                finalBitmap.recycle()
            }
            return generateImageCommand(correctedBitmap, maxWidth, alignment)
        }
        
        // Enhance contrast for sharper thermal printer output
        val enhancedBitmap = enhanceContrast(finalBitmap)
        
        // Convert bitmap to monochrome with dithering
        val monoImage = convertToMonochromeWithDithering(enhancedBitmap)
        
        // Clean up enhanced bitmap if it was created
        if (enhancedBitmap != finalBitmap) {
            enhancedBitmap.recycle()
        }
        
        // Generate ESC/POS image command - pass maxWidth and alignment
        val imageData = convertBitmapToESCPOS(monoImage, maxWidth, alignment)
        outputStream.write(imageData)
        
        // Clean up bitmaps
        if (finalBitmap != bitmap && finalBitmap != resizedBitmap) {
            finalBitmap.recycle()
        }
        if (resizedBitmap != bitmap && resizedBitmap != finalBitmap) {
            resizedBitmap.recycle()
        }
        monoImage.recycle()
        
        // Single line feed to trigger printing (reduced from 8 to minimize bottom space)
        outputStream.write(generateFeedCommand(1))
        
        // Form feed command (0x0C) - standard ESC/POS command to trigger printing
        val FORM_FEED = 0x0C
        outputStream.write(FORM_FEED)
        
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
     * Uses adaptive threshold based on image brightness for optimal output quality
     */
    private fun convertToMonochromeWithDithering(bitmap: Bitmap): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        val monoBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        
        // Create a copy of grayscale values for dithering
        val grayValues = Array(height) { IntArray(width) }
        
        // Convert to grayscale and calculate average brightness
        var totalBrightness = 0L
        for (y in 0 until height) {
            for (x in 0 until width) {
                val pixel = bitmap.getPixel(x, y)
                val gray = (android.graphics.Color.red(pixel) * 0.299 +
                        android.graphics.Color.green(pixel) * 0.587 +
                        android.graphics.Color.blue(pixel) * 0.114).toInt()
                grayValues[y][x] = gray
                totalBrightness += gray
            }
        }
        
        // Calculate adaptive threshold based on image brightness
        val avgBrightness = (totalBrightness / (width * height)).toInt()
        val threshold = when {
            avgBrightness < 85 -> 100   // Dark image - lower threshold for more detail
            avgBrightness > 170 -> 160  // Light image - higher threshold for clarity
            else -> 128                  // Normal balanced threshold
        }
        Log.d(TAG, "Image brightness: $avgBrightness, using threshold: $threshold")
        
        // Floyd-Steinberg dithering with adaptive threshold
        for (y in 0 until height) {
            for (x in 0 until width) {
                val oldPixel = grayValues[y][x].coerceIn(0, 255)
                val newPixel = if (oldPixel > threshold) 255 else 0
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
     * Scale bitmap with high-quality filtering for better detail preservation
     */
    private fun scaleWithHighQuality(bitmap: Bitmap, maxWidth: Int): Bitmap {
        val ratio = maxWidth.toFloat() / bitmap.width
        val newHeight = (bitmap.height * ratio).toInt()
        
        // Create scaled bitmap with high-quality paint filter
        val scaledBitmap = Bitmap.createBitmap(maxWidth, newHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(scaledBitmap)
        
        // Use high-quality paint with bilinear filtering
        val paint = Paint().apply {
            isFilterBitmap = true
            isAntiAlias = true
            isDither = true
        }
        
        val matrix = Matrix()
        matrix.setScale(ratio, ratio)
        canvas.drawBitmap(bitmap, matrix, paint)
        
        Log.d(TAG, "Scaled image from ${bitmap.width}x${bitmap.height} to ${maxWidth}x${newHeight}")
        return scaledBitmap
    }
    
    /**
     * Enhance contrast for sharper thermal printer output
     * Normalizes histogram to improve black/white separation
     */
    private fun enhanceContrast(bitmap: Bitmap): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        
        // Find min and max brightness values
        var minBrightness = 255
        var maxBrightness = 0
        
        for (y in 0 until height) {
            for (x in 0 until width) {
                val pixel = bitmap.getPixel(x, y)
                val gray = (android.graphics.Color.red(pixel) * 0.299 +
                        android.graphics.Color.green(pixel) * 0.587 +
                        android.graphics.Color.blue(pixel) * 0.114).toInt()
                minBrightness = minOf(minBrightness, gray)
                maxBrightness = maxOf(maxBrightness, gray)
            }
        }
        
        // If contrast is already good, return original
        val range = maxBrightness - minBrightness
        if (range > 200) {
            Log.d(TAG, "Image contrast is good (range: $range), skipping enhancement")
            return bitmap
        }
        
        // Create enhanced bitmap with stretched histogram
        val enhancedBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val scale = if (range > 0) 255.0 / range else 1.0
        
        for (y in 0 until height) {
            for (x in 0 until width) {
                val pixel = bitmap.getPixel(x, y)
                val r = android.graphics.Color.red(pixel)
                val g = android.graphics.Color.green(pixel)
                val b = android.graphics.Color.blue(pixel)
                
                // Stretch each channel
                val newR = ((r - minBrightness) * scale).toInt().coerceIn(0, 255)
                val newG = ((g - minBrightness) * scale).toInt().coerceIn(0, 255)
                val newB = ((b - minBrightness) * scale).toInt().coerceIn(0, 255)
                
                enhancedBitmap.setPixel(x, y, android.graphics.Color.rgb(newR, newG, newB))
            }
        }
        
        Log.d(TAG, "Enhanced contrast: range $range -> 255 (scale: ${String.format("%.2f", scale)})")
        return enhancedBitmap
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
     * Uses ESC * m nL nH d1...dk format with zero line spacing for stripe-free output
     * @param maxWidth Maximum width in pixels to prevent right-side cutoff
     */
    private fun convertBitmapToESCPOS(bitmap: Bitmap, maxWidth: Int, alignment: String?): ByteArray {
        val outputStream = ByteArrayOutputStream()
        // Clamp width to maxWidth to prevent right-side cutoff
        val width = if (bitmap.width > maxWidth) {
            Log.w(TAG, "⚠️ Bitmap width (${bitmap.width}) exceeds maxWidth ($maxWidth), clamping to prevent cutoff")
            maxWidth
        } else {
            bitmap.width
        }
        val height = bitmap.height
        
        // Log actual bitmap dimensions
        Log.d(TAG, "Converting bitmap to ESC/POS: ${bitmap.width}x$height pixels (clamped to: ${width}x$height)")
        
        // Align left for full-width printing (no right-side cutoff)
        // Set alignment: ESC a n where n = 0 (left), 1 (center), 2 (right)
        val alignValue: Byte = when ((alignment ?: "left").lowercase()) {
            "center" -> 1
            "right" -> 2
            else -> 0 // left (default)
        }
        outputStream.write(byteArrayOf(ESC, 'a'.code.toByte(), alignValue))
        
        // Set line spacing to zero - eliminates gaps/stripes between image strips
        // ESC 3 n - Set line spacing to n/180 inch (n=0 for zero spacing)
        outputStream.write(byteArrayOf(ESC, '3'.code.toByte(), 0))
        
        // Process image in 24-dot lines (3 bytes per column)
        var y = 0
        while (y < height) {
            // ESC * m nL nH - Select bit-image mode
            outputStream.write(ESC.toInt())
            outputStream.write('*'.code)
            outputStream.write(33) // 24-dot double-density mode
            
            // Width in pixels (little-endian) - use clamped width, never exceed maxWidth
            val safeWidth = minOf(width, maxWidth, bitmap.width)
            outputStream.write(safeWidth and 0xFF)
            outputStream.write((safeWidth shr 8) and 0xFF)
            
            Log.d(TAG, "Sending ESC/POS image strip: width=$safeWidth (maxWidth=$maxWidth, bitmap.width=${bitmap.width})")
            
            // Process each column (only up to safe width to prevent cutoff)
            for (x in 0 until safeWidth) {
                // Process 24 pixels (3 bytes) in this column
                for (byteIndex in 0..2) {
                    var byteValue = 0
                    for (bit in 0..7) {
                        val pixelY = y + byteIndex * 8 + bit
                        if (pixelY < height) {
                            // Only read pixel if within bitmap bounds
                            val pixel = if (x < bitmap.width) bitmap.getPixel(x, pixelY) else 0xFFFFFF
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
        
        // Restore default line spacing - ESC 2 sets default spacing
        // This ensures text printing after image is not affected
        outputStream.write(byteArrayOf(ESC, '2'.code.toByte()))
        
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


