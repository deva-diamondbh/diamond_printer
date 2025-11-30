import Foundation
import UIKit

/// ESC/POS printer command generator for iOS
class ESCPOSCommandGenerator: PrinterCommandGenerator {
    
    // ESC/POS Commands
    private let ESC: UInt8 = 0x1B
    private let GS: UInt8 = 0x1D
    private let LF: UInt8 = 0x0A
    private let CR: UInt8 = 0x0D
    
    func generateTextCommand(_ text: String) -> Data {
        var data = Data()
        
        // Initialize printer
        data.append(contentsOf: [ESC, 0x40]) // ESC @
        
        // Add text
        if let textData = text.data(using: .utf8) {
            data.append(textData)
        }
        
        // Line feed
        data.append(LF)
        
        return data
    }
    
    func generateImageCommand(_ image: UIImage, maxWidth: Int) -> Data {
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
        
        // Generate ESC/POS image data
        let imageData = convertBitmapToESCPOS(bitmap)
        data.append(imageData)
        
        // Line feed
        data.append(generateFeedCommand(lines: 3))
        
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
    
    
    /// Convert bitmap to ESC/POS format
    private func convertBitmapToESCPOS(_ bitmap: [[Bool]]) -> Data {
        var data = Data()
        
        let height = bitmap.count
        guard height > 0 else { return data }
        let width = bitmap[0].count
        
        // Center alignment
        data.append(contentsOf: [ESC, 0x61, 1]) // ESC a 1
        
        var y = 0
        while y < height {
            // ESC * m nL nH - Select bit-image mode
            data.append(ESC)
            data.append(0x2A) // *
            data.append(33) // 24-dot double-density mode
            
            // Width (little-endian)
            data.append(UInt8(width & 0xFF))
            data.append(UInt8((width >> 8) & 0xFF))
            
            // Process each column
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
        
        // Left alignment
        data.append(contentsOf: [ESC, 0x61, 0]) // ESC a 0
        
        return data
    }
}

