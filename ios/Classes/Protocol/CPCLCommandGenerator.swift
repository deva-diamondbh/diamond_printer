import Foundation
import UIKit
import os.log

/// CPCL command generator for iOS
class CPCLCommandGenerator: PrinterCommandGenerator {
    
    private let defaultHeight = 400
    
    private enum CPCLImageFormat {
        case eg
        case egCenter
        case graphics
    }
    
    func generateTextCommand(_ text: String) -> Data {
        var data = Data()
        
        // Split text into lines
        let lines = text.components(separatedBy: .newlines)
        
        // Calculate height based on number of lines
        let lineHeight = 20
        let topMargin = 10
        let bottomMargin = 20
        let totalHeight = topMargin + (lines.count * lineHeight) + bottomMargin
        
        // CPCL header
        // ! unit-type print-speed print-density label-height quantity
        data.append("! 0 200 200 \(totalHeight) 1\r\n".data(using: .utf8)!)
        
        // Add each line as a separate TEXT command
        var yPosition = topMargin
        for line in lines {
            if !line.isEmpty {
                // TEXT font rotation x y text
                // Font: 0 = 8pt, 1 = 10pt, 2 = 12pt, 4 = 24pt, 7 = 14pt
                data.append("TEXT 4 0 0 \(yPosition) \(line)\r\n".data(using: .utf8)!)
            }
            yPosition += lineHeight
        }
        
        // Form feed and print
        data.append("FORM\r\n".data(using: .utf8)!)
        data.append("PRINT\r\n".data(using: .utf8)!)
        
        return data
    }
    
    func generateImageCommand(_ image: UIImage, maxWidth: Int) -> Data {
        Logger.methodEntry("CPCL generateImageCommand", category: .commandGeneration)
        Logger.info("Original image size: \(Int(image.size.width))x\(Int(image.size.height)), target width: \(maxWidth)", category: .commandGeneration)
        
        // Validate input
        guard maxWidth > 0 else {
            Logger.error("Invalid maxWidth: \(maxWidth)", category: .commandGeneration)
            Logger.methodExit("CPCL generateImageCommand", success: false)
            return createErrorCommand(message: "Invalid image width")
        }
        
        guard image.size.width > 0 && image.size.height > 0 else {
            Logger.error("Invalid image dimensions: \(image.size)", category: .commandGeneration)
            Logger.methodExit("CPCL generateImageCommand", success: false)
            return createErrorCommand(message: "Invalid image dimensions")
        }
        
        var data = Data()
        
        // Try multiple CPCL formats for compatibility
        var imageData: Data? = nil
        var bitmapHeight = 0
        var usedFormat = "NONE"
        
        // Try EG with CENTER format first (most compatible for many printers)
        Logger.info("Attempting EG with CENTER format...", category: .commandGeneration)
        if let (egCenterData, _, height) = convertImageToCPCL(image, format: .egCenter, targetWidth: maxWidth) {
            imageData = egCenterData
            bitmapHeight = height
            usedFormat = "EG_CENTER"
            Logger.info("✓ SUCCESS - Using EG with CENTER format, bitmap height: \(height), data size: \(egCenterData.count) bytes", category: .commandGeneration)
        } else {
            Logger.error("✗ FAILED - EG with CENTER format", category: .commandGeneration)
            Logger.info("Attempting EG format...", category: .commandGeneration)
            if let (egData, _, height) = convertImageToCPCL(image, format: .eg, targetWidth: maxWidth) {
                imageData = egData
                bitmapHeight = height
                usedFormat = "EG"
                Logger.info("✓ SUCCESS - Using EG format, bitmap height: \(height), data size: \(egData.count) bytes", category: .commandGeneration)
            } else {
                Logger.error("✗ FAILED - EG format", category: .commandGeneration)
                Logger.info("Attempting GRAPHICS format...", category: .commandGeneration)
                if let (graphicsData, _, height) = convertImageToCPCL(image, format: .graphics, targetWidth: maxWidth) {
                    imageData = graphicsData
                    bitmapHeight = height
                    usedFormat = "GRAPHICS"
                    Logger.info("✓ SUCCESS - Using GRAPHICS format, bitmap height: \(height), data size: \(graphicsData.count) bytes", category: .commandGeneration)
                } else {
                    Logger.error("✗ FAILED - GRAPHICS format", category: .commandGeneration)
                    Logger.error("❌ ERROR - All image conversion formats failed!", category: .commandGeneration)
                }
            }
        }
        
        // Calculate label height: bitmap height + margins (top: 10, bottom: 20)
        let labelHeight = bitmapHeight > 0 ? bitmapHeight + 30 : Int(image.size.height) + 30
        Logger.info("Label height calculated: \(labelHeight) (bitmap: \(bitmapHeight) + margins: 30)", category: .commandGeneration)
        
        // Validate label height
        guard labelHeight > 0 && labelHeight < 100000 else {
            Logger.error("Invalid label height: \(labelHeight)", category: .commandGeneration)
            Logger.methodExit("CPCL generateImageCommand", success: false)
            return createErrorCommand(message: "Invalid label height")
        }
        
        // CPCL header
        let header = "! 0 200 200 \(labelHeight) 1\r\n"
        guard let headerData = header.data(using: .utf8) else {
            Logger.error("Failed to encode header", category: .commandGeneration)
            Logger.methodExit("CPCL generateImageCommand", success: false)
            return createErrorCommand(message: "Header encoding failed")
        }
        data.append(headerData)
        Logger.info("Header added: '\(header.trimmingCharacters(in: .whitespacesAndNewlines))' (\(headerData.count) bytes)", category: .commandGeneration)
        
        if let imageData = imageData {
            // Validate image data
            guard imageData.count > 0 else {
                Logger.error("Image data is empty", category: .commandGeneration)
                Logger.methodExit("CPCL generateImageCommand", success: false)
                return createErrorCommand(message: "Image data is empty")
            }
            data.append(imageData)
            Logger.info("Image data appended: \(imageData.count) bytes", category: .commandGeneration)
        } else {
            Logger.error("⚠️ WARNING - No image data, adding error message", category: .commandGeneration)
            let errorText = "TEXT 4 0 10 10 [IMAGE ERROR]\r\n"
            if let errorData = errorText.data(using: .utf8) {
                data.append(errorData)
            }
        }
        
        // Form feed and print
        let formFeed = "FORM\r\n"
        let printCmd = "PRINT\r\n"
        guard let formFeedData = formFeed.data(using: .utf8),
              let printCmdData = printCmd.data(using: .utf8) else {
            Logger.error("Failed to encode footer commands", category: .commandGeneration)
            Logger.methodExit("CPCL generateImageCommand", success: false)
            return createErrorCommand(message: "Footer encoding failed")
        }
        data.append(formFeedData)
        data.append(printCmdData)
        Logger.info("Footer added: FORM + PRINT", category: .commandGeneration)
        
        // Validate final command
        guard data.count > 0 else {
            Logger.error("Final command is empty", category: .commandGeneration)
            Logger.methodExit("CPCL generateImageCommand", success: false)
            return createErrorCommand(message: "Command generation failed")
        }
        
        Logger.info("Final command size: \(data.count) bytes", category: .commandGeneration)
        Logger.info("Command breakdown - Header: \(headerData.count) bytes, Image: \(imageData?.count ?? 0) bytes, Footer: \(formFeedData.count + printCmdData.count) bytes", category: .commandGeneration)
        Logger.info("Format used: \(usedFormat)", category: .commandGeneration)
        Logger.methodExit("CPCL generateImageCommand", success: imageData != nil)
        
        return data
    }
    
