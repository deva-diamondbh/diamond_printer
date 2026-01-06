import Foundation
import UIKit

/// ZPL command generator for iOS
class ZPLCommandGenerator: PrinterCommandGenerator {
    
    func generateTextCommand(_ text: String, alignment: String?) -> Data {
        var zpl = ""
        
        // Start label
        zpl += "^XA\n"
        
        // Set label home position
        zpl += "^LH0,0\n"
        
        // Determine alignment and calculate x position
        // Use dynamic width based on maxWidth for full-width printing
        let labelWidth = 812 // Default, but will use maxWidth for images
        let alignStr = (alignment ?? "left").lowercased()
        
        // Estimate text width (approximately 6 dots per character)
        let estimatedTextWidth = text.count * 6
        let xPosition: Int
        
        if alignStr == "center" {
            xPosition = max(0, (labelWidth - estimatedTextWidth) / 2)
        } else if alignStr == "right" {
            xPosition = max(0, labelWidth - estimatedTextWidth - 10) // 10 dot margin
        } else {
            xPosition = 0 // left (default) - use 0 for full-width printing
        }
        
        // Field origin (y position = 0 for full-width printing)
        zpl += "^FO\(xPosition),0\n"
        
        // Field block for text wrapping and alignment
        // ^FBwidth,height,spacing,alignment,0
        let alignmentCode = alignStr == "center" ? "C" : (alignStr == "right" ? "R" : "L")
        zpl += "^FB\(labelWidth - xPosition),1,0,\(alignmentCode),0\n"
        
        // Font and text
        zpl += "^A0N,30,30\n"
        zpl += "^FD\(text)^FS\n"
        
        // End label
        zpl += "^XZ\n"
        
        return zpl.data(using: .utf8) ?? Data()
    }
    
    func generateImageCommand(_ image: UIImage, maxWidth: Int, alignment: String?) -> Data {
        var zpl = ""
        
        // Start label
        zpl += "^XA\n"
        
        // Resize image if needed
        let resizedImage = ImageProcessor.resizeImage(image, maxWidth: maxWidth, maxHeight: 4096)
        
        // Convert image to ZPL graphic field with alignment
        if let graphicField = convertImageToZPL(resizedImage, maxWidth: maxWidth, alignment: alignment) {
            zpl += graphicField
        }
        
        // End label
        zpl += "^XZ\n"
        
        return zpl.data(using: .utf8) ?? Data()
    }
    
    func generateCutCommand() -> Data {
        return Data() // ZPL doesn't have standard cut command
    }
    
    func generateFeedCommand(lines: Int) -> Data {
        var zpl = ""
        
        zpl += "^XA\n"
        zpl += "^FO0,0^GB812,\(lines * 20),0^FS\n"
        zpl += "^XZ\n"
        
        return zpl.data(using: .utf8) ?? Data()
    }
    
    private func convertImageToZPL(_ image: UIImage, maxWidth: Int, alignment: String?) -> String? {
        // Use optimized image processor
        let config = ImageProcessor.Configuration(
            maxWidth: Int(image.size.width),
            maxHeight: Int(image.size.height),
            compressionQuality: 0.8,
            memoryThreshold: 10 * 1024 * 1024
        )
        guard let bitmap = ImageProcessor.convertToMonochrome(image, configuration: config) else { return nil }
        
        let width = bitmap[0].count
        let height = bitmap.count
        let bytesPerRow = (width + 7) / 8
        let totalBytes = bytesPerRow * height
        
        // Build hex string
        var hexString = ""
        
        for row in bitmap {
            var byteValue: UInt8 = 0
            var bitPosition = 7
            
            for (index, pixel) in row.enumerated() {
                if pixel {
                    byteValue |= (1 << bitPosition)
                }
                
                bitPosition -= 1
                if bitPosition < 0 || index == row.count - 1 {
                    hexString += String(format: "%02X", byteValue)
                    byteValue = 0
                    bitPosition = 7
                }
            }
        }
        
        // Compress hex data
        let compressed = compressZPLData(hexString)
        
        // Calculate x position based on alignment - always use LEFT (0) for full-width printing
        // Use maxWidth instead of hardcoded labelWidth for dynamic paper sizes
        let labelWidth = maxWidth
        let alignStr = (alignment ?? "left").lowercased()
        let xPosition: Int
        
        if alignStr == "center" {
            xPosition = max(0, (labelWidth - width) / 2)
        } else if alignStr == "right" {
            xPosition = max(0, labelWidth - width - 10) // 10 dot margin
        } else {
            xPosition = 0 // left (default) - use 0 for full-width printing
        }
        
        // Build ZPL graphic field
        var zpl = ""
        zpl += "^FO\(xPosition),0\n" // Field origin (y = 0 for full-width)
        zpl += "^GFA,"
        zpl += "\(totalBytes),"
        zpl += "\(totalBytes),"
        zpl += "\(bytesPerRow),"
        zpl += compressed
        zpl += "^FS\n"
        
        return zpl
    }
    
    
    private func compressZPLData(_ hexString: String) -> String {
        guard !hexString.isEmpty else { return hexString }
        
        var result = ""
        var i = 0
        let chars = Array(hexString)
        
        while i < chars.count {
            let currentChar = chars[i]
            var count = 1
            
            // Count consecutive identical characters (max 400 for ZPL)
            while i + count < chars.count && chars[i + count] == currentChar && count < 400 {
                count += 1
            }
            
            // ZPL compression: if count > 2, use compression format: char + hex count
            // Otherwise, just repeat the character
            if count > 2 {
                // Format: character followed by 2-digit hex count
                let hexCount = String(format: "%02X", count)
                result += String(currentChar) + hexCount
            } else {
                // Just repeat the character
                result += String(repeating: currentChar, count: count)
            }
            
            i += count
        }
        
        return result
    }
}

