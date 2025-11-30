import Foundation
import UIKit
import os.log

/// Utility for memory-efficient image processing
class ImageProcessor {
    
    /// Configuration for image processing
    struct Configuration {
        let maxWidth: Int
        let maxHeight: Int
        let compressionQuality: CGFloat
        let memoryThreshold: Int // Bytes threshold for using memory-efficient processing
        
        static let `default` = Configuration(
            maxWidth: 2048,
            maxHeight: 2048,
            compressionQuality: 0.8,
            memoryThreshold: 10 * 1024 * 1024 // 10MB
        )
    }
    
    /// Resize image to fit within max dimensions while maintaining aspect ratio
    static func resizeImage(_ image: UIImage, maxWidth: Int, maxHeight: Int) -> UIImage {
        let size = image.size
        
        // If image is smaller than max dimensions, return original
        if size.width <= CGFloat(maxWidth) && size.height <= CGFloat(maxHeight) {
            return image
        }
        
        // Calculate new size maintaining aspect ratio
        let widthRatio = CGFloat(maxWidth) / size.width
        let heightRatio = CGFloat(maxHeight) / size.height
        let ratio = min(widthRatio, heightRatio)
        
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        
        // Use autoreleasepool for memory management
        return autoreleasepool {
            let renderer = UIGraphicsImageRenderer(size: newSize)
            return renderer.image { context in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
    }
    
    /// Convert image to monochrome bitmap with memory-efficient processing
    /// - Parameter threshold: Grayscale threshold (0-255). Higher values = more white pixels, lower = more black pixels. Default: 128
    /// - Parameter forceResize: If true, always resize to exact maxWidth/maxHeight even if image is smaller
    static func convertToMonochrome(_ image: UIImage, configuration: Configuration = .default, threshold: Int = 128, forceResize: Bool = false) -> [[Bool]]? {
        Logger.methodEntry("ImageProcessor.convertToMonochrome", category: .imageProcessing)
        Logger.info("Input image size: \(Int(image.size.width))x\(Int(image.size.height))", category: .imageProcessing)
        Logger.info("Target dimensions: \(configuration.maxWidth)x\(configuration.maxHeight)", category: .imageProcessing)
        Logger.info("Threshold: \(threshold), Force resize: \(forceResize)", category: .imageProcessing)
        
        // Validate inputs
        guard image.size.width > 0 && image.size.height > 0 else {
            Logger.error("Invalid image dimensions: \(image.size)", category: .imageProcessing)
            Logger.methodExit("ImageProcessor.convertToMonochrome", success: false)
            return nil
        }
        
        guard configuration.maxWidth > 0 && configuration.maxHeight > 0 else {
            Logger.error("Invalid configuration dimensions: \(configuration.maxWidth)x\(configuration.maxHeight)", category: .imageProcessing)
            Logger.methodExit("ImageProcessor.convertToMonochrome", success: false)
            return nil
        }
        
        guard threshold >= 0 && threshold <= 255 else {
            Logger.error("Invalid threshold: \(threshold) (must be 0-255)", category: .imageProcessing)
            Logger.methodExit("ImageProcessor.convertToMonochrome", success: false)
            return nil
        }
        
        // Resize if needed
        let resizedImage: UIImage
        if forceResize {
            // Force resize to exact dimensions (always resize, even if smaller)
            let targetSize = CGSize(width: configuration.maxWidth, height: configuration.maxHeight)
            Logger.info("Force resizing from \(Int(image.size.width))x\(Int(image.size.height)) to \(configuration.maxWidth)x\(configuration.maxHeight)", category: .imageProcessing)
            // Use scale = 1.0 to get exact pixel dimensions
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            format.opaque = false
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
            resizedImage = renderer.image { context in
                // Fill with white background first
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: targetSize))
                // Draw image scaled to fit
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            Logger.info("✓ Force resize completed", category: .imageProcessing)
        } else {
            Logger.info("Using standard resize (max dimensions)", category: .imageProcessing)
            resizedImage = resizeImage(image, maxWidth: configuration.maxWidth, maxHeight: configuration.maxHeight)
            Logger.info("Resized image size: \(Int(resizedImage.size.width))x\(Int(resizedImage.size.height))", category: .imageProcessing)
        }
        
        guard let cgImage = resizedImage.cgImage else {
            Logger.error("❌ ERROR - Failed to get CGImage from resized image", category: .imageProcessing)
            Logger.methodExit("ImageProcessor.convertToMonochrome", success: false)
            return nil
        }
        
        Logger.info("✓ Got CGImage from resized image", category: .imageProcessing)
        
        // Get actual pixel dimensions from CGImage
        // Note: CGImage dimensions are in pixels, not points
        var finalWidth = cgImage.width
        var finalHeight = cgImage.height
        var finalCGImage = cgImage
        
        Logger.info("CGImage dimensions: \(finalWidth)x\(finalHeight), expected: \(configuration.maxWidth)x\(configuration.maxHeight)", category: .imageProcessing)
        
        // If dimensions don't match exactly, create a new image with exact pixel dimensions
        if finalWidth != configuration.maxWidth || finalHeight != configuration.maxHeight {
            Logger.info("Dimensions mismatch, creating exact size image at pixel level", category: .imageProcessing)
            // Create image with exact pixel dimensions (scale = 1.0 to avoid scaling issues)
            let exactSize = CGSize(width: configuration.maxWidth, height: configuration.maxHeight)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0 // Use 1:1 scale to get exact pixel dimensions
            format.opaque = false
            
            let renderer = UIGraphicsImageRenderer(size: exactSize, format: format)
            let exactImage = renderer.image { context in
                // Fill with white background
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: exactSize))
                // Draw resized image scaled to fit
                resizedImage.draw(in: CGRect(origin: .zero, size: exactSize))
            }
            
            guard let exactCGImage = exactImage.cgImage else {
                Logger.error("Failed to create exact size CGImage", category: .imageProcessing)
                Logger.methodExit("ImageProcessor.convertToMonochrome", success: false)
                return nil
            }
            
            finalCGImage = exactCGImage
            finalWidth = exactCGImage.width
            finalHeight = exactCGImage.height
            Logger.info("Created exact size CGImage: \(finalWidth)x\(finalHeight)", category: .imageProcessing)
        }
        
