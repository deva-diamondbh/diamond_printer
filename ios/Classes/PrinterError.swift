import Foundation

/// Printer-related errors with detailed context
enum PrinterError: Error {
    case notConnected
    case sendFailed(String)
    case invalidImage
    case invalidPDF
    case unsupportedLanguage(String)
    case connectionTimeout(String)
    case connectionFailed(String)
    case serviceDiscoveryFailed(String)
    case characteristicDiscoveryFailed(String)
    case invalidAddress(String)
    case bluetoothUnavailable(String)
    case networkUnavailable(String)
    case transmissionRetryExceeded(Int)
    case connectionRetryExceeded(Int)
    case invalidConfiguration(String)
    case imageProcessingFailed(String)
    case memoryError(String)
    
    var localizedDescription: String {
        switch self {
        case .notConnected:
            return "Not connected to a printer"
        case .sendFailed(let message):
            return "Send failed: \(message)"
        case .invalidImage:
            return "Invalid image data"
        case .invalidPDF:
            return "Invalid PDF file"
        case .unsupportedLanguage(let language):
            return "Unsupported printer language: \(language)"
        case .connectionTimeout(let details):
            return "Connection timeout: \(details)"
        case .connectionFailed(let details):
            return "Connection failed: \(details)"
        case .serviceDiscoveryFailed(let details):
            return "Service discovery failed: \(details)"
        case .characteristicDiscoveryFailed(let details):
            return "Characteristic discovery failed: \(details)"
        case .invalidAddress(let address):
            return "Invalid address format: \(address)"
        case .bluetoothUnavailable(let reason):
            return "Bluetooth unavailable: \(reason)"
        case .networkUnavailable(let reason):
            return "Network unavailable: \(reason)"
        case .transmissionRetryExceeded(let count):
            return "Transmission failed after \(count) retry attempts"
        case .connectionRetryExceeded(let count):
            return "Connection failed after \(count) retry attempts"
        case .invalidConfiguration(let details):
            return "Invalid configuration: \(details)"
        case .imageProcessingFailed(let details):
            return "Image processing failed: \(details)"
        case .memoryError(let details):
            return "Memory error: \(details)"
        }
    }
    
    /// Error code for Flutter error reporting
    var errorCode: String {
        switch self {
        case .notConnected:
            return "NOT_CONNECTED"
        case .sendFailed:
            return "SEND_FAILED"
        case .invalidImage:
            return "INVALID_IMAGE"
        case .invalidPDF:
            return "INVALID_PDF"
        case .unsupportedLanguage:
            return "UNSUPPORTED_LANGUAGE"
        case .connectionTimeout:
            return "CONNECTION_TIMEOUT"
        case .connectionFailed:
            return "CONNECTION_FAILED"
        case .serviceDiscoveryFailed:
            return "SERVICE_DISCOVERY_FAILED"
        case .characteristicDiscoveryFailed:
            return "CHARACTERISTIC_DISCOVERY_FAILED"
        case .invalidAddress:
            return "INVALID_ADDRESS"
        case .bluetoothUnavailable:
            return "BLUETOOTH_UNAVAILABLE"
        case .networkUnavailable:
            return "NETWORK_UNAVAILABLE"
        case .transmissionRetryExceeded:
            return "TRANSMISSION_RETRY_EXCEEDED"
        case .connectionRetryExceeded:
            return "CONNECTION_RETRY_EXCEEDED"
        case .invalidConfiguration:
            return "INVALID_CONFIGURATION"
        case .imageProcessingFailed:
            return "IMAGE_PROCESSING_FAILED"
        case .memoryError:
            return "MEMORY_ERROR"
        }
    }
}

