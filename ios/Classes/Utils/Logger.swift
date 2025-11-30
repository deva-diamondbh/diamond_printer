import Foundation
import os.log

/// Centralized logging utility for better Xcode console visibility
class Logger {
    private static let subsystem = "com.diamond.printer"
    
    // Create separate log categories for better filtering
    private static let general = OSLog(subsystem: subsystem, category: "General")
    private static let connection = OSLog(subsystem: subsystem, category: "Connection")
    private static let imageProcessing = OSLog(subsystem: subsystem, category: "ImageProcessing")
    private static let commandGeneration = OSLog(subsystem: subsystem, category: "CommandGeneration")
    private static let dataTransmission = OSLog(subsystem: subsystem, category: "DataTransmission")
    
    enum LogLevel {
        case debug
        case info
        case error
    }
    
    /// Log a debug message (most verbose)
    static func debug(_ message: String, category: Category = .general) {
        let log = getLog(for: category)
        os_log("%{public}@", log: log, type: .debug, message)
        // Also print for immediate console visibility
        print("[DEBUG] \(message)")
    }
    
    /// Log an info message (normal operation)
    static func info(_ message: String, category: Category = .general) {
        let log = getLog(for: category)
        os_log("%{public}@", log: log, type: .info, message)
        print("[INFO] \(message)")
    }
    
    /// Log an error message (critical issues)
    static func error(_ message: String, category: Category = .general) {
        let log = getLog(for: category)
        os_log("%{public}@", log: log, type: .error, message)
        print("[ERROR] \(message)")
    }
    
    /// Log with custom level
    static func log(_ message: String, level: LogLevel = .info, category: Category = .general) {
        switch level {
        case .debug:
            debug(message, category: category)
        case .info:
            info(message, category: category)
        case .error:
            error(message, category: category)
        }
    }
    
    enum Category {
        case general
        case connection
        case imageProcessing
        case commandGeneration
        case dataTransmission
    }
    
    private static func getLog(for category: Category) -> OSLog {
        switch category {
        case .general:
            return general
        case .connection:
            return connection
        case .imageProcessing:
            return imageProcessing
        case .commandGeneration:
            return commandGeneration
        case .dataTransmission:
            return dataTransmission
        }
    }
    
    /// Log method entry/exit for debugging
    static func methodEntry(_ methodName: String, category: Category = .general) {
        debug("=== \(methodName): START ===", category: category)
    }
    
    /// Log method exit
    static func methodExit(_ methodName: String, success: Bool = true, category: Category = .general) {
        let status = success ? "END (SUCCESS)" : "END (FAILED)"
        debug("=== \(methodName): \(status) ===", category: category)
    }
}

