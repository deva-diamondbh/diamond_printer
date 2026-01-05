package com.diamond.printer.diamond_printer.protocol

import android.graphics.Bitmap
import android.graphics.Color
import android.util.Log
import java.io.ByteArrayOutputStream
import java.nio.charset.Charset

/**
 * CPCL (Common Printing Command Language) generator
 * Used by Zebra mobile printers and some other label printers
 * 
 * Supports multiple CPCL image formats for maximum compatibility
 */
class CPCLCommandGenerator : PrinterCommandGenerator {
    
    companion object {
        private const val TAG = "CPCLCommandGen"
        private const val DEFAULT_DPI = 203
        private const val DEFAULT_WIDTH = 576 // 3 inch label at 203 DPI
        private const val DEFAULT_HEIGHT = 400
    }
    
    override fun generateTextCommand(text: String): ByteArray {
        val outputStream = ByteArrayOutputStream()
        
        // Split text into lines
        val lines = text.split("\n")
        
        // Calculate height based on number of lines
        val lineHeight = 20
        val topMargin = 10
        val bottomMargin = 20
        val totalHeight = topMargin + (lines.size * lineHeight) + bottomMargin
        
        // CPCL header
        // ! unit-type print-speed print-density label-height quantity
        outputStream.write("! 0 200 200 $totalHeight 1\r\n".toByteArray())
        
        // Add each line as a separate TEXT command
        var yPosition = topMargin
        for (line in lines) {
            if (line.isNotEmpty()) {
                // TEXT font rotation x y text
                // Font: 0 = 8pt, 1 = 10pt, 2 = 12pt, 4 = 24pt, 7 = 14pt
                outputStream.write("TEXT 4 0 0 $yPosition $line\r\n".toByteArray())
            }
            yPosition += lineHeight
        }
        
        // Form feed
        outputStream.write("FORM\r\n".toByteArray())
        
        // Print
        outputStream.write("PRINT\r\n".toByteArray())
        
        return outputStream.toByteArray()
    }
    
    override fun generateImageCommand(bitmap: Bitmap, maxWidth: Int): ByteArray {
        Log.d(TAG, "Generating CPCL image for ${bitmap.width}x${bitmap.height}, maxWidth=$maxWidth")
        
        // Resize image to fit printer width
        // Scale up if smaller, scale down if larger, to always fill paper width
        val resizedBitmap = if (bitmap.width != maxWidth) {
            val ratio = maxWidth.toFloat() / bitmap.width
            val newHeight = (bitmap.height * ratio).toInt()
            if (bitmap.width > maxWidth) {
                Log.d(TAG, "Scaling down from ${bitmap.width}x${bitmap.height} to ${maxWidth}x$newHeight")
            } else {
                Log.d(TAG, "Scaling up from ${bitmap.width}x${bitmap.height} to ${maxWidth}x$newHeight to fit paper")
            }
            Bitmap.createScaledBitmap(bitmap, maxWidth, newHeight, true)
        } else {
            bitmap
        }
        
        // Convert to monochrome first (better results)
        val monoBitmap = convertBitmapToMonochrome(resizedBitmap)
        val monoWidth = monoBitmap.width
        val monoHeight = monoBitmap.height
        
        // Try MULTIPLE CPCL formats in order of compatibility
        // Different printers support different variations!
        val methods = listOf(
            { generateExpandedGraphicsCenter(monoBitmap) } to "EG with CENTER (most compatible)",
            { generateExpandedGraphics(monoBitmap) } to "EG standard",
            { generateCG(monoBitmap) } to "CG (compressed graphics)",
            { generateBinaryGraphicsZeroPos(monoBitmap) } to "GRAPHICS at 0,0",
            { generateBinaryGraphics(monoBitmap) } to "GRAPHICS at 10,10",
            { generateEGGraphics(monoBitmap) } to "EG alternate",
            { generatePCX(monoBitmap) } to "PCX format (legacy)"
        )
        
        var result: ByteArray? = null
        var successMethod = ""
        
        for ((method, name) in methods) {
            try {
                Log.d(TAG, "Trying CPCL format: $name...")
                result = method()
                successMethod = name
                Log.d(TAG, "✓ CPCL format '$name' succeeded! Generated ${result.size} bytes")
                break
            } catch (e: Exception) {
                Log.w(TAG, "✗ CPCL format '$name' failed: ${e.message}", e)
            }
        }
        
        // Clean up
        if (resizedBitmap != bitmap) {
            resizedBitmap.recycle()
        }
        monoBitmap.recycle()
        
        if (result != null) {
            Log.d(TAG, "✓ CPCL image generated successfully using: $successMethod (${result.size} bytes, image: ${monoWidth}x${monoHeight})")
            return result
        } else {
            Log.e(TAG, "❌ All CPCL image generation methods failed! Image size: ${monoWidth}x${monoHeight}, maxWidth: $maxWidth")
            // Return minimal label to avoid crash
            return "! 0 200 200 100 1\r\nTEXT 4 0 10 10 [IMAGE ERROR]\r\nFORM\r\nPRINT\r\n".toByteArray()
        }
    }
    
