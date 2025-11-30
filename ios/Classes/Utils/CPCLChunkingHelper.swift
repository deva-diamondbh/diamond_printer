import Foundation

/// Helper for CPCL-aware chunking to avoid breaking CPCL command syntax
class CPCLChunkingHelper {
    
    /// Detects if data contains CPCL commands
    static func isCPCLData(_ data: Data) -> Bool {
        guard let string = String(data: data, encoding: .utf8) else {
            return false
        }
        
        // Check for CPCL command patterns
        let cpclPatterns = [
            "! 0 200 200",  // CPCL header
            "\r\nEG ",      // EG command
            "\r\nGRAPHICS ", // GRAPHICS command
            "\r\nCENTER\r\n", // CENTER command
            "\r\nFORM\r\n",   // FORM command
            "\r\nPRINT\r\n"   // PRINT command
        ]
        
        for pattern in cpclPatterns {
            if string.contains(pattern) {
                return true
            }
        }
        
        return false
    }
    
    /// Chunks CPCL data at safe boundaries
    /// - Ensures hex data is split at complete byte pairs (2 hex chars = 1 byte)
    /// - Splits at newline boundaries when possible
    /// - Avoids splitting in the middle of command syntax
    static func chunkCPCLData(_ data: Data, maxChunkSize: Int) -> [Data] {
        guard let string = String(data: data, encoding: .utf8) else {
            // If not valid UTF-8, fall back to simple chunking
            return simpleChunk(data: data, chunkSize: maxChunkSize)
        }
        
        // If data fits in one chunk, return as-is
        if data.count <= maxChunkSize {
            return [data]
        }
        
        var chunks: [Data] = []
        var currentChunk = ""
        var currentChunkSize = 0
        
        // Split by lines to preserve command boundaries
        let lines = string.components(separatedBy: "\r\n")
        
        for (lineIndex, line) in lines.enumerated() {
            let isLastLine = lineIndex == lines.count - 1
            let lineWithNewline = isLastLine ? line : line + "\r\n"
            let lineData = lineWithNewline.data(using: .utf8) ?? Data()
            
            // Check if this line contains hex data
            let isHexDataLine = isHexDataLine(line)
            
            if isHexDataLine && lineData.count > maxChunkSize {
                // Hex line is too large - need to split it carefully
                // First, save current chunk if any
                if !currentChunk.isEmpty {
                    if let chunkData = currentChunk.data(using: .utf8) {
                        chunks.append(chunkData)
                    }
                    currentChunk = ""
                    currentChunkSize = 0
                }
                
                // Split hex line - handle EG command with hex data on same line
                if line.hasPrefix("EG ") {
                    // Split EG command: keep "EG params " together, split hex data
                    let parts = splitEGCommandWithHex(line, maxChunkSize: maxChunkSize)
                    for (partIndex, part) in parts.enumerated() {
                        let isLastPart = partIndex == parts.count - 1
                        let partWithNewline = isLastPart && isLastLine ? part : part + "\r\n"
                        if let partData = partWithNewline.data(using: .utf8) {
                            chunks.append(partData)
                        }
                    }
                } else {
                    // Pure hex data line - split at even boundaries
                    let hexChunks = chunkHexLine(line, maxChunkSize: maxChunkSize)
                    for (hexIndex, hexChunk) in hexChunks.enumerated() {
                        let isLastHexChunk = hexIndex == hexChunks.count - 1
                        let hexChunkWithNewline = isLastHexChunk && isLastLine ? hexChunk : hexChunk + "\r\n"
                        if let hexChunkData = hexChunkWithNewline.data(using: .utf8) {
                            chunks.append(hexChunkData)
                        }
                    }
                }
            } else {
                // Regular line or small hex line - try to add to current chunk
                if currentChunkSize + lineData.count <= maxChunkSize {
                    // Add to current chunk
                    currentChunk += lineWithNewline
                    currentChunkSize += lineData.count
                } else {
                    // Save current chunk and start new one
                    if !currentChunk.isEmpty {
                        if let chunkData = currentChunk.data(using: .utf8) {
                            chunks.append(chunkData)
                        }
                    }
                    currentChunk = lineWithNewline
                    currentChunkSize = lineData.count
                }
            }
        }
        
        // Add remaining chunk
        if !currentChunk.isEmpty {
            if let chunkData = currentChunk.data(using: .utf8) {
                chunks.append(chunkData)
            }
        }
        
        return chunks.isEmpty ? [data] : chunks
    }
    
    /// Checks if a line contains hex data (after EG or GRAPHICS command)
    private static func isHexDataLine(_ line: String) -> Bool {
        // CPCL hex data can be:
        // 1. On the same line as EG command: "EG 123 456 AABBCCDD..."
        // 2. On a separate line after EG command (new format for large images)
        // 3. On a separate line after GRAPHICS command
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return false
        }
        
