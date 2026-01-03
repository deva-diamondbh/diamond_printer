import Foundation
import CoreBluetooth

/// CoreBluetooth scanner for discovering Bluetooth LE devices
/// This will trigger the Bluetooth permission dialog on iOS
class CoreBluetoothScanner: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    private var centralManager: CBCentralManager!
    private var discoveredPeripherals: [CBPeripheral] = []
    private var scanCompletion: (([[String: String]]) -> Void)?
    private var scanTimer: Timer?
    
    // Cache of previously seen device UUIDs
    private static var knownDeviceUUIDs: [UUID] = []
    private let userDefaults = UserDefaults.standard
    private let knownDevicesKey = "com.diamond.printer.knownDevices"
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        loadKnownDevices()
    }
    
    /// Load previously seen device UUIDs from storage
    private func loadKnownDevices() {
        if let uuidStrings = userDefaults.stringArray(forKey: knownDevicesKey) {
            CoreBluetoothScanner.knownDeviceUUIDs = uuidStrings.compactMap { UUID(uuidString: $0) }
            print("Loaded \(CoreBluetoothScanner.knownDeviceUUIDs.count) known device UUIDs")
        }
    }
    
    /// Save device UUID for future retrieval
    private func saveDeviceUUID(_ uuid: UUID) {
        if !CoreBluetoothScanner.knownDeviceUUIDs.contains(uuid) {
            CoreBluetoothScanner.knownDeviceUUIDs.append(uuid)
            let uuidStrings = CoreBluetoothScanner.knownDeviceUUIDs.map { $0.uuidString }
            userDefaults.set(uuidStrings, forKey: knownDevicesKey)
            print("Saved device UUID: \(uuid.uuidString)")
        }
    }
    
    /// Start scanning for Bluetooth devices
    func startScanning(timeout: TimeInterval = 15.0, completion: @escaping ([[String: String]]) -> Void) {
        self.scanCompletion = completion
        self.discoveredPeripherals.removeAll()
        
        // Check if Bluetooth is ready
        if centralManager.state == .poweredOn {
            // 1. Retrieve currently connected peripherals
            let connectedPeripherals = centralManager.retrieveConnectedPeripherals(withServices: [])
            print("Found \(connectedPeripherals.count) currently connected peripherals")
            discoveredPeripherals.append(contentsOf: connectedPeripherals)
            
            // 2. Retrieve known peripherals from cache
            if !CoreBluetoothScanner.knownDeviceUUIDs.isEmpty {
                let knownPeripherals = centralManager.retrievePeripherals(withIdentifiers: CoreBluetoothScanner.knownDeviceUUIDs)
                print("Retrieved \(knownPeripherals.count) known peripherals from cache")
                for peripheral in knownPeripherals {
                    if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
                        discoveredPeripherals.append(peripheral)
                    }
                }
            }
            
            // 3. Start active scanning for more devices
            beginScanning(timeout: timeout)
        } else {
            // Will start scanning once Bluetooth is powered on (in centralManagerDidUpdateState)
            print("Waiting for Bluetooth to power on...")
        }
    }
    
    private func beginScanning(timeout: TimeInterval) {
        print("Starting Bluetooth scan...")
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        
        // Stop scanning after timeout
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.stopScanning()
        }
    }
    
    func stopScanning() {
        print("Stopping Bluetooth scan...")
        centralManager.stopScan()
        scanTimer?.invalidate()
        scanTimer = nil
        
        // Include all discovered devices (even without names, as some printers don't advertise names)
        // Use device name if available, otherwise use UUID prefix as fallback
        let devices = discoveredPeripherals
            .map { peripheral -> [String: String] in
                // Use peripheral name if available, otherwise use a descriptive default
                let deviceName: String
                if let name = peripheral.name, !name.isEmpty {
                    deviceName = name
                } else {
                    // Use UUID prefix as fallback name for devices without advertised names
                    let uuidString = peripheral.identifier.uuidString
                    let uuidPrefix = String(uuidString.prefix(8))
                    deviceName = "Bluetooth Device (\(uuidPrefix))"
                }
                
                return [
                    "name": deviceName,
                    "address": peripheral.identifier.uuidString,
                    "type": "bluetooth"
                ]
            }
        
        print("Returning \(devices.count) devices (from \(discoveredPeripherals.count) total discovered)")
        scanCompletion?(devices)
        scanCompletion = nil
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown:
            print("Bluetooth state: unknown")
        case .resetting:
            print("Bluetooth state: resetting")
        case .unsupported:
            print("Bluetooth state: unsupported")
            scanCompletion?([])
            scanCompletion = nil
        case .unauthorized:
            print("Bluetooth state: unauthorized")
            scanCompletion?([])
            scanCompletion = nil
        case .poweredOff:
            print("Bluetooth state: powered off")
            scanCompletion?([])
            scanCompletion = nil
        case .poweredOn:
            print("Bluetooth state: powered on")
            // Start scanning if we were waiting for Bluetooth to power on
            if scanCompletion != nil {
                // 1. Retrieve connected peripherals
                let connectedPeripherals = centralManager.retrieveConnectedPeripherals(withServices: [])
                print("Found \(connectedPeripherals.count) already connected peripherals")
                discoveredPeripherals.append(contentsOf: connectedPeripherals)
                
                // 2. Retrieve known peripherals from cache
                if !CoreBluetoothScanner.knownDeviceUUIDs.isEmpty {
                    let knownPeripherals = centralManager.retrievePeripherals(withIdentifiers: CoreBluetoothScanner.knownDeviceUUIDs)
                    print("Retrieved \(knownPeripherals.count) known peripherals from cache")
                    for peripheral in knownPeripherals {
                        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
                            discoveredPeripherals.append(peripheral)
                        }
                    }
                }
                
                // 3. Start active scanning
                beginScanning(timeout: 15.0)
            }
        @unknown default:
            print("Bluetooth state: unknown default")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Add all devices (even without names, as some printers don't advertise names)
        // We'll filter by name later if needed
        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            let deviceName = peripheral.name ?? "Unknown Device"
            print("Discovered: \(deviceName) - \(peripheral.identifier.uuidString) - RSSI: \(RSSI)")
            discoveredPeripherals.append(peripheral)
            
            // Save this device UUID for future retrieval
            saveDeviceUUID(peripheral.identifier)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to peripheral: \(peripheral.name ?? "Unknown")")
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to peripheral: \(error?.localizedDescription ?? "Unknown error")")
    }
}