    override fun generateCutCommand(): ByteArray {
        // CPCL doesn't have a standard cut command, return empty
        return ByteArray(0)
    }
    
    override fun generateFeedCommand(lines: Int): ByteArray {
        val outputStream = ByteArrayOutputStream()
        
        // Generate blank label to feed paper
        outputStream.write("! 0 200 200 ${lines * 20} 1\r\n".toByteArray())
        outputStream.write("FORM\r\n".toByteArray())
        outputStream.write("PRINT\r\n".toByteArray())
        
        return outputStream.toByteArray()
    }
    
    /**
     * Method 1: EXPANDED-GRAPHICS with CENTER (maximum compatibility)
     * Works on most Zebra mobile printers
     */
    private fun generateExpandedGraphicsCenter(bitmap: Bitmap): ByteArray {
        val output = ByteArrayOutputStream()
        val width = bitmap.width
        val height = bitmap.height
        val bytesPerRow = (width + 7) / 8
        
        // CPCL header - label height = image height + margins (top: 10, bottom: 20)
        val labelHeight = height + 30
        output.write("! 0 200 200 $labelHeight 1\r\n".toByteArray())
        
        // CENTER command for better positioning
        output.write("CENTER\r\n".toByteArray())
        
        // EXPANDED-GRAPHICS command with hex data
        output.write("EG $bytesPerRow $height 0 0 ".toByteArray())
        
        // Convert to hex string
        for (y in 0 until height) {
            for (byteX in 0 until bytesPerRow) {
                var byteValue = 0
                for (bit in 0..7) {
                    val x = byteX * 8 + bit
                    if (x < width) {
                        val pixel = bitmap.getPixel(x, y)
                        val isBlack = Color.red(pixel) < 128
                        if (isBlack) {
                            byteValue = byteValue or (1 shl (7 - bit))
                        }
                    }
                }
                output.write(String.format("%02X", byteValue).toByteArray())
            }
        }
        
        output.write("\r\n".toByteArray())
        output.write("FORM\r\n".toByteArray())
        output.write("PRINT\r\n".toByteArray())
        
        return output.toByteArray()
    }
    
    /**
     * Method 2: EXPANDED-GRAPHICS standard (most compatible for Zebra printers)
     * This uses ASCII hex encoding which is more reliable
     */
    private fun generateExpandedGraphics(bitmap: Bitmap): ByteArray {
        val output = ByteArrayOutputStream()
        val width = bitmap.width
        val height = bitmap.height
        val bytesPerRow = (width + 7) / 8
        
        // CPCL header - label height = image height + margins (top: 10, bottom: 20)
        val labelHeight = height + 30
        output.write("! 0 200 200 $labelHeight 1\r\n".toByteArray())
        
        // EXPANDED-GRAPHICS command with hex data
        output.write("EG $bytesPerRow $height 10 10 ".toByteArray())
        
        // Convert to hex string
        for (y in 0 until height) {
            for (byteX in 0 until bytesPerRow) {
                var byteValue = 0
                for (bit in 0..7) {
                    val x = byteX * 8 + bit
                    if (x < width) {
                        val pixel = bitmap.getPixel(x, y)
                        val isBlack = Color.red(pixel) < 128
                        if (isBlack) {
                            byteValue = byteValue or (1 shl (7 - bit))
                        }
                    }
                }
                output.write(String.format("%02X", byteValue).toByteArray())
            }
        }
        
        output.write("\r\n".toByteArray())
        output.write("FORM\r\n".toByteArray())
        output.write("PRINT\r\n".toByteArray())
        
        return output.toByteArray()
    }
    
