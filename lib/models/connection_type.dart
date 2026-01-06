/// Connection types for printer communication.
///
/// Printers can be connected via different methods, each with its own
/// characteristics and use cases. This class provides constants and utilities
/// for working with connection types.
///
/// Example:
/// ```dart
/// // Connect via Bluetooth
/// await printer.connect(address, type: ConnectionType.bluetooth);
///
/// // Connect via WiFi
/// await printer.connect(ipAddress, type: ConnectionType.wifi);
///
/// // Check if connection type is supported
/// if (ConnectionType.isSupported('bluetooth')) {
///   // Connect...
/// }
/// ```
class ConnectionType {
  /// Bluetooth connection.
  ///
  /// Used for wireless connection to nearby printers. Requires:
  /// - Bluetooth to be enabled on the device
  /// - Printer to be paired (on some platforms)
  /// - Appropriate permissions (location on Android, Bluetooth on iOS)
  ///
  /// Address format: MAC address (e.g., "00:11:22:33:44:55")
  ///
  /// Best for: Mobile printers, portable devices, close-range printing.
  static const String bluetooth = 'bluetooth';

  /// WiFi/Network connection.
  ///
  /// Used for network-connected printers on the same network. Requires:
  /// - Printer and device on the same network
  /// - Printer IP address or hostname
  /// - Network connectivity
  ///
  /// Address format: IP address (e.g., "192.168.1.100") or hostname
  ///
  /// Best for: Fixed printers, office environments, high-volume printing.
  static const String wifi = 'wifi';

  /// USB connection.
  ///
  /// Direct wired connection via USB. Requires:
  /// - USB cable connection
  /// - USB host mode support (on Android)
  /// - Appropriate USB permissions
  ///
  /// Address format: USB device identifier (platform-specific)
  ///
  /// Best for: Desktop applications, reliable connections, high-speed printing.
  ///
  /// Note: USB support may vary by platform and requires additional setup.
  static const String usb = 'usb';

  /// All supported connection types.
  ///
  /// Returns a list of all connection type constants: [bluetooth, wifi, usb].
  static const List<String> all = [bluetooth, wifi, usb];

  /// Checks if a connection type string is supported.
  ///
  /// Performs case-insensitive comparison against all supported connection types.
  ///
  /// [type] - The connection type string to check (e.g., 'bluetooth', 'WiFi').
  ///
  /// Returns `true` if the connection type is supported, `false` otherwise.
  ///
  /// Example:
  /// ```dart
  /// ConnectionType.isSupported('bluetooth'); // true
  /// ConnectionType.isSupported('WiFi'); // true (case-insensitive)
  /// ConnectionType.isSupported('ethernet'); // false
  /// ```
  static bool isSupported(String type) {
    return all.contains(type.toLowerCase());
  }
}
