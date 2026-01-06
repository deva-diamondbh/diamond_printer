import Foundation
import UIKit

/// ESC/POS printer command generator for iOS
/// Optimized for high-quality thermal printer output
class ESCPOSCommandGenerator: PrinterCommandGenerator {
    
    // ESC/POS Commands
    private let ESC: UInt8 = 0x1B
    private let GS: UInt8 = 0x1D
    private let LF: UInt8 = 0x0A
    private let CR: UInt8 = 0x0D
    
    func generateTextCommand(_ text: String, alignment: String?) -> Data {
        var data = Data()
        
        // Initialize printer
        data.append(contentsOf: [ESC, 0x40]) // ESC @
        
        // Set proper character encoding for international characters
        // ESC t n - Select character code table (n=28 for UTF-8)
        data.append(contentsOf: [ESC, 0x74, 28])
        
        // Set alignment: ESC a n where n = 0 (left), 1 (center), 2 (right)
        let alignValue: UInt8
        let alignStr = (alignment ?? "left").lowercased()
        if alignStr == "center" {
            alignValue = 1
        } else if alignStr == "right" {
            alignValue = 2
        } else {
            alignValue = 0 // left (default)
        }
        data.append(contentsOf: [ESC, 0x61, alignValue]) // ESC a n
        
        // Set optimal line spacing for text readability (30/180 inch)
        data.append(contentsOf: [ESC, 0x33, 30]) // ESC 3 30
        
        // Add text
        if let textData = text.data(using: .utf8) {
            data.append(textData)
        }
        
        // Line feed
        data.append(LF)
        
        // Restore default line spacing
        data.append(contentsOf: [ESC, 0x32]) // ESC 2
        
        // Reset to left alignment
        data.append(contentsOf: [ESC, 0x61, 0]) // ESC a 0
        
        return data
    }
    
    func generateImageCommand(_ image: UIImage, maxWidth: Int, alignment: String?) -> Data {
        var data = Data()
        
        // Initialize printer
        data.append(contentsOf: [ESC, 0x40]) // ESC @
        
        // Resize image if needed
        let resizedImage = ImageProcessor.resizeImage(image, maxWidth: maxWidth, maxHeight: 4096)
        
        // Convert image to monochrome bitmap using optimized processor
        let config = ImageProcessor.Configuration(
            maxWidth: maxWidth,
            maxHeight: 4096,
            compressionQuality: 0.8,
            memoryThreshold: 10 * 1024 * 1024
        )
        guard let bitmap = ImageProcessor.convertToMonochrome(resizedImage, configuration: config) else {
            return data
        }
        
        // Generate ESC/POS image data - pass maxWidth and alignment
        let imageData = convertBitmapToESCPOS(bitmap, maxWidth: maxWidth, alignment: alignment)
        data.append(imageData)
        
        // Single line feed to minimize bottom space
        data.append(generateFeedCommand(lines: 1))
        
        return data
    }
    
    func generateCutCommand() -> Data {
        var data = Data()
        data.append(contentsOf: [GS, 0x56, 1]) // GS V 1 - Cut paper
        return data
    }
    
    func generateFeedCommand(lines: Int) -> Data {
        var data = Data()
        for _ in 0..<lines {
            data.append(LF)
        }
        return data
    }
    
    
    /// Convert bitmap to ESC/POS format with zero line spacing for stripe-free output
    /// @param maxWidth Maximum width in pixels to prevent right-side cutoff
    /// @param alignment Text alignment: "left", "center", or "right"
    private func convertBitmapToESCPOS(_ bitmap: [[Bool]], maxWidth: Int, alignment: String?) -> Data {
        var data = Data()
        
        let height = bitmap.count
        guard height > 0 else { return data }
        let bitmapWidth = bitmap[0].count
        
        // Clamp width to maxWidth to prevent right-side cutoff
        let width = min(bitmapWidth, maxWidth)
        
        Logger.info("Converting bitmap to ESC/POS: \(bitmapWidth)x\(height) pixels (clamped to: \(width)x\(height))", category: .commandGeneration)
        
        // Set alignment: ESC a n where n = 0 (left), 1 (center), 2 (right)
        let alignValue: UInt8
        let alignStr = (alignment ?? "left").lowercased()
        if alignStr == "center" {
            alignValue = 1
        } else if alignStr == "right" {
            alignValue = 2
        } else {
            alignValue = 0 // left (default)
        }
        data.append(contentsOf: [ESC, 0x61, alignValue]) // ESC a n
        
        // Set line spacing to zero - eliminates gaps/stripes between image strips
        // ESC 3 n - Set line spacing to n/180 inch (n=0 for zero spacing)
        data.append(contentsOf: [ESC, 0x33, 0]) // ESC 3 0
        
        var y = 0
        while y < height {
            // ESC * m nL nH - Select bit-image mode
            data.append(ESC)
            data.append(0x2A) // *
            data.append(33) // 24-dot double-density mode
            
            // Width (little-endian) - use clamped width
            data.append(UInt8(width & 0xFF))
            data.append(UInt8((width >> 8) & 0xFF))
            
            // Process each column (only up to clamped width to prevent cutoff)
            for x in 0..<width {
                // Process 24 pixels (3 bytes) in this column
                for byteIndex in 0...2 {
                    var byteValue: UInt8 = 0
                    for bit in 0...7 {
                        let pixelY = y + byteIndex * 8 + bit
                        if pixelY < height && bitmap[pixelY][x] {
                            byteValue |= (1 << (7 - bit))
                        }
                    }
                    data.append(byteValue)
                }
            }
            
            data.append(LF)
            y += 24
        }
        
        // Restore default line spacing - ESC 2 sets default spacing
        // This ensures text printing after image is not affected
        data.append(contentsOf: [ESC, 0x32]) // ESC 2
        
        // Reset to left alignment
        data.append(contentsOf: [ESC, 0x61, 0]) // ESC a 0
        
        return data
    }
}