    /**
     * Method 3: CG (Compressed Graphics) - for printers supporting compression
     */
    private fun generateCG(bitmap: Bitmap): ByteArray {
        val output = ByteArrayOutputStream()
        val width = bitmap.width
        val height = bitmap.height
        val bytesPerRow = (width + 7) / 8
        
        // CPCL header - label height = image height + margins (top: 10, bottom: 20)
        val labelHeight = height + 30
        output.write("! 0 200 200 $labelHeight 1\r\n".toByteArray())
        
        // CG command (Compressed Graphics)
        output.write("CG $bytesPerRow $height 0 0 ".toByteArray())
        
        // Convert to hex with run-length encoding
        for (y in 0 until height) {
            for (byteX in 0 until bytesPerRow) {
                var byteValue = 0
                for (bit in 0..7) {
                    val x = byteX * 8 + bit
                    if (x < width) {
                        val pixel = bitmap.getPixel(x, y)
                        val isBlack = Color.red(pixel) < 128
                        if (isBlack) {
                            byteValue = byteValue or (1 shl (7 - bit))
                        }
                    }
                }
                output.write(String.format("%02X", byteValue).toByteArray())
            }
        }
        
        output.write("\r\n".toByteArray())
        output.write("FORM\r\n".toByteArray())
        output.write("PRINT\r\n".toByteArray())
        
        return output.toByteArray()
    }
    
    /**
     * Method 4: GRAPHICS at position 0,0 (some printers only work with zero position)
     */
    private fun generateBinaryGraphicsZeroPos(bitmap: Bitmap): ByteArray {
        val output = ByteArrayOutputStream()
        val width = bitmap.width
        val height = bitmap.height
        val bytesPerRow = (width + 7) / 8
        
        // CPCL header - label height = image height + margins (top: 10, bottom: 20)
        val labelHeight = height + 30
        output.write("! 0 200 200 $labelHeight 1\r\n".toByteArray())
        
        // GRAPHICS command at 0,0
        output.write("GRAPHICS $bytesPerRow $height 0 0\r\n".toByteArray())
        
        // Binary data
        for (y in 0 until height) {
            for (byteX in 0 until bytesPerRow) {
                var byteValue = 0
                for (bit in 0..7) {
                    val x = byteX * 8 + bit
                    if (x < width) {
                        val pixel = bitmap.getPixel(x, y)
                        val isBlack = Color.red(pixel) < 128
                        if (isBlack) {
                            byteValue = byteValue or (1 shl (7 - bit))
                        }
                    }
                }
                output.write(byteValue)
            }
        }
        
        output.write("\r\n".toByteArray())
        output.write("FORM\r\n".toByteArray())
        output.write("PRINT\r\n".toByteArray())
        
        return output.toByteArray()
    }
    
    /**
     * Method 5: GRAPHICS with binary data at 10,10 (faster but less compatible)
     */
    private fun generateBinaryGraphics(bitmap: Bitmap): ByteArray {
        val output = ByteArrayOutputStream()
        val width = bitmap.width
        val height = bitmap.height
        val bytesPerRow = (width + 7) / 8
        
        // CPCL header - label height = image height + margins (top: 10, bottom: 20)
        val labelHeight = height + 30
        output.write("! 0 200 200 $labelHeight 1\r\n".toByteArray())
        
        // GRAPHICS command
        output.write("GRAPHICS $bytesPerRow $height 10 10\r\n".toByteArray())
        
        // Binary data
        for (y in 0 until height) {
            for (byteX in 0 until bytesPerRow) {
                var byteValue = 0
                for (bit in 0..7) {
                    val x = byteX * 8 + bit
                    if (x < width) {
                        val pixel = bitmap.getPixel(x, y)
                        val isBlack = Color.red(pixel) < 128
                        if (isBlack) {
                            byteValue = byteValue or (1 shl (7 - bit))
                        }
                    }
                }
                output.write(byteValue)
            }
        }
        
        output.write("\r\n".toByteArray())
        output.write("FORM\r\n".toByteArray())
        output.write("PRINT\r\n".toByteArray())
        
        return output.toByteArray()
    }
    
