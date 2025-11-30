package com.diamond.printer.diamond_printer.protocol

import android.graphics.Bitmap
import android.util.Base64
import java.io.ByteArrayOutputStream

/**
 * ZPL (Zebra Programming Language) command generator
 * Used by Zebra industrial printers
 */
class ZPLCommandGenerator : PrinterCommandGenerator {
    
    companion object {
        private const val DEFAULT_DPI = 203
    }
    
    override fun generateTextCommand(text: String): ByteArray {
        val zpl = StringBuilder()
        
        // Start label
        zpl.append("^XA\n")
        
        // Set label home position
        zpl.append("^LH0,0\n")
        
        // Field origin and text
        zpl.append("^FO50,50\n")
        zpl.append("^A0N,30,30\n") // Font, rotation, height, width
        zpl.append("^FD$text^FS\n")
        
        // End label
        zpl.append("^XZ\n")
        
        return zpl.toString().toByteArray()
    }
    
    override fun generateImageCommand(bitmap: Bitmap, maxWidth: Int): ByteArray {
        val zpl = StringBuilder()
        
        // Start label
        zpl.append("^XA\n")
        
        // Convert bitmap to ZPL graphic field
        val graphicField = convertBitmapToZPL(bitmap)
        zpl.append(graphicField)
        
        // End label
        zpl.append("^XZ\n")
        
        return zpl.toString().toByteArray()
    }
    
    override fun generateCutCommand(): ByteArray {
        // ZPL doesn't have a cut command for most printers
        // Return empty array
        return ByteArray(0)
    }
    
    override fun generateFeedCommand(lines: Int): ByteArray {
        // Generate blank label for feeding
        val zpl = StringBuilder()
        zpl.append("^XA\n")
        zpl.append("^FO0,0^GB812,${lines * 20},0^FS\n") // Blank box
        zpl.append("^XZ\n")
        
        return zpl.toString().toByteArray()
    }
    
    /**
     * Convert bitmap to ZPL graphic field format
     * Uses ^GFA (Graphic Field ASCII) command
     */
    private fun convertBitmapToZPL(bitmap: Bitmap): String {
        val width = bitmap.width
        val height = bitmap.height
        
        // Convert to monochrome
        val pixels = convertToMonochrome(bitmap)
        
        // Calculate bytes per row (width must be multiple of 8)
        val bytesPerRow = (width + 7) / 8
        val totalBytes = bytesPerRow * height
        
        // Build hex string from pixels
        val hexData = StringBuilder()
        
        for (y in 0 until height) {
            var byteValue = 0
            var bitPosition = 7
            
            for (x in 0 until width) {
                if (pixels[y * width + x]) {
                    byteValue = byteValue or (1 shl bitPosition)
                }
                
                bitPosition--
                if (bitPosition < 0 || x == width - 1) {
                    hexData.append(String.format("%02X", byteValue))
                    byteValue = 0
                    bitPosition = 7
                }
            }
        }
        
        // Compress hex data (simple run-length encoding)
        val compressedData = compressZPLData(hexData.toString())
        
        // Build ZPL graphic field command
        val zpl = StringBuilder()
        zpl.append("^FO50,50\n") // Field origin
        zpl.append("^GFA,")
        zpl.append("$totalBytes,") // Total bytes
        zpl.append("$totalBytes,") // Bytes per row * rows
        zpl.append("$bytesPerRow,") // Bytes per row
        zpl.append("$compressedData^FS\n")
        
        return zpl.toString()
    }
    
    /**
     * Convert bitmap to monochrome boolean array
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
    
    /**
     * Simple run-length compression for ZPL hex data
     * Reduces data size by encoding repeated characters
     */
    private fun compressZPLData(hexString: String): String {
        if (hexString.isEmpty()) return hexString
        
        val result = StringBuilder()
        var count = 1
        var currentChar = hexString[0]
        
        for (i in 1 until hexString.length) {
            if (hexString[i] == currentChar && count < 400) {
                count++
            } else {
                // Append compressed segment
                if (count > 2) {
                    result.append(String.format("%c%02X", currentChar, count))
                } else {
                    result.append(currentChar.toString().repeat(count))
                }
                
                currentChar = hexString[i]
                count = 1
            }
        }
        
        // Append last segment
        if (count > 2) {
            result.append(String.format("%c%02X", currentChar, count))
        } else {
            result.append(currentChar.toString().repeat(count))
        }
        
        return result.toString()
    }
}

