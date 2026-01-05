import Flutter
import UIKit
import PDFKit

public class DiamondPrinterPlugin: NSObject, FlutterPlugin {
    
    private var connectionManager: ConnectionManager?
    private let bluetoothManager = BluetoothConnectionManager() // External Accessory (MFi)
    private let bleManager = BLEConnectionManager() // CoreBluetooth (BLE)
    private let bluetoothScanner = CoreBluetoothScanner()
    private var wifiManager: WiFiConnectionManager?
    private var lastConnectionType: String = "bluetooth" // Track which type we used
    private var configuration: PrinterConfiguration = .default
    
    /// Current connection state
    public var connectionState: ConnectionState {
        return connectionManager?.state ?? .disconnected
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "diamond_printer", binaryMessenger: registrar.messenger())
        let instance = DiamondPrinterPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
            
        case "scanPrinters":
            handleScanPrinters(call, result: result)
            
        case "connect":
            handleConnect(call, result: result)
            
        case "disconnect":
            handleDisconnect(result: result)
            
        case "isConnected":
            result(connectionManager?.isConnected() ?? false)
            
        case "getConnectionState":
            let state = connectionState
            result(state.isConnected ? "connected" : (state.isConnecting ? "connecting" : "disconnected"))
            
        case "printText":
            handlePrintText(call, result: result)
            
        case "printImage":
            handlePrintImage(call, result: result)
            
        case "printPdf":
            handlePrintPdf(call, result: result)
            
        case "sendRawData":
            handleSendRawData(call, result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func handleScanPrinters(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let scanBluetooth = args["bluetooth"] as? Bool else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
            return
        }
        
        if scanBluetooth {
            // Use CoreBluetooth to scan - this will trigger the permission dialog
            bluetoothScanner.startScanning(timeout: 15.0) { [weak self] discoveredDevices in
                guard let self = self else {
                    result([])
                    return
                }
                
                // Also include all available MFi accessories (paired in Settings)
                let mfiDevices = self.bluetoothManager.getAllAvailableDevices()
                print("MFi devices found: \(mfiDevices.count)")
                
                // Combine both lists and remove duplicates
                var allDevices = discoveredDevices
                for mfiDevice in mfiDevices {
                    // Check by both address and name to avoid duplicates
                    let isDuplicate = allDevices.contains { device in
                        device["address"] == mfiDevice["address"] ||
                        (device["name"] == mfiDevice["name"] && device["name"] != "Unknown")
                    }
                    
                    if !isDuplicate {
                        print("Adding MFi device: \(mfiDevice["name"] ?? "Unknown")")
                        allDevices.append(mfiDevice)
                    }
                }
                
                print("Total devices found: \(allDevices.count) (BLE: \(discoveredDevices.count), MFi: \(mfiDevices.count))")
                result(allDevices)
            }
        } else {
            result([])
        }
    }
    