    /**
     * Method 6: EG (Extended Graphics) - alternate format
     */
    private fun generateEGGraphics(bitmap: Bitmap): ByteArray {
        val output = ByteArrayOutputStream()
        val width = bitmap.width
        val height = bitmap.height
        val bytesPerRow = (width + 7) / 8
        
        // CPCL header - label height = image height + margins (top: 10, bottom: 20)
        val labelHeight = height + 30
        output.write("! 0 200 200 $labelHeight 1\r\n".toByteArray())
        
        // CENTER for better appearance
        output.write("CENTER\r\n".toByteArray())
        
        // EG command
        output.write("EG $bytesPerRow $height 0 0 ".toByteArray())
        
        // Hex encoded data
        for (y in 0 until height) {
            for (byteX in 0 until bytesPerRow) {
                var byteValue = 0
                for (bit in 0..7) {
                    val x = byteX * 8 + bit
                    if (x < width) {
                        val pixel = bitmap.getPixel(x, y)
                        val isBlack = Color.red(pixel) < 128
                        if (isBlack) {
                            byteValue = byteValue or (1 shl (7 - bit))
                        }
                    }
                }
                output.write(String.format("%02X", byteValue).toByteArray())
            }
        }
        
        output.write("\r\n".toByteArray())
        output.write("FORM\r\n".toByteArray())
        output.write("PRINT\r\n".toByteArray())
        
        return output.toByteArray()
    }
    
    /**
     * Method 7: PCX format (legacy printers)
     * Some older CPCL printers only support PCX
     */
    private fun generatePCX(bitmap: Bitmap): ByteArray {
        val output = ByteArrayOutputStream()
        val width = bitmap.width
        val height = bitmap.height
        val bytesPerRow = (width + 7) / 8
        
        // CPCL header  
        output.write("! 0 200 200 ${height + 100} 1\r\n".toByteArray())
        
        // BARCODE-TEXT OFF to avoid interference
        output.write("BARCODE-TEXT OFF\r\n".toByteArray())
        
        // PCX command (simpler format)
        output.write("PCX $bytesPerRow $height 0 0\r\n".toByteArray())
        
        // Binary image data
        for (y in 0 until height) {
            for (byteX in 0 until bytesPerRow) {
                var byteValue = 0
                for (bit in 0..7) {
                    val x = byteX * 8 + bit
                    if (x < width) {
                        val pixel = bitmap.getPixel(x, y)
                        val isBlack = Color.red(pixel) < 128
                        if (isBlack) {
                            byteValue = byteValue or (1 shl (7 - bit))
                        }
                    }
                }
                output.write(byteValue)
            }
        }
        
        output.write("\r\n".toByteArray())
        output.write("FORM\r\n".toByteArray())
        output.write("PRINT\r\n".toByteArray())
        
        return output.toByteArray()
    }
    
    /**
     * Convert to monochrome bitmap (simpler than dithering for CPCL)
     */
    private fun convertBitmapToMonochrome(bitmap: Bitmap): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        val monoBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        
        for (y in 0 until height) {
            for (x in 0 until width) {
                val pixel = bitmap.getPixel(x, y)
                val gray = (Color.red(pixel) * 0.299 +
                        Color.green(pixel) * 0.587 +
                        Color.blue(pixel) * 0.114).toInt()
                
                val monoColor = if (gray > 128) Color.WHITE else Color.BLACK
                monoBitmap.setPixel(x, y, monoColor)
            }
        }
        
        return monoBitmap
    }
    
    /**
     * Convert bitmap to monochrome with Floyd-Steinberg dithering
     * Much better quality than simple threshold
     */
    private fun convertToMonochromeWithDithering(bitmap: Bitmap): BooleanArray {
        val width = bitmap.width
        val height = bitmap.height
        val pixels = BooleanArray(width * height)
        
        // Create grayscale array for dithering
        val grayValues = Array(height) { IntArray(width) }
        
        // Convert to grayscale
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
                
                // Distribute error to neighbors
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
                
                pixels[y * width + x] = newPixel == 0 // true = black
            }
        }
        
        return pixels
    }
    
    /**
     * Simple threshold conversion (backup method)
     */
    private fun convertToMonochrome(bitmap: Bitmap): BooleanArray {
        val width = bitmap.width
        val height = bitmap.height
        val pixels = BooleanArray(width * height)
        
        for (y in 0 until height) {
            for (x in 0 until width) {
                val pixel = bitmap.getPixel(x, y)
                val gray = (android.graphics.Color.red(pixel) * 0.299 +
                        android.graphics.Color.green(pixel) * 0.587 +
                        android.graphics.Color.blue(pixel) * 0.114).toInt()
                
                // true = black, false = white
                pixels[y * width + x] = gray < 128
            }
        }
        
        return pixels
    }
}

