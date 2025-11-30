import Foundation
import Network

/// Manages WiFi/Network socket connections to printers
@available(iOS 12.0, *)
class WiFiConnectionManager: ConnectionManager {
    
    // MARK: - Properties
    
    var configuration: PrinterConfiguration = .default
    private(set) var state: ConnectionState = .disconnected
    
    private var connection: NWConnection?
    private var isConnectedFlag: Bool = false
    private let queue = DispatchQueue(label: "com.diamond.printer.wifi")
    private var connectionTimeoutTimer: Timer?
    private var pendingDataQueue: [(Data, (Result<Void, Error>) -> Void)] = []
    private var isSending: Bool = false
    
    // MARK: - ConnectionManager Protocol
    
    func connect(address: String, completion: @escaping (Bool) -> Void) {
        queue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            self.disconnect()
            self.updateState(.connecting)
        
        // Parse address (format: "IP:PORT" or just "IP")
            let (host, port) = self.parseAddress(address)
            
            guard !host.isEmpty else {
                self.updateState(.error("Invalid host address"))
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
        
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: port))
        let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .wifi
            
            self.connection = NWConnection(to: endpoint, using: parameters)
        
            self.connection?.stateUpdateHandler = { [weak self] connectionState in
                guard let self = self else { return }
        
                switch connectionState {
            case .ready:
                    self.isConnectedFlag = true
                    self.cancelConnectionTimeout()
                    self.updateState(.connected)
                    print("WiFi: Connection established to \(host):\(port)")
                    DispatchQueue.main.async {
                completion(true)
                    }
                    
            case .failed(let error):
                    print("WiFi: Connection failed: \(error)")
                    self.isConnectedFlag = false
                    self.cancelConnectionTimeout()
                    self.updateState(.error("Connection failed: \(error.localizedDescription)"))
                    DispatchQueue.main.async {
                completion(false)
                    }
                    
            case .cancelled:
                    print("WiFi: Connection cancelled")
                    self.isConnectedFlag = false
                    self.cancelConnectionTimeout()
                    self.updateState(.disconnected)
                    
                case .waiting(let error):
                    print("WiFi: Connection waiting: \(error.localizedDescription)")
                    // Don't fail yet, might be temporary
                    
            default:
                break
            }
        }
        
