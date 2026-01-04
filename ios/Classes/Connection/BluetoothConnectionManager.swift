import Foundation
import CoreBluetooth
import ExternalAccessory

/// Manages Bluetooth connections to printers using External Accessory Framework
/// For MFi (Made for iPhone/iPad) certified printers
class BluetoothConnectionManager: NSObject, ConnectionManager, StreamDelegate {
    
    // MARK: - Properties
    
    var configuration: PrinterConfiguration = .default
    private(set) var state: ConnectionState = .disconnected
    
    private var session: EASession?
    private var accessory: EAAccessory?
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var isConnectedFlag: Bool = false
    private let dataQueue = DispatchQueue(label: "com.diamond.printer.mfi.data")
    private var pendingDataQueue: [(Data, (Result<Void, Error>) -> Void)] = []
    private var isSending: Bool = false
    
    private let protocolString = "com.zebra.rawport" // Default protocol, can be customized
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessoryConnected),
            name: .EAAccessoryDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessoryDisconnected),
            name: .EAAccessoryDidDisconnect,
            object: nil
        )
        EAAccessoryManager.shared().registerForLocalNotifications()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        EAAccessoryManager.shared().unregisterForLocalNotifications()
    }
    
    // MARK: - ConnectionManager Protocol
    
    func connect(address: String, completion: @escaping (Bool) -> Void) {
        updateState(.connecting)
        
        // Find accessory by serial number or name
        let accessories = EAAccessoryManager.shared().connectedAccessories
        
        guard let accessory = accessories.first(where: { acc in
            acc.serialNumber == address || acc.name.contains(address)
        }) else {
            print("MFi: Accessory not found: \(address)")
            updateState(.error("Accessory not found: \(address)"))
            completion(false)
            return
        }
        
        // Check if accessory supports the protocol
        guard accessory.protocolStrings.contains(protocolString) else {
            print("MFi: Accessory does not support protocol: \(protocolString)")
            updateState(.error("Protocol not supported: \(protocolString)"))
            completion(false)
            return
        }
        
        self.accessory = accessory
        session = EASession(accessory: accessory, forProtocol: protocolString)
        
        guard let session = session else {
            print("MFi: Failed to create session")
            updateState(.error("Failed to create session"))
            completion(false)
            return
        }
        
        inputStream = session.inputStream
        outputStream = session.outputStream
        
        inputStream?.delegate = self
        outputStream?.delegate = self
        
        inputStream?.schedule(in: .current, forMode: .default)
        outputStream?.schedule(in: .current, forMode: .default)
        
        inputStream?.open()
        outputStream?.open()
        
        isConnectedFlag = true
        updateState(.connected)
        print("MFi: Connected to accessory: \(accessory.name)")
        completion(true)
    }
    
    func disconnect() {
        inputStream?.close()
        outputStream?.close()
        inputStream?.remove(from: .current, forMode: .default)
        outputStream?.remove(from: .current, forMode: .default)
        
        session = nil
        accessory = nil
        inputStream = nil
        outputStream = nil
        isConnectedFlag = false
        pendingDataQueue.removeAll()
        isSending = false
        updateState(.disconnected)
        
        print("MFi: Disconnected from printer")
    }
    
    func isConnected() -> Bool {
        return isConnectedFlag && outputStream?.streamStatus == .open
    }
    
    func sendData(_ data: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        Logger.methodEntry("MFi sendData", category: .dataTransmission)
        Logger.info("Data size: \(data.count) bytes", category: .dataTransmission)
        
        // Validate data
        guard data.count > 0 else {
            Logger.error("Data is empty", category: .dataTransmission)
            Logger.methodExit("MFi sendData", success: false)
            completion(.failure(PrinterError.sendFailed("Data is empty")))
            return
        }
        
        // Check connection health
        guard isConnected() else {
            Logger.error("Not connected - isConnected() returned false", category: .connection)
            Logger.methodExit("MFi sendData", success: false)
            completion(.failure(PrinterError.notConnected))
            return
        }
        
        guard let outputStream = self.outputStream else {
            Logger.error("Output stream is nil", category: .connection)
            Logger.methodExit("MFi sendData", success: false)
            completion(.failure(PrinterError.notConnected))
            return
        }
        
        guard outputStream.streamStatus == .open else {
            Logger.error("Output stream is not open. Status: \(outputStream.streamStatus.rawValue)", category: .connection)
            Logger.methodExit("MFi sendData", success: false)
            completion(.failure(PrinterError.notConnected))
            return
        }
        
        Logger.info("Output stream is open and ready", category: .connection)
        
        // Check if this is CPCL data
        if CPCLChunkingHelper.isCPCLData(data) {
            Logger.info("Detected CPCL data - will use CPCL-aware chunking", category: .dataTransmission)
        } else {
            Logger.info("Non-CPCL data - will use standard chunking", category: .dataTransmission)
        }
        
        dataQueue.async { [weak self] in
            guard let self = self else {
                completion(.failure(PrinterError.sendFailed("Manager deallocated")))
                return
            }
            
            // Add to queue
            self.pendingDataQueue.append((data, completion))
            self.processDataQueue(outputStream: outputStream)
        }
    }
    
    // MARK: - Private Methods
    
    private func updateState(_ newState: ConnectionState) {
        DispatchQueue.main.async { [weak self] in
            self?.state = newState
        }
    }
    
    private func processDataQueue(outputStream: OutputStream) {
        guard !isSending, !pendingDataQueue.isEmpty else {
            return
        }
        
        isSending = true
        let (data, completion) = pendingDataQueue.removeFirst()
        
        sendDataWithRetry(data: data, outputStream: outputStream, retryCount: 0, completion: completion)
    }
    
    private func sendDataWithRetry(data: Data, outputStream: OutputStream, retryCount: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        let chunkSize = configuration.mfiChunkSize
        let delay = configuration.mfiChunkDelay
        
        // Use CPCL-aware chunking if needed
        // Verify connection is still active
        guard isConnected(), outputStream.streamStatus == .open else {
            Logger.error("Connection lost before chunking", category: .connection)
            Logger.methodExit("MFi sendData", success: false)
            completion(.failure(PrinterError.notConnected))
            return
        }
        
        let chunks = chunkData(data, maxChunkSize: chunkSize)
        Logger.info("Data chunked into \(chunks.count) chunks (chunk size: \(chunkSize) bytes)", category: .dataTransmission)
        
        // Validate chunks
        guard !chunks.isEmpty else {
            Logger.error("Chunking produced no chunks", category: .dataTransmission)
            Logger.methodExit("MFi sendData", success: false)
            completion(.failure(PrinterError.sendFailed("Chunking failed")))
            return
        }
        
        for (index, chunk) in chunks.enumerated() {
            Logger.debug("Chunk \(index + 1)/\(chunks.count): \(chunk.count) bytes", category: .dataTransmission)
        }
        var totalBytesWritten = 0
        var lastError: Error?
        
        for chunk in chunks {
            
            let bytesWritten = chunk.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Int in
                guard let baseAddress = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }
                return outputStream.write(baseAddress, maxLength: chunk.count)
            }
            
            if bytesWritten < 0 {
                let error = outputStream.streamError ?? PrinterError.sendFailed("Unknown write error")
                lastError = error
                
                // Retry logic
                if retryCount < configuration.maxTransmissionRetries {
                    let retryDelay = min(configuration.retryDelayBase * pow(2.0, Double(retryCount)), configuration.maxRetryDelay)
                    Logger.info("Retrying send after \(retryDelay) seconds (attempt \(retryCount + 1))", category: .dataTransmission)
                    
                    DispatchQueue.global().asyncAfter(deadline: .now() + retryDelay) { [weak self] in
                        guard let self = self, let outputStream = self.outputStream else {
                            completion(.failure(PrinterError.sendFailed("Stream unavailable")))
                            return
                        }
                        self.sendDataWithRetry(data: data, outputStream: outputStream, retryCount: retryCount + 1, completion: completion)
                    }
                    return
                } else {
                    isSending = false
                    completion(.failure(PrinterError.transmissionRetryExceeded(configuration.maxTransmissionRetries)))
                    // Process next item in queue
                    if !pendingDataQueue.isEmpty {
                        processDataQueue(outputStream: outputStream)
                    }
                    return
                }
            }
            
            totalBytesWritten += bytesWritten
            
            // Small delay between chunks to avoid buffer overflow
            if delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
        }
        
        // Verify connection is still active
        guard isConnected(), outputStream.streamStatus == .open else {
            Logger.error("Connection lost during transmission", category: .connection)
            Logger.methodExit("MFi sendData", success: false)
            isSending = false
            completion(.failure(PrinterError.notConnected))
            return
        }
        
        if let error = lastError {
            Logger.error("❌ FAILED - Error: \(error.localizedDescription)", category: .dataTransmission)
            Logger.methodExit("MFi sendData", success: false)
            isSending = false
            completion(.failure(error))
        } else {
            let totalChunks = chunks.count
            Logger.info("✓ SUCCESS - Sent \(totalChunks) chunks (\(totalBytesWritten) bytes total)", category: .dataTransmission)
            Logger.methodExit("MFi sendData", success: true)
            isSending = false
            completion(.success(()))
        }
        
        // Process next item in queue
        if !pendingDataQueue.isEmpty {
            processDataQueue(outputStream: outputStream)
        }
    }
    
    @objc private func accessoryConnected(_ notification: Notification) {
        guard let accessory = notification.userInfo?[EAAccessoryKey] as? EAAccessory else {
            return
        }
        print("MFi: Accessory connected: \(accessory.name)")
    }
    
    @objc private func accessoryDisconnected(_ notification: Notification) {
        guard let accessory = notification.userInfo?[EAAccessoryKey] as? EAAccessory else {
            return
        }
        print("MFi: Accessory disconnected: \(accessory.name)")
        
        if self.accessory?.connectionID == accessory.connectionID {
            disconnect()
        }
    }
    
    // MARK: - StreamDelegate
    
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .openCompleted:
            print("MFi: Stream opened")
        case .hasBytesAvailable:
            // Handle incoming data if needed
            break
        case .hasSpaceAvailable:
            // Ready to send data
            break
        case .errorOccurred:
            print("MFi: Stream error: \(aStream.streamError?.localizedDescription ?? "Unknown")")
            updateState(.error("Stream error: \(aStream.streamError?.localizedDescription ?? "Unknown")"))
        case .endEncountered:
            print("MFi: Stream ended")
            disconnect()
        default:
            break
        }
    }
    
    /// Get list of available MFi accessories (both connected and available)
    func getConnectedDevices() -> [[String: String]] {
        // Get all available accessories (includes both connected and paired devices)
        let accessories = EAAccessoryManager.shared().connectedAccessories
        
        // Filter accessories that support our protocol
        let compatibleAccessories = accessories.filter { accessory in
            accessory.protocolStrings.contains(protocolString)
        }
        
        print("MFi: Found \(compatibleAccessories.count) MFi accessories supporting protocol: \(protocolString)")
        
        return compatibleAccessories.map { accessory in
            [
                "name": accessory.name,
                "address": accessory.serialNumber.isEmpty ? accessory.name : accessory.serialNumber,
                "type": "bluetooth"
            ]
        }
    }
    
    /// Get all available MFi accessories (for scanning)
    func getAllAvailableDevices() -> [[String: String]] {
        // Note: EAAccessoryManager only shows connected accessories
        // For MFi devices, they must be paired in iOS Settings first
        // Then they appear here when connected or available
        let accessories = EAAccessoryManager.shared().connectedAccessories
        
        // Include all accessories, not just those with our protocol
        // User might have different printer protocols
        let allAccessories = accessories.map { accessory in
            [
                "name": accessory.name,
                "address": accessory.serialNumber.isEmpty ? accessory.name : accessory.serialNumber,
                "type": "bluetooth"
            ]
        }
        
        print("MFi: Found \(allAccessories.count) total MFi accessories")
        return allAccessories
    }
}