        // Validate final dimensions
        guard finalWidth > 0 && finalHeight > 0 else {
            Logger.error("Invalid final dimensions: \(finalWidth)x\(finalHeight)", category: .imageProcessing)
            Logger.methodExit("ImageProcessor.convertToMonochrome", success: false)
            return nil
        }
        
        // Estimate memory usage
        let estimatedMemory = finalWidth * finalHeight * 4 // RGBA bytes
        let useMemoryEfficient = estimatedMemory > configuration.memoryThreshold
        
        Logger.info("Estimated memory: \(estimatedMemory) bytes, threshold: \(configuration.memoryThreshold) bytes", category: .imageProcessing)
        Logger.info("Using \(useMemoryEfficient ? "memory-efficient" : "standard") conversion method", category: .imageProcessing)
        
        let result: [[Bool]]?
        if useMemoryEfficient {
            result = convertToMonochromeMemoryEfficient(cgImage: finalCGImage, width: finalWidth, height: finalHeight, threshold: threshold)
        } else {
            result = convertToMonochromeStandard(cgImage: finalCGImage, width: finalWidth, height: finalHeight, threshold: threshold)
        }
        
        if let bitmap = result {
            // Validate result
            guard !bitmap.isEmpty && !bitmap[0].isEmpty else {
                Logger.error("Conversion returned empty bitmap", category: .imageProcessing)
                Logger.methodExit("ImageProcessor.convertToMonochrome", success: false)
                return nil
            }
            Logger.info("✓ Conversion successful - Bitmap size: \(bitmap[0].count)x\(bitmap.count)", category: .imageProcessing)
            Logger.methodExit("ImageProcessor.convertToMonochrome", success: true)
        } else {
            Logger.error("❌ ERROR - Conversion returned nil", category: .imageProcessing)
            Logger.methodExit("ImageProcessor.convertToMonochrome", success: false)
        }
        