            self.connection?.start(queue: self.queue)
            self.startConnectionTimeout(completion: completion)
        }
    }
    
    func disconnect() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            self.cancelConnectionTimeout()
            self.connection?.cancel()
            self.connection = nil
            self.isConnectedFlag = false
            self.updateState(.disconnected)
            self.pendingDataQueue.removeAll()
            self.isSending = false
            
            print("WiFi: Disconnected")
        }
    }
    
    func isConnected() -> Bool {
        return isConnectedFlag && connection?.state == .ready
    }
    
    func sendData(_ data: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        Logger.methodEntry("WiFi sendData", category: .dataTransmission)
        Logger.info("Data size: \(data.count) bytes", category: .dataTransmission)
        
        // Validate data
        guard data.count > 0 else {
            Logger.error("Data is empty", category: .dataTransmission)
            Logger.methodExit("WiFi sendData", success: false)
            completion(.failure(PrinterError.sendFailed("Data is empty")))
            return
        }
        
        // Check connection health
        guard isConnected() else {
            Logger.error("Not connected - isConnected() returned false", category: .connection)
            Logger.methodExit("WiFi sendData", success: false)
            completion(.failure(PrinterError.notConnected))
            return
        }
        
        guard let connection = self.connection else {
            Logger.error("Connection is nil", category: .connection)
            Logger.methodExit("WiFi sendData", success: false)
            completion(.failure(PrinterError.notConnected))
            return
        }
        
        // Verify connection state
        guard connection.state == .ready else {
            Logger.error("Connection state is not ready: \(connection.state)", category: .connection)
            Logger.methodExit("WiFi sendData", success: false)
            completion(.failure(PrinterError.notConnected))
            return
        }
        
        Logger.info("Connection state: \(connection.state)", category: .connection)
        
        // Check if this is CPCL data
        if CPCLChunkingHelper.isCPCLData(data) {
            Logger.info("Detected CPCL data - will use CPCL-aware chunking", category: .dataTransmission)
            } else {
            Logger.info("Non-CPCL data - will use standard chunking", category: .dataTransmission)
        }
        
        queue.async { [weak self] in
            guard let self = self else {
                completion(.failure(PrinterError.sendFailed("Manager deallocated")))
                return
            }
            
            // Add to queue
            self.pendingDataQueue.append((data, completion))
            self.processDataQueue(connection: connection)
        }
    }
    
    // MARK: - Private Methods
    
    private func updateState(_ newState: ConnectionState) {
        DispatchQueue.main.async { [weak self] in
            self?.state = newState
        }
    }
    
    private func startConnectionTimeout(completion: @escaping (Bool) -> Void) {
        cancelConnectionTimeout()
        
        connectionTimeoutTimer = Timer.scheduledTimer(withTimeInterval: configuration.wifiConnectionTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if !self.isConnectedFlag {
                print("WiFi: Connection timeout after \(self.configuration.wifiConnectionTimeout) seconds")
                self.cancelConnectionTimeout()
                self.updateState(.error("Connection timeout"))
                self.disconnect()
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }
    
    private func cancelConnectionTimeout() {
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil
    }
    
    private func parseAddress(_ address: String) -> (String, UInt16) {
        let components = address.split(separator: ":")
        let host = String(components[0])
        let port: UInt16 = components.count > 1 ? UInt16(components[1]) ?? 9100 : 9100
        return (host, port)
    }
    
    private func processDataQueue(connection: NWConnection) {
        guard !isSending, !pendingDataQueue.isEmpty else {
            return
        }
        
        isSending = true
        let (data, completion) = pendingDataQueue.removeFirst()
        
        // Use CPCL-aware chunking if needed
        let chunkSize = configuration.wifiChunkSize
        // Verify connection is still active
        guard isConnected(), connection.state == .ready else {
            Logger.error("Connection lost before chunking", category: .connection)
            Logger.methodExit("WiFi sendData", success: false)
            completion(.failure(PrinterError.notConnected))
            return
        }
        
        let chunks = chunkData(data, maxChunkSize: chunkSize)
        Logger.info("Data chunked into \(chunks.count) chunks (chunk size: \(chunkSize) bytes)", category: .dataTransmission)
        
        // Validate chunks
        guard !chunks.isEmpty else {
            Logger.error("Chunking produced no chunks", category: .dataTransmission)
            Logger.methodExit("WiFi sendData", success: false)
            completion(.failure(PrinterError.sendFailed("Chunking failed")))
            return
        }
        
        for (index, chunk) in chunks.enumerated() {
            Logger.debug("Chunk \(index + 1)/\(chunks.count): \(chunk.count) bytes", category: .dataTransmission)
        }
        
        if chunks.count == 1 {
            // Single chunk, send directly
            sendChunk(data: chunks[0], connection: connection, retryCount: 0, completion: completion)
        } else {
            // Multiple chunks, send sequentially
            sendChunksSequentially(chunks: chunks, connection: connection, index: 0, completion: completion)
        }
    }
    
    private func sendChunksSequentially(chunks: [Data], connection: NWConnection, index: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        // Verify connection is still active before each chunk
        guard isConnected() && connection.state == .ready else {
            Logger.error("Connection lost during chunk transmission at chunk \(index + 1)", category: .connection)
            Logger.methodExit("WiFi sendData", success: false)
            isSending = false
            completion(.failure(PrinterError.notConnected))
            return
        }
        
        guard index < chunks.count else {
            // All chunks sent
            let totalBytes = chunks.reduce(0) { $0 + $1.count }
            Logger.info("✓ SUCCESS - Sent all \(chunks.count) chunks successfully (\(totalBytes) bytes total)", category: .dataTransmission)
            Logger.methodExit("WiFi sendData", success: true)
            isSending = false
            completion(.success(()))
            // Process next item in queue
            if !pendingDataQueue.isEmpty {
                processDataQueue(connection: connection)
            }
            return
        }
        
        Logger.debug("Sending chunk \(index + 1)/\(chunks.count) (\(chunks[index].count) bytes)", category: .dataTransmission)
        
        let chunk = chunks[index]
        sendChunk(data: chunk, connection: connection, retryCount: 0) { [weak self] result in
            guard let self = self else {
                completion(.failure(PrinterError.sendFailed("Manager deallocated")))
                return
            }
            
            switch result {
            case .success:
                // Small delay between chunks if configured
                let delay = self.configuration.wifiChunkDelay
                if delay > 0 {
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        self.sendChunksSequentially(chunks: chunks, connection: connection, index: index + 1, completion: completion)
                    }
                } else {
                    self.sendChunksSequentially(chunks: chunks, connection: connection, index: index + 1, completion: completion)
                }
                
            case .failure(let error):
                Logger.error("❌ FAILED - Error sending chunk \(index + 1): \(error.localizedDescription)", category: .dataTransmission)
                Logger.methodExit("WiFi sendData", success: false)
                self.isSending = false
                completion(.failure(error))
            }
        }
    }
    
    private func sendChunk(data: Data, connection: NWConnection, retryCount: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        // Verify connection before sending
        guard isConnected() && connection.state == .ready else {
            Logger.error("Connection lost before sending chunk", category: .connection)
            completion(.failure(PrinterError.notConnected))
            return
        }
        
        if retryCount > 0 {
            Logger.info("Retrying chunk send (attempt \(retryCount + 1))", category: .dataTransmission)
        }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self = self else {
                completion(.failure(PrinterError.sendFailed("Manager deallocated")))
                return
            }
            
            if let error = error {
                // Retry logic
                if retryCount < self.configuration.maxTransmissionRetries {
                    let retryDelay = min(self.configuration.retryDelayBase * pow(2.0, Double(retryCount)), self.configuration.maxRetryDelay)
                    Logger.info("Retrying send after \(retryDelay) seconds (attempt \(retryCount + 1))", category: .dataTransmission)
                    
                    DispatchQueue.global().asyncAfter(deadline: .now() + retryDelay) {
                        self.sendChunk(data: data, connection: connection, retryCount: retryCount + 1, completion: completion)
                    }
                } else {
                    print("WiFi: Send failed after \(self.configuration.maxTransmissionRetries) retries: \(error.localizedDescription)")
                    completion(.failure(PrinterError.transmissionRetryExceeded(self.configuration.maxTransmissionRetries)))
                }
            } else {
                completion(.success(()))
            }
        })
    }
}
