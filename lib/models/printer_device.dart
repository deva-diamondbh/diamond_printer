/// Represents a discovered printer device.
///
/// This class encapsulates information about a printer discovered during scanning,
/// including its name, address, connection type, and optional additional metadata.
///
/// Example:
/// ```dart
/// // Discovered during scanning
/// final devices = await printer.scanPrinters();
/// for (final device in devices) {
///   print('Found: ${device.name} at ${device.address}');
/// }
///
/// // Connect to a discovered device
/// await printer.connect(device.address, type: device.type);
/// ```
class PrinterDevice {
  /// Device name or model identifier.
  ///
  /// Examples: "POS-58", "Zebra ZD220", "Epson TM-T88".
  final String name;

  /// Device address for connection.
  ///
  /// - For Bluetooth: MAC address (e.g., "00:11:22:33:44:55")
  /// - For WiFi: IP address (e.g., "192.168.1.100")
  final String address;

  /// Connection type identifier.
  ///
  /// Valid values: 'bluetooth', 'wifi', or 'usb'.
  /// Use [ConnectionType] constants for type-safe values.
  final String type;

  /// Additional device information (optional).
  ///
  /// May contain platform-specific metadata such as signal strength,
  /// manufacturer information, or other discovery details.
  final Map<String, dynamic>? additionalInfo;

  /// Creates a printer device instance.
  ///
  /// [name] - Device name or model identifier.
  /// [address] - Device address (MAC for Bluetooth, IP for WiFi).
  /// [type] - Connection type ('bluetooth', 'wifi', or 'usb').
  /// [additionalInfo] - Optional additional device metadata.
  PrinterDevice({
    required this.name,
    required this.address,
    required this.type,
    this.additionalInfo,
  });

  /// Creates a [PrinterDevice] from a map (typically from platform channel).
  ///
  /// This factory constructor is used internally to deserialize device
  /// information received from the native platform.
  ///
  /// [map] - Map containing device information with keys:
  ///   - `name`: Device name (optional, defaults to 'Unknown Device')
  ///   - `address`: Device address (required)
  ///   - `type`: Connection type (required)
  ///   - `additionalInfo`: Optional map of additional metadata
  ///
  /// Example:
  /// ```dart
  /// final device = PrinterDevice.fromMap({
  ///   'name': 'My Printer',
  ///   'address': '00:11:22:33:44:55',
  ///   'type': 'bluetooth',
  /// });
  /// ```
  factory PrinterDevice.fromMap(Map<dynamic, dynamic> map) {
    return PrinterDevice(
      name: map['name'] as String? ?? 'Unknown Device',
      address: map['address'] as String,
      type: map['type'] as String,
      additionalInfo: map['additionalInfo'] != null
          ? Map<String, dynamic>.from(map['additionalInfo'] as Map)
          : null,
    );
  }

  /// Converts the device to a map for serialization.
  ///
  /// Returns a map containing all device information, suitable for
  /// platform channel communication or storage.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
      'type': type,
      if (additionalInfo != null) 'additionalInfo': additionalInfo,
    };
  }

  @override
  String toString() {
    return 'PrinterDevice(name: $name, address: $address, type: $type)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PrinterDevice &&
        other.name == name &&
        other.address == address &&
        other.type == type;
  }

  @override
  int get hashCode => Object.hash(name, address, type);
}