        return result
    }
    
    /// Standard conversion (faster but uses more memory)
    private static func convertToMonochromeStandard(cgImage: CGImage, width: Int, height: Int, threshold: Int = 128) -> [[Bool]]? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let pixelData = context.data else {
            return nil
        }
        
        var bitmap: [[Bool]] = []
        bitmap.reserveCapacity(height)
        
        for y in 0..<height {
            var row: [Bool] = []
            row.reserveCapacity(width)
            
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let r = pixelData.load(fromByteOffset: offset, as: UInt8.self)
                let g = pixelData.load(fromByteOffset: offset + 1, as: UInt8.self)
                let b = pixelData.load(fromByteOffset: offset + 2, as: UInt8.self)
                
                // Convert to grayscale using luminance formula
                let gray = Int(Double(r) * 0.299 + Double(g) * 0.587 + Double(b) * 0.114)
                // Use threshold: true = black pixel, false = white pixel
                // Higher threshold means more pixels become white (less black)
                row.append(gray < threshold)
            }
            
            bitmap.append(row)
        }
        
        return bitmap
    }
    
    /// Memory-efficient conversion (processes in chunks)
    private static func convertToMonochromeMemoryEfficient(cgImage: CGImage, width: Int, height: Int, threshold: Int = 128) -> [[Bool]]? {
        // Process image in chunks to reduce memory footprint
        let chunkHeight = 256 // Process 256 rows at a time
        var bitmap: [[Bool]] = []
        bitmap.reserveCapacity(height)
        
        for chunkStart in stride(from: 0, to: height, by: chunkHeight) {
            let chunkEnd = min(chunkStart + chunkHeight, height)
            let chunkSize = chunkEnd - chunkStart
            
            let chunkResult = autoreleasepool { () -> [[Bool]]? in
                // Break up complex CGContext initialization
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let bytesPerRow = width * 4
                let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
                
                guard let context = CGContext(
                    data: nil,
                    width: width,
                    height: chunkSize,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                ) else {
                    return nil
                }
                
                // Draw only the chunk we're processing
                // Create a cropped image for this chunk
                let sourceRect = CGRect(x: 0, y: chunkStart, width: width, height: chunkSize)
                guard let croppedImage = cgImage.cropping(to: sourceRect) else {
                    return nil
                }
                
                let destRect = CGRect(x: 0, y: 0, width: width, height: chunkSize)
                context.draw(croppedImage, in: destRect)
                
                guard let pixelData = context.data else {
                    return nil
                }
                
                // Process this chunk
                return processChunkPixels(
                    pixelData: pixelData,
                    width: width,
                    chunkSize: chunkSize,
                    threshold: threshold
                )
            }
            
            if let chunkBitmap = chunkResult {
                bitmap.append(contentsOf: chunkBitmap)
            }
        }
        
        return bitmap
    }
    
    /// Process pixels for a chunk to avoid complex expressions
    private static func processChunkPixels(pixelData: UnsafeMutableRawPointer, width: Int, chunkSize: Int, threshold: Int = 128) -> [[Bool]] {
        var chunkBitmap: [[Bool]] = []
        chunkBitmap.reserveCapacity(chunkSize)
        
        for y in 0..<chunkSize {
            var row: [Bool] = []
            row.reserveCapacity(width)
            
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let r = pixelData.load(fromByteOffset: offset, as: UInt8.self)
                let g = pixelData.load(fromByteOffset: offset + 1, as: UInt8.self)
                let b = pixelData.load(fromByteOffset: offset + 2, as: UInt8.self)
                
                // Break up gray calculation
                let rWeight = Double(r) * 0.299
                let gWeight = Double(g) * 0.587
                let bWeight = Double(b) * 0.114
                let gray = Int(rWeight + gWeight + bWeight)
                
                // Use threshold: true = black pixel, false = white pixel
                // Higher threshold means more pixels become white (less black)
                row.append(gray < threshold)
            }
            
            chunkBitmap.append(row)
        }
        
        return chunkBitmap
    }
}

