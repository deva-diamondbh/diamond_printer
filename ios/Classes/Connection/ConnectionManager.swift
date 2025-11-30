import Foundation

/// Base protocol for all connection types
protocol ConnectionManager {
    var configuration: PrinterConfiguration { get set }
    var state: ConnectionState { get }
    
    func connect(address: String, completion: @escaping (Bool) -> Void)
    func disconnect()
    func isConnected() -> Bool
    func sendData(_ data: Data, completion: @escaping (Result<Void, Error>) -> Void)
    
    /// Chunks data appropriately based on connection type and data format
    func chunkData(_ data: Data, maxChunkSize: Int) -> [Data]
}

/// Default implementation for chunking
extension ConnectionManager {
    func chunkData(_ data: Data, maxChunkSize: Int) -> [Data] {
        // Check if this is CPCL data and use CPCL-aware chunking
        if CPCLChunkingHelper.isCPCLData(data) {
            return CPCLChunkingHelper.chunkCPCLData(data, maxChunkSize: maxChunkSize)
        }
        
        // Default chunking for other data types
        var chunks: [Data] = []
        var offset = 0
        
        while offset < data.count {
            let chunkEnd = min(offset + maxChunkSize, data.count)
            chunks.append(data.subdata(in: offset..<chunkEnd))
            offset = chunkEnd
        }
        
        return chunks
    }
}