    private func createErrorCommand(message: String) -> Data {
        var data = Data()
        let errorLabel = "! 0 200 200 100 1\r\nTEXT 4 0 10 10 \(message)\r\nFORM\r\nPRINT\r\n"
        if let errorData = errorLabel.data(using: .utf8) {
            data.append(errorData)
        }
        return data
    }
    
    
    func generateCutCommand() -> Data {
        return Data() // CPCL doesn't have standard cut command
    }
    
    func generateFeedCommand(lines: Int) -> Data {
        var data = Data()
        
        data.append("! 0 200 200 \(lines * 20) 1\r\n".data(using: .utf8)!)
        data.append("FORM\r\n".data(using: .utf8)!)
        data.append("PRINT\r\n".data(using: .utf8)!)
        
        return data
    }
    
    private func convertImageToCPCL(_ image: UIImage, format: CPCLImageFormat, targetWidth: Int) -> (Data, Int, Int)? {
        let formatName: String
        switch format {
        case .eg: formatName = "EG"
        case .egCenter: formatName = "EG_CENTER"
        case .graphics: formatName = "GRAPHICS"
        }
        
        Logger.methodEntry("convertImageToCPCL (\(formatName))", category: .commandGeneration)
        
        // Validate inputs
        guard targetWidth > 0 else {
            Logger.error("Invalid targetWidth: \(targetWidth)", category: .commandGeneration)
            Logger.methodExit("convertImageToCPCL", success: false)
            return nil
        }
        
        // Calculate target height maintaining aspect ratio
        let aspectRatio = image.size.height / image.size.width
        let targetHeight = Int(CGFloat(targetWidth) * aspectRatio)
        
        Logger.info("Converting image - Original: \(Int(image.size.width))x\(Int(image.size.height)), Target: \(targetWidth)x\(targetHeight)", category: .commandGeneration)
        Logger.debug("Aspect ratio: \(aspectRatio)", category: .commandGeneration)
        
        // Validate target dimensions
        guard targetHeight > 0 && targetHeight < 100000 else {
            Logger.error("Invalid target height: \(targetHeight)", category: .commandGeneration)
            Logger.methodExit("convertImageToCPCL", success: false)
            return nil
        }
        
        // Use optimized image processor with exact target dimensions
        let config = ImageProcessor.Configuration(
            maxWidth: targetWidth,
            maxHeight: targetHeight,
            compressionQuality: 0.8,
            memoryThreshold: 10 * 1024 * 1024
        )
        
        Logger.debug("ImageProcessor config - maxWidth: \(config.maxWidth), maxHeight: \(config.maxHeight), threshold: 140", category: .commandGeneration)
        
        // Convert to monochrome with improved threshold (higher threshold = more white, lower = more black)
        // Using threshold 140 to reduce excessive black printing
        // Force resize to ensure exact dimensions (always resize to targetWidth x targetHeight)
        Logger.info("Calling ImageProcessor.convertToMonochrome...", category: .imageProcessing)
        guard let bitmap = ImageProcessor.convertToMonochrome(image, configuration: config, threshold: 140, forceResize: true) else {
            Logger.error("❌ FAILED - ImageProcessor.convertToMonochrome returned nil", category: .imageProcessing)
            Logger.methodExit("convertImageToCPCL", success: false)
            return nil
        }
        
        Logger.info("✓ ImageProcessor.convertToMonochrome succeeded", category: .imageProcessing)
        
        // Validate bitmap is not empty
        guard !bitmap.isEmpty && !bitmap[0].isEmpty else {
            Logger.error("❌ ERROR - Bitmap is empty after conversion (rows: \(bitmap.count))", category: .imageProcessing)
            Logger.methodExit("convertImageToCPCL", success: false)
            return nil
        }
        
        let bitmapWidth = bitmap[0].count
        let bitmapHeight = bitmap.count
        Logger.info("Bitmap dimensions after conversion: \(bitmapWidth)x\(bitmapHeight), target was: \(targetWidth)x\(targetHeight)", category: .imageProcessing)
        
        // Validate dimensions are reasonable
        guard bitmapWidth > 0 && bitmapHeight > 0 else {
            Logger.error("❌ ERROR - Invalid bitmap dimensions: \(bitmapWidth)x\(bitmapHeight)", category: .imageProcessing)
            Logger.methodExit("convertImageToCPCL", success: false)
            return nil
        }
        
        var data = Data()
        
        // Ensure width matches target width exactly (pad or crop if needed)
        let adjustedBitmap: [[Bool]]
        if bitmapWidth < targetWidth {
            // Pad with white (false) pixels on the right
            Logger.info("Padding bitmap from \(bitmapWidth) to \(targetWidth) pixels", category: .imageProcessing)
            adjustedBitmap = bitmap.map { row in
                var paddedRow = row
                paddedRow.append(contentsOf: Array(repeating: false, count: targetWidth - bitmapWidth))
                return paddedRow
            }
        } else if bitmapWidth > targetWidth {
            // Crop from the right
            Logger.info("Cropping bitmap from \(bitmapWidth) to \(targetWidth) pixels", category: .imageProcessing)
            adjustedBitmap = bitmap.map { Array($0.prefix(targetWidth)) }
        } else {
            adjustedBitmap = bitmap
            Logger.debug("Bitmap width matches target width: \(targetWidth)", category: .imageProcessing)
        }
        
        let finalWidth = adjustedBitmap[0].count
        let finalHeight = adjustedBitmap.count
        let finalBytesPerRow = (finalWidth + 7) / 8
        
        Logger.info("Final bitmap dimensions: \(finalWidth)x\(finalHeight), bytesPerRow: \(finalBytesPerRow)", category: .imageProcessing)
        
        switch format {
        case .eg:
            // EG command with hex encoding
            // Format: EG bytesPerRow height x y <hexdata>
            // Try both formats: hex on same line (more compact) and on separate line (more compatible)
            let hexData = convertBitmapToHex(adjustedBitmap)
            let hexString = String(data: hexData, encoding: .utf8) ?? ""
            
            // Check if hex data is too large - if so, put on separate line for better compatibility
            let commandLine = "EG \(finalBytesPerRow) \(finalHeight) 10 10 "
            let commandWithHex = commandLine + hexString
            
            if commandWithHex.count > 1000 {
                // Large image - put hex data on separate line for better compatibility
                Logger.info("Using separate line format for large image", category: .commandGeneration)
                guard let cmdData = commandLine.data(using: .utf8),
                      let newlineData = "\r\n".data(using: .utf8) else {
                    Logger.error("Failed to encode command line", category: .commandGeneration)
                    Logger.methodExit("convertImageToCPCL", success: false)
                    return nil
                }
                data.append(cmdData)
                data.append(newlineData)
                data.append(hexData)
                data.append(newlineData)
            } else {
                // Small image - keep on same line
                guard let cmdData = commandLine.data(using: .utf8),
                      let newlineData = "\r\n".data(using: .utf8) else {
                    Logger.error("Failed to encode command line", category: .commandGeneration)
                    Logger.methodExit("convertImageToCPCL", success: false)
                    return nil
                }
                data.append(cmdData)
                data.append(hexData)
                data.append(newlineData)
            }
            
        case .egCenter:
            // CENTER command for better positioning
            guard let centerData = "CENTER\r\n".data(using: .utf8) else {
                Logger.error("Failed to encode CENTER command", category: .commandGeneration)
                Logger.methodExit("convertImageToCPCL", success: false)
                return nil
            }
            data.append(centerData)
            let hexData = convertBitmapToHex(adjustedBitmap)
            let commandLine = "EG \(finalBytesPerRow) \(finalHeight) 0 0 "
            let hexString = String(data: hexData, encoding: .utf8) ?? ""
            let commandWithHex = commandLine + hexString
            
            if commandWithHex.count > 1000 {
                // Large image - put hex data on separate line
                Logger.info("Using separate line format for large image with CENTER", category: .commandGeneration)
                guard let cmdData = commandLine.data(using: .utf8),
                      let newlineData = "\r\n".data(using: .utf8) else {
                    Logger.error("Failed to encode command line", category: .commandGeneration)
                    Logger.methodExit("convertImageToCPCL", success: false)
                    return nil
                }
                data.append(cmdData)
                data.append(newlineData)
                data.append(hexData)
                data.append(newlineData)
            } else {
                guard let cmdData = commandLine.data(using: .utf8),
                      let newlineData = "\r\n".data(using: .utf8) else {
                    Logger.error("Failed to encode command line", category: .commandGeneration)
                    Logger.methodExit("convertImageToCPCL", success: false)
                    return nil
                }
                data.append(cmdData)
                data.append(hexData)
                data.append(newlineData)
            }
            
        case .graphics:
            // GRAPHICS command with binary data
            let graphicsCmd = "GRAPHICS \(finalBytesPerRow) \(finalHeight) 0 0\r\n"
            guard let graphicsData = graphicsCmd.data(using: .utf8),
                  let newlineData = "\r\n".data(using: .utf8) else {
                Logger.error("Failed to encode GRAPHICS command", category: .commandGeneration)
                Logger.methodExit("convertImageToCPCL", success: false)
                return nil
            }
            data.append(graphicsData)
            data.append(convertBitmapToBinary(adjustedBitmap))
            data.append(newlineData)
        }
        
        // Validate generated data
        guard data.count > 0 else {
            Logger.error("Generated command data is empty", category: .commandGeneration)
            Logger.methodExit("convertImageToCPCL", success: false)
            return nil
        }
        
        Logger.info("Generated command with image dimensions: \(finalWidth)x\(finalHeight), data size: \(data.count) bytes", category: .commandGeneration)
        Logger.methodExit("convertImageToCPCL", success: true)
        return (data, finalWidth, finalHeight)
    }
    
    private func convertBitmapToHex(_ bitmap: [[Bool]]) -> Data {
        var hexData = Data()
        let width = bitmap[0].count
        let bytesPerRow = (width + 7) / 8
        
        for row in bitmap {
            for byteX in 0..<bytesPerRow {
                var byteValue: UInt8 = 0
                
                for bit in 0..<8 {
                    let x = byteX * 8 + bit
                    if x < width && row[x] {
                        byteValue |= (1 << (7 - bit))
                    }
                }
                
                let hexString = String(format: "%02X", byteValue)
                hexData.append(hexString.data(using: .utf8)!)
            }
        }
        
        return hexData
    }
    
    private func convertBitmapToBinary(_ bitmap: [[Bool]]) -> Data {
        var binaryData = Data()
        let width = bitmap[0].count
        let bytesPerRow = (width + 7) / 8
        
        for row in bitmap {
            for byteX in 0..<bytesPerRow {
                var byteValue: UInt8 = 0
                
                for bit in 0..<8 {
                    let x = byteX * 8 + bit
                    if x < width && row[x] {
                        byteValue |= (1 << (7 - bit))
                    }
                }
                
                binaryData.append(byteValue)
            }
        }
        
        return binaryData
    }
    
}