        // Check if line starts with EG or GRAPHICS command followed by hex data
        if trimmed.hasPrefix("EG ") {
            // Extract the part after "EG <numbers> <numbers> <numbers> "
            // Format: "EG bytesPerRow height x y <hexdata>"
            let components = trimmed.components(separatedBy: " ")
            if components.count >= 5 {
                // Check if there's hex data after the command parameters
                let potentialHexData = components.dropFirst(5).joined(separator: "")
                if !potentialHexData.isEmpty && isHexString(potentialHexData) {
                    return true
                }
            }
            // If it's just "EG bytesPerRow height x y" without hex, it's not a hex line
            return false
        } else if trimmed.hasPrefix("GRAPHICS ") {
            // GRAPHICS command with binary data - not hex, but still needs careful chunking
            return false // Binary data is handled differently
        } else {
            // Check if line contains only hex characters (and spaces) - pure hex data line
            // This handles the case where hex data is on a separate line after EG command
            if isHexString(trimmed) {
                return true
            }
        }
        
        return false
    }
    
    /// Checks if a string contains only hex characters (and spaces)
    private static func isHexString(_ string: String) -> Bool {
        let hexPattern = "^[0-9A-Fa-f\\s]+$"
        let regex = try? NSRegularExpression(pattern: hexPattern, options: [])
        let range = NSRange(location: 0, length: string.utf16.count)
        return regex?.firstMatch(in: string, options: [], range: range) != nil
    }
    
    /// Splits an EG command line that contains hex data
    /// Format: "EG bytesPerRow height x y <hexdata>"
    /// Note: CPCL printers typically expect the entire EG command in one transmission.
    /// If we must split, we split the hex data at even boundaries and send as continuation.
    /// The printer should buffer and process as one command.
    private static func splitEGCommandWithHex(_ line: String, maxChunkSize: Int) -> [String] {
        let components = line.components(separatedBy: " ")
        guard components.count >= 5 else {
            // Malformed EG command, return as-is
            return [line]
        }
        
        // Extract command part: "EG bytesPerRow height x y "
        let commandPart = components.prefix(5).joined(separator: " ") + " "
        let hexDataPart = components.dropFirst(5).joined(separator: "")
        
        // Calculate available space for hex data (accounting for command and newline)
        let commandData = commandPart.data(using: .utf8) ?? Data()
        let newlineData = "\r\n".data(using: .utf8) ?? Data()
        let overhead = commandData.count + newlineData.count
        let availableForHex = maxChunkSize - overhead
        
        if availableForHex <= 0 {
            // Command itself is too large, send as single chunk
            // Connection manager will need to handle this
            return [line]
        }
        
        // Split hex data at even boundaries
        let hexChunks = chunkHexLine(hexDataPart, maxChunkSize: availableForHex)
        
        if hexChunks.isEmpty {
            return [line]
        }
        
        // First chunk includes the command, subsequent chunks are hex data continuation
        var result: [String] = []
        result.append(commandPart + hexChunks[0])
        
        // Remaining chunks are just hex data (printer should buffer)
        for i in 1..<hexChunks.count {
            result.append(hexChunks[i])
        }
        
        return result
    }
    
    /// Chunks a hex data line ensuring complete byte pairs
    /// Hex data in CPCL is sent as ASCII characters, so we need to ensure
    /// we don't split in the middle of a hex byte pair (e.g., "AB" should stay together)
    private static func chunkHexLine(_ line: String, maxChunkSize: Int) -> [String] {
        // Remove spaces for chunking (spaces are optional in hex data)
        let hexOnly = line.replacingOccurrences(of: " ", with: "")
        
        // Ensure we chunk at even boundaries (2 hex chars = 1 byte of data)
        // But remember: each hex char is 1 byte in UTF-8, so maxChunkSize applies directly
        var chunks: [String] = []
        var offset = 0
        
        while offset < hexOnly.count {
            // Calculate chunk size (must be even for complete hex bytes)
            let remaining = hexOnly.count - offset
            var chunkSize = min(maxChunkSize, remaining)
            
            // Ensure chunk size is even (complete hex byte pairs)
            if chunkSize % 2 != 0 {
                chunkSize -= 1
            }
            
            // Don't create empty chunks
            if chunkSize <= 0 {
                break
            }
            
            let startIndex = hexOnly.index(hexOnly.startIndex, offsetBy: offset)
            let endIndex = hexOnly.index(startIndex, offsetBy: chunkSize)
            let chunk = String(hexOnly[startIndex..<endIndex])
            chunks.append(chunk)
            offset += chunkSize
        }
        
        return chunks
    }
    
    /// Simple chunking fallback for non-UTF-8 data
    private static func simpleChunk(data: Data, chunkSize: Int) -> [Data] {
        var chunks: [Data] = []
        var offset = 0
        
        while offset < data.count {
            let chunkEnd = min(offset + chunkSize, data.count)
            chunks.append(data.subdata(in: offset..<chunkEnd))
            offset = chunkEnd
        }
        
        return chunks
    }
}

