import Foundation

/// Represents the connection state of a printer
public enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case error(String)
    
    /// Returns true if the connection is active
    public var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
    
    /// Returns true if the connection is in progress
    public var isConnecting: Bool {
        if case .connecting = self {
            return true
        }
        return false
    }
    
    /// Returns the error message if in error state
    public var errorMessage: String? {
        if case .error(let message) = self {
            return message
        }
        return nil
    }
}

