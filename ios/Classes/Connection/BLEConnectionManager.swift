import Foundation
import CoreBluetooth

/// Manages Bluetooth LE connections to printers
class BLEConnectionManager: NSObject, ConnectionManager, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    // MARK: - Properties
    
    var configuration: PrinterConfiguration = .default
    private(set) var state: ConnectionState = .disconnected
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var isConnectedFlag: Bool = false
    private var connectionCompletion: ((Bool) -> Void)?
    private var targetAddress: String?
    private var connectionTimeoutTimer: Timer?
    private var serviceDiscoveryTimeoutTimer: Timer?
    private var characteristicDiscoveryTimeoutTimer: Timer?
    private var discoveredServices: [CBService] = []
    private var discoveredCharacteristics: [CBCharacteristic] = []
    private let connectionQueue = DispatchQueue(label: "com.diamond.printer.ble.connection")
    private let dataQueue = DispatchQueue(label: "com.diamond.printer.ble.data")
    
    // Standard Serial Port Service UUID (commonly used by BLE printers)
    private let serialServiceUUID = CBUUID(string: "49535343-FE7D-4AE5-8FA9-9FAFD205E455")
    private let writeCharacteristicUUID = CBUUID(string: "49535343-8841-43F4-A8D4-ECBE34729BB3")
    
    // Store known device UUIDs
    private let userDefaults = UserDefaults.standard
    private let knownDevicesKey = "com.diamond.printer.knownDevices"
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: connectionQueue)
    }
    
    // MARK: - ConnectionManager Protocol
    
    func connect(address: String, completion: @escaping (Bool) -> Void) {
        connectionQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            
            // Cancel any existing connection attempt
            self.cancelConnectionAttempt()
            
        self.connectionCompletion = completion
        self.targetAddress = address
            self.updateState(.connecting)
            
            // Check Bluetooth state
            if self.centralManager.state != .poweredOn {
                print("BLE: Bluetooth not powered on, current state: \(self.centralManager.state.rawValue)")
                self.updateState(.error("Bluetooth not powered on"))
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }
        
        // Check if we already have this peripheral cached
            if let uuid = UUID(uuidString: address) {
                let peripherals = self.centralManager.retrievePeripherals(withIdentifiers: [uuid])
        
        if let peripheral = peripherals.first {
                    print("BLE: Found cached peripheral: \(peripheral.name ?? "Unknown")")
                    self.connectedPeripheral = peripheral
            peripheral.delegate = self
                    self.centralManager.connect(peripheral, options: nil)
                    self.startConnectionTimeout()
                    return
                }
            }
            
            // Start scanning to find the device
            print("BLE: Scanning for device: \(address)")
            self.centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            self.startConnectionTimeout()
        }
    }
    
    func disconnect() {
        connectionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.cancelConnectionAttempt()
            
            if let peripheral = self.connectedPeripheral {
                self.centralManager.cancelPeripheralConnection(peripheral)
            }
            
            self.connectedPeripheral = nil
            self.writeCharacteristic = nil
            self.isConnectedFlag = false
            self.discoveredServices = []
            self.discoveredCharacteristics = []
            self.updateState(.disconnected)
            
            print("BLE: Disconnected from printer")
        }
    }
    
    func isConnected() -> Bool {
        return isConnectedFlag && connectedPeripheral?.state == .connected && writeCharacteristic != nil
    }
    
    func sendData(_ data: Data, completion: @escaping (Result<Void, Error>) -> Void) {
        Logger.methodEntry("BLE sendData", category: .dataTransmission)
        Logger.info("Data size: \(data.count) bytes", category: .dataTransmission)
        
        // Validate data
        guard data.count > 0 else {
            Logger.error("Data is empty", category: .dataTransmission)
            Logger.methodExit("BLE sendData", success: false)
            completion(.failure(PrinterError.sendFailed("Data is empty")))
            return
        }
        
        // Check connection health
        guard isConnected() else {
            Logger.error("Not connected - isConnected() returned false", category: .connection)
            Logger.methodExit("BLE sendData", success: false)
            completion(.failure(PrinterError.notConnected))
            return
        }
        
        guard let peripheral = connectedPeripheral, let characteristic = writeCharacteristic else {
            Logger.error("Not connected or no write characteristic - peripheral: \(String(describing: connectedPeripheral)), characteristic: \(String(describing: writeCharacteristic))", category: .connection)
            Logger.methodExit("BLE sendData", success: false)
            completion(.failure(PrinterError.notConnected))
            return
        }
        
        // Verify peripheral is still connected
        guard peripheral.state == .connected else {
            Logger.error("Peripheral state is not connected: \(peripheral.state.rawValue)", category: .connection)
            Logger.methodExit("BLE sendData", success: false)
            completion(.failure(PrinterError.notConnected))
            return
        }
        
        Logger.info("Connected to peripheral: \(peripheral.name ?? "Unknown")", category: .connection)
        Logger.info("Write characteristic: \(characteristic.uuid)", category: .connection)
        
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
            
            self.sendDataWithRetry(data: data, peripheral: peripheral, characteristic: characteristic, retryCount: 0, completion: completion)
        }
    }
    
    // MARK: - Private Methods
    
    private func updateState(_ newState: ConnectionState) {
        DispatchQueue.main.async { [weak self] in
            self?.state = newState
        }
    }
    
    private func startConnectionTimeout() {
        cancelConnectionTimeout()
        connectionTimeoutTimer = Timer.scheduledTimer(withTimeInterval: configuration.bleConnectionTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if !self.isConnectedFlag {
                print("BLE: Connection timeout after \(self.configuration.bleConnectionTimeout) seconds")
                self.cancelConnectionAttempt()
                self.updateState(.error("Connection timeout"))
                if let completion = self.connectionCompletion {
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    self.connectionCompletion = nil
                }
            }
        }
    }
    
    private func startServiceDiscoveryTimeout() {
        cancelServiceDiscoveryTimeout()
        serviceDiscoveryTimeoutTimer = Timer.scheduledTimer(withTimeInterval: configuration.bleServiceDiscoveryTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.writeCharacteristic == nil {
                print("BLE: Service discovery timeout")
                self.cancelConnectionAttempt()
                self.updateState(.error("Service discovery timeout"))
                if let completion = self.connectionCompletion {
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    self.connectionCompletion = nil
                }
            }
        }
    }
    
    private func startCharacteristicDiscoveryTimeout() {
        cancelCharacteristicDiscoveryTimeout()
        characteristicDiscoveryTimeoutTimer = Timer.scheduledTimer(withTimeInterval: configuration.bleCharacteristicDiscoveryTimeout, repeats: false) { [weak self] _ in
                guard let self = self else { return }
            if self.writeCharacteristic == nil {
                print("BLE: Characteristic discovery timeout")
                self.cancelConnectionAttempt()
                self.updateState(.error("Characteristic discovery timeout"))
                if let completion = self.connectionCompletion {
                    DispatchQueue.main.async {
                    completion(false)
                    }
                    self.connectionCompletion = nil
                }
            }
        }
    }
    
    private func cancelConnectionTimeout() {
        connectionTimeoutTimer?.invalidate()
        connectionTimeoutTimer = nil
    }
    
    private func cancelServiceDiscoveryTimeout() {
        serviceDiscoveryTimeoutTimer?.invalidate()
        serviceDiscoveryTimeoutTimer = nil
    }
    
    private func cancelCharacteristicDiscoveryTimeout() {
        characteristicDiscoveryTimeoutTimer?.invalidate()
        characteristicDiscoveryTimeoutTimer = nil
    }
    
    private func cancelConnectionAttempt() {
        cancelConnectionTimeout()
        cancelServiceDiscoveryTimeout()
        cancelCharacteristicDiscoveryTimeout()
        centralManager.stopScan()
    }
    
    private func saveDeviceUUID(_ uuid: UUID) {
        var knownUUIDs: [String] = userDefaults.stringArray(forKey: knownDevicesKey) ?? []
        let uuidString = uuid.uuidString
        
        if !knownUUIDs.contains(uuidString) {
            knownUUIDs.append(uuidString)
            userDefaults.set(knownUUIDs, forKey: knownDevicesKey)
            print("BLE: Saved device UUID to cache: \(uuidString)")
        }
    }
    
    private var pendingWriteCompletion: ((Result<Void, Error>) -> Void)?
    private var pendingWriteChunks: [Data] = []
    private var currentChunkIndex: Int = 0
    private var writeRetryCount: Int = 0
    private var lastWriteError: Error?
    
    private func sendDataWithRetry(data: Data, peripheral: CBPeripheral, characteristic: CBCharacteristic, retryCount: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        // Verify connection is still active
        guard isConnected() && peripheral.state == .connected else {
            Logger.error("Connection lost before chunking", category: .connection)
            Logger.methodExit("BLE sendData", success: false)
            completion(.failure(PrinterError.notConnected))
            return
        }
        
        let chunkSize = configuration.bleChunkSize
        Logger.info("Chunking data - chunk size: \(chunkSize) bytes, total data: \(data.count) bytes", category: .dataTransmission)
        
        // Use CPCL-aware chunking if needed
        let chunks = chunkData(data, maxChunkSize: chunkSize)
        Logger.info("Data chunked into \(chunks.count) chunks", category: .dataTransmission)
        
        // Validate chunks
        guard !chunks.isEmpty else {
            Logger.error("Chunking produced no chunks", category: .dataTransmission)
            Logger.methodExit("BLE sendData", success: false)
            completion(.failure(PrinterError.sendFailed("Chunking failed")))
            return
        }
        
        for (index, chunk) in chunks.enumerated() {
            Logger.debug("Chunk \(index + 1)/\(chunks.count): \(chunk.count) bytes", category: .dataTransmission)
        }
        
        // Store for async processing
        pendingWriteChunks = chunks
        currentChunkIndex = 0
        writeRetryCount = retryCount
        pendingWriteCompletion = completion
        lastWriteError = nil
        
        Logger.info("Starting to send chunks...", category: .dataTransmission)
        // Start sending chunks
        sendNextChunk(peripheral: peripheral, characteristic: characteristic)
    }
    
    private func sendNextChunk(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        // Verify connection is still active before each chunk
        guard isConnected() && peripheral.state == .connected else {
            Logger.error("Connection lost during chunk transmission at chunk \(currentChunkIndex + 1)", category: .connection)
            Logger.methodExit("BLE sendData", success: false)
            if let completion = pendingWriteCompletion {
                completion(.failure(PrinterError.notConnected))
            }
            pendingWriteCompletion = nil
            pendingWriteChunks = []
            currentChunkIndex = 0
            writeRetryCount = 0
            return
        }
        
        guard currentChunkIndex < pendingWriteChunks.count else {
            // All chunks sent successfully
            let totalChunks = pendingWriteChunks.count
            let totalBytes = pendingWriteChunks.reduce(0) { $0 + $1.count }
            Logger.info("✓ SUCCESS - Sent all \(totalChunks) chunks successfully (\(totalBytes) bytes total)", category: .dataTransmission)
            Logger.methodExit("BLE sendData", success: true)
            if let completion = pendingWriteCompletion {
                completion(.success(()))
            }
            pendingWriteCompletion = nil
            pendingWriteChunks = []
            currentChunkIndex = 0
            writeRetryCount = 0
            return
        }
        
        let chunk = pendingWriteChunks[currentChunkIndex]
        Logger.debug("Sending chunk \(currentChunkIndex + 1)/\(pendingWriteChunks.count) (\(chunk.count) bytes)", category: .dataTransmission)
        
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) 
                ? .withoutResponse 
                : .withResponse
            
        Logger.debug("Write type: \(writeType == .withoutResponse ? "withoutResponse" : "withResponse")", category: .dataTransmission)
        
        if writeType == .withoutResponse {
            // For withoutResponse, we can send immediately and continue
            peripheral.writeValue(chunk, for: characteristic, type: writeType)
            
            // Small delay to avoid overwhelming the connection
            let delay = configuration.bleChunkDelay
            if delay > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.currentChunkIndex += 1
                    self?.sendNextChunk(peripheral: peripheral, characteristic: characteristic)
                }
            } else {
                currentChunkIndex += 1
                sendNextChunk(peripheral: peripheral, characteristic: characteristic)
            }
        } else {
            // For withResponse, we need to wait for the callback
            peripheral.writeValue(chunk, for: characteristic, type: writeType)
            // The didWriteValueFor callback will handle continuation
        }
    }
    
    private func handleWriteError(_ error: Error?, peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        if let error = error {
            lastWriteError = error
        }
        
        // Retry logic
        if writeRetryCount < configuration.maxTransmissionRetries {
            let retryDelay = min(configuration.retryDelayBase * pow(2.0, Double(writeRetryCount)), configuration.maxRetryDelay)
            Logger.info("Retrying chunk \(currentChunkIndex + 1) after \(retryDelay) seconds (attempt \(writeRetryCount + 1))", category: .dataTransmission)
            
            writeRetryCount += 1
            DispatchQueue.global().asyncAfter(deadline: .now() + retryDelay) { [weak self] in
                self?.sendNextChunk(peripheral: peripheral, characteristic: characteristic)
            }
            } else {
                // Max retries exceeded
                Logger.error("❌ FAILED - Max retries (\(configuration.maxTransmissionRetries)) exceeded for chunk \(currentChunkIndex + 1)", category: .dataTransmission)
                Logger.methodExit("BLE sendData", success: false)
                if let completion = pendingWriteCompletion {
                    completion(.failure(PrinterError.transmissionRetryExceeded(configuration.maxTransmissionRetries)))
                }
                pendingWriteCompletion = nil
                pendingWriteChunks = []
                currentChunkIndex = 0
                writeRetryCount = 0
            }
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("BLE: Central Manager powered on")
        case .poweredOff:
            print("BLE: Central Manager powered off")
            updateState(.error("Bluetooth powered off"))
            connectionCompletion?(false)
            connectionCompletion = nil
            cancelConnectionAttempt()
        case .unauthorized:
            print("BLE: Central Manager unauthorized")
            updateState(.error("Bluetooth unauthorized"))
            connectionCompletion?(false)
            connectionCompletion = nil
            cancelConnectionAttempt()
        case .unsupported:
            print("BLE: Central Manager unsupported")
            updateState(.error("Bluetooth unsupported"))
            connectionCompletion?(false)
            connectionCompletion = nil
            cancelConnectionAttempt()
        case .resetting:
            print("BLE: Central Manager resetting")
            updateState(.error("Bluetooth resetting"))
        default:
            break
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Check if this is the device we're looking for
        if connectedPeripheral == nil, let targetAddress = targetAddress {
            print("BLE: Discovered: \(peripheral.name ?? "Unknown") - \(peripheral.identifier.uuidString)")
            
            // Match by UUID
            if peripheral.identifier.uuidString == targetAddress {
                connectedPeripheral = peripheral
                peripheral.delegate = self
                central.stopScan()
                cancelConnectionTimeout()
                central.connect(peripheral, options: nil)
                startConnectionTimeout()
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("BLE: Connected to peripheral: \(peripheral.name ?? "Unknown")")
        isConnectedFlag = true
        discoveredServices = []
        discoveredCharacteristics = []
        
        // Save this device UUID for future retrieval
        saveDeviceUUID(peripheral.identifier)
        
        peripheral.discoverServices(nil)
        startServiceDiscoveryTimeout()
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("BLE: Failed to connect to peripheral: \(error?.localizedDescription ?? "Unknown error")")
        isConnectedFlag = false
        updateState(.error(error?.localizedDescription ?? "Connection failed"))
        connectionCompletion?(false)
        connectionCompletion = nil
        cancelConnectionAttempt()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("BLE: Disconnected from peripheral: \(error?.localizedDescription ?? "No error")")
        isConnectedFlag = false
        connectedPeripheral = nil
        writeCharacteristic = nil
        updateState(.disconnected)
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("BLE: Error discovering services: \(error.localizedDescription)")
            cancelServiceDiscoveryTimeout()
            updateState(.error("Service discovery failed: \(error.localizedDescription)"))
            connectionCompletion?(false)
            connectionCompletion = nil
            cancelConnectionAttempt()
            return
        }
        
        guard let services = peripheral.services, !services.isEmpty else {
            print("BLE: No services discovered")
            cancelServiceDiscoveryTimeout()
            updateState(.error("No services found"))
            connectionCompletion?(false)
            connectionCompletion = nil
            cancelConnectionAttempt()
            return
        }
        
        print("BLE: Discovered \(services.count) services")
        discoveredServices = services
        
        // Discover characteristics for all services
        for service in services {
            print("BLE: Discovering characteristics for service: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
        
        startCharacteristicDiscoveryTimeout()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("BLE: Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else {
            return
        }
        
        print("BLE: Discovered \(characteristics.count) characteristics for service \(service.uuid)")
        discoveredCharacteristics.append(contentsOf: characteristics)
        
        // Find a writable characteristic
        for characteristic in characteristics {
            print("BLE: Characteristic: \(characteristic.uuid) - Properties: \(characteristic.properties)")
            
            if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                print("BLE: Found writable characteristic: \(characteristic.uuid)")
                writeCharacteristic = characteristic
                cancelCharacteristicDiscoveryTimeout()
                cancelServiceDiscoveryTimeout()
                
                // Connection successful
                updateState(.connected)
                isConnectedFlag = true
                
                if let completion = connectionCompletion {
                    DispatchQueue.main.async {
                        completion(true)
                    }
                    connectionCompletion = nil
                }
                return
            }
        }
        
        // Check if we've discovered all characteristics for all services
        if discoveredCharacteristics.count >= discoveredServices.reduce(0, { $0 + ($1.characteristics?.count ?? 0) }) {
            // All characteristics discovered but no writable one found
            if writeCharacteristic == nil {
                print("BLE: No writable characteristic found")
                cancelCharacteristicDiscoveryTimeout()
                cancelServiceDiscoveryTimeout()
                updateState(.error("No writable characteristic found"))
                connectionCompletion?(false)
                connectionCompletion = nil
                cancelConnectionAttempt()
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("BLE: Error writing to characteristic: \(error.localizedDescription)")
            handleWriteError(error, peripheral: peripheral, characteristic: characteristic)
        } else {
            // Write successful, continue with next chunk
            currentChunkIndex += 1
            
            // Small delay before next chunk
            let delay = configuration.bleChunkDelay
            if delay > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.sendNextChunk(peripheral: peripheral, characteristic: characteristic)
                }
            } else {
                sendNextChunk(peripheral: peripheral, characteristic: characteristic)
            }
        }
    }
}