    private func handleConnect(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let address = args["address"] as? String,
              let type = args["type"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
            return
        }
        
        // Disconnect existing connection
        connectionManager?.disconnect()
        
        // Apply configuration to managers
        bleManager.configuration = configuration
        bluetoothManager.configuration = configuration
        
        switch type.lowercased() {
        case "bluetooth":
            lastConnectionType = "bluetooth"
            
            // Try BLE connection first (for CoreBluetooth devices)
            print("Attempting BLE connection to: \(address)")
            connectionManager = bleManager
            bleManager.connect(address: address) { [weak self] success in
                guard let self = self else {
                    result(false)
                    return
                }
                
                if success {
                    print("BLE connection successful")
                    result(true)
                } else {
                    // If BLE fails, try External Accessory (MFi devices)
                    print("BLE connection failed, trying External Accessory (MFi)")
                    self.connectionManager = self.bluetoothManager
                    self.bluetoothManager.connect(address: address) { mfiSuccess in
                        if mfiSuccess {
                            print("MFi connection successful")
                        } else {
                            print("MFi connection failed")
                        }
                        result(mfiSuccess)
                    }
                }
            }
            
        case "wifi":
            lastConnectionType = "wifi"
            if #available(iOS 12.0, *) {
                if wifiManager == nil {
                    wifiManager = WiFiConnectionManager()
                }
                wifiManager?.configuration = configuration
                connectionManager = wifiManager
                wifiManager?.connect(address: address) { success in
                    result(success)
                }
            } else {
                result(FlutterError(code: "UNSUPPORTED", message: "WiFi printing requires iOS 12+", details: nil))
                return
            }
            
        default:
            result(FlutterError(code: "INVALID_TYPE", message: "Unsupported connection type: \(type)", details: nil))
            return
        }
    }
    
    private func handleDisconnect(result: @escaping FlutterResult) {
        connectionManager?.disconnect()
        connectionManager = nil
        result(nil)
    }
    
    private func handlePrintText(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let text = args["text"] as? String,
              let language = args["language"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
            return
        }
        
        guard connectionManager?.isConnected() == true else {
            result(FlutterError(code: "NOT_CONNECTED", message: "Not connected to a printer", details: nil))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let connectionManager = self.connectionManager else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "NOT_CONNECTED", message: "Not connected to a printer", details: nil))
                }
                return
            }
            
            let generator = self.getCommandGenerator(language)
            let command = generator.generateTextCommand(text)
            
            connectionManager.sendData(command) { sendResult in
                DispatchQueue.main.async {
                    switch sendResult {
                    case .success:
                        result(nil)
                    case .failure(let error):
                        let printerError = error as? PrinterError
                        let errorCode = printerError?.errorCode ?? "PRINT_ERROR"
                        result(FlutterError(code: errorCode, message: error.localizedDescription, details: nil))
                    }
                }
            }
        }
    }
    
    private func handlePrintImage(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        Logger.methodEntry("handlePrintImage", category: .general)
        
        // Validate arguments
        guard let args = call.arguments as? [String: Any] else {
            Logger.error("Invalid arguments - args is nil or not a dictionary", category: .general)
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
            return
        }
        
        guard let imageData = (args["imageBytes"] as? FlutterStandardTypedData)?.data else {
            Logger.error("imageBytes is missing or invalid", category: .general)
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Image bytes missing", details: nil))
            return
        }
        
        guard let language = args["language"] as? String else {
            Logger.error("language parameter is missing", category: .general)
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Language parameter missing", details: nil))
            return
        }
        
        Logger.info("Language = '\(language)', Image data size = \(imageData.count) bytes", category: .general)
        
        // Validate connection before processing
        guard let connectionManager = self.connectionManager else {
            Logger.error("Connection manager is nil", category: .connection)
            result(FlutterError(code: "NOT_CONNECTED", message: "Not connected to a printer", details: nil))
            return
        }
        
        guard connectionManager.isConnected() else {
            let state = connectionManager.state
            Logger.error("Not connected to printer. Connection state: \(state)", category: .connection)
            result(FlutterError(code: "NOT_CONNECTED", message: "Not connected to a printer. State: \(state)", details: nil))
            return
        }
        
        Logger.info("Connection verified - Type: \(type(of: connectionManager))", category: .connection)
        
        // Decode image with error handling
        guard let image = UIImage(data: imageData) else {
            Logger.error("Failed to decode image from \(imageData.count) bytes of data", category: .imageProcessing)
            result(FlutterError(code: "INVALID_IMAGE", message: "Failed to decode image data", details: nil))
            return
        }
        
        Logger.info("Image decoded successfully - Size: \(Int(image.size.width))x\(Int(image.size.height))", category: .imageProcessing)
        
        // Extract config and calculate maxImageWidth
        let configMap = args["config"] as? [String: Any]
        let paperWidthDots = (configMap?["paperWidthDots"] as? Int) ?? 576
        let maxImageWidth = paperWidthDots // Use full width for edge-to-edge printing
        
        Logger.info("Paper width = \(paperWidthDots) dots, Max image width = \(maxImageWidth) dots", category: .imageProcessing)
        
        // Process image on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                Logger.error("Self is nil in async block", category: .general)
                DispatchQueue.main.async {
                    result(FlutterError(code: "ERROR", message: "Manager deallocated", details: nil))
                }
                return
            }
            
            // Verify connection is still active
            guard connectionManager.isConnected() else {
                Logger.error("Connection lost during image processing", category: .connection)
                DispatchQueue.main.async {
                    result(FlutterError(code: "NOT_CONNECTED", message: "Connection lost during processing", details: nil))
                }
                return
            }
            
            do {
                Logger.info("Getting command generator for language '\(language)'", category: .commandGeneration)
                let generator = self.getCommandGenerator(language)
                Logger.info("Command generator type = \(type(of: generator))", category: .commandGeneration)
                
                Logger.info("Generating image command...", category: .commandGeneration)
                let command = generator.generateImageCommand(image, maxWidth: maxImageWidth)
                
                // Validate command
                guard command.count > 0 else {
                    Logger.error("Generated command is empty", category: .commandGeneration)
                    DispatchQueue.main.async {
                        result(FlutterError(code: "COMMAND_GENERATION_FAILED", message: "Generated command is empty", details: nil))
                    }
                    return
                }
                
                Logger.info("Command generated - Size: \(command.count) bytes", category: .commandGeneration)
                
                // Log command preview for debugging
                if command.count > 0 {
                    let previewSize = min(200, command.count)
                    let preview = command.prefix(previewSize)
                    if let previewString = String(data: preview, encoding: .utf8) {
                        Logger.debug("Command preview (first \(previewSize) bytes): \(previewString)", category: .commandGeneration)
                    } else {
                        Logger.debug("Command preview (first \(previewSize) bytes): [Binary data]", category: .commandGeneration)
                    }
                }
                
                // Verify connection one more time before sending
                guard connectionManager.isConnected() else {
                    Logger.error("Connection lost before sending data", category: .connection)
                    DispatchQueue.main.async {
                        result(FlutterError(code: "NOT_CONNECTED", message: "Connection lost before sending", details: nil))
                    }
                    return
                }
                
                Logger.info("Sending data to connection manager...", category: .dataTransmission)
                connectionManager.sendData(command) { sendResult in
                    DispatchQueue.main.async {
                        switch sendResult {
                        case .success:
                            Logger.info("SUCCESS - Data sent successfully", category: .dataTransmission)
                            Logger.methodExit("handlePrintImage", success: true)
                            result(nil)
                        case .failure(let error):
                            let printerError = error as? PrinterError
                            let errorCode = printerError?.errorCode ?? "PRINT_ERROR"
                            let errorMessage = error.localizedDescription
                            Logger.error("FAILED - Error code: \(errorCode), Message: \(errorMessage)", category: .dataTransmission)
                            if let printerError = printerError {
                                Logger.error("PrinterError details: \(String(describing: printerError))", category: .dataTransmission)
                            }
                            Logger.methodExit("handlePrintImage", success: false)
                            result(FlutterError(code: errorCode, message: errorMessage, details: ["originalError": error.localizedDescription]))
                        }
                    }
                }
            } catch {
                Logger.error("Exception during image processing: \(error.localizedDescription)", category: .imageProcessing)
                DispatchQueue.main.async {
                    result(FlutterError(code: "IMAGE_PROCESSING_ERROR", message: error.localizedDescription, details: ["error": String(describing: error)]))
                }
            }
        }
    }
    
    private func handlePrintPdf(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let filePath = args["filePath"] as? String,
              let language = args["language"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
            return
        }
        
        guard connectionManager?.isConnected() == true else {
            result(FlutterError(code: "NOT_CONNECTED", message: "Not connected to a printer", details: nil))
            return
        }
        
        guard #available(iOS 11.0, *) else {
            result(FlutterError(code: "UNSUPPORTED", message: "PDF printing requires iOS 11+", details: nil))
            return
        }
        
        let fileURL = URL(fileURLWithPath: filePath)
        guard let pdfDocument = PDFDocument(url: fileURL) else {
            result(FlutterError(code: "INVALID_PDF", message: "Failed to load PDF", details: nil))
            return
        }
        
        // Extract config and calculate maxImageWidth (default to 576)
        let configMap = args["config"] as? [String: Any]
        let paperWidthDots = (configMap?["paperWidthDots"] as? Int) ?? 576
        let maxImageWidth = paperWidthDots // Use full width for edge-to-edge printing
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let connectionManager = self.connectionManager else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "NOT_CONNECTED", message: "Not connected to a printer", details: nil))
                }
                return
            }
            
            let generator = self.getCommandGenerator(language)
            self.printPdfPages(pdfDocument: pdfDocument, generator: generator, maxImageWidth: maxImageWidth, connectionManager: connectionManager, pageIndex: 0, result: result)
        }
    }
    
    private func printPdfPages(pdfDocument: PDFDocument, generator: PrinterCommandGenerator, maxImageWidth: Int, connectionManager: ConnectionManager, pageIndex: Int, result: @escaping FlutterResult) {
        guard pageIndex < pdfDocument.pageCount else {
            DispatchQueue.main.async {
                result(nil)
            }
            return
        }
        
        guard let page = pdfDocument.page(at: pageIndex) else {
            printPdfPages(pdfDocument: pdfDocument, generator: generator, maxImageWidth: maxImageWidth, connectionManager: connectionManager, pageIndex: pageIndex + 1, result: result)
            return
        }
        
        let pageRect = page.bounds(for: .mediaBox)
        let renderer = UIGraphicsImageRenderer(size: pageRect.size)
        
        let image = renderer.image { context in
            UIColor.white.set()
            context.fill(pageRect)
            context.cgContext.translateBy(x: 0, y: pageRect.size.height)
            context.cgContext.scaleBy(x: 1.0, y: -1.0)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        
        let command = generator.generateImageCommand(image, maxWidth: maxImageWidth)
        
        connectionManager.sendData(command) { [weak self] sendResult in
            guard let self = self else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "ERROR", message: "Manager deallocated", details: nil))
                }
                return
            }
            
            switch sendResult {
            case .success:
                // Send feed command between pages (except after last page)
                if pageIndex < pdfDocument.pageCount - 1 {
                    let feedCommand = generator.generateFeedCommand(lines: 3)
                    connectionManager.sendData(feedCommand) { feedResult in
                        switch feedResult {
                        case .success:
                            self.printPdfPages(pdfDocument: pdfDocument, generator: generator, maxImageWidth: maxImageWidth, connectionManager: connectionManager, pageIndex: pageIndex + 1, result: result)
                        case .failure(let error):
                            let printerError = error as? PrinterError
                            let errorCode = printerError?.errorCode ?? "PRINT_ERROR"
                            DispatchQueue.main.async {
                                result(FlutterError(code: errorCode, message: error.localizedDescription, details: nil))
                            }
                        }
                    }
                } else {
                    // Last page printed successfully
                    DispatchQueue.main.async {
                        result(nil)
                    }
                }
                
            case .failure(let error):
                let printerError = error as? PrinterError
                let errorCode = printerError?.errorCode ?? "PRINT_ERROR"
                DispatchQueue.main.async {
                    result(FlutterError(code: errorCode, message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func handleSendRawData(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let rawData = (args["rawBytes"] as? FlutterStandardTypedData)?.data else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid arguments", details: nil))
            return
        }
        
        guard connectionManager?.isConnected() == true else {
            result(FlutterError(code: "NOT_CONNECTED", message: "Not connected to a printer", details: nil))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let connectionManager = self.connectionManager else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "NOT_CONNECTED", message: "Not connected to a printer", details: nil))
                }
                return
            }
            
            connectionManager.sendData(rawData) { sendResult in
                DispatchQueue.main.async {
                    switch sendResult {
                    case .success:
                        result(nil)
                    case .failure(let error):
                        let printerError = error as? PrinterError
                        let errorCode = printerError?.errorCode ?? "SEND_ERROR"
                        result(FlutterError(code: errorCode, message: error.localizedDescription, details: nil))
                    }
                }
            }
        }
    }
    
    private func getCommandGenerator(_ language: String) -> PrinterCommandGenerator {
        switch language.lowercased() {
        case "escpos", "eos":
            return ESCPOSCommandGenerator()
        case "cpcl":
            return CPCLCommandGenerator()
        case "zpl":
            return ZPLCommandGenerator()
        default:
            return ESCPOSCommandGenerator()
        }
    }
}
