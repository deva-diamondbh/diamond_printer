/// Connection types for printers
class ConnectionType {
  static const String bluetooth = 'bluetooth';
  static const String wifi = 'wifi';
  static const String usb = 'usb';
  
  /// All supported connection types
  static const List<String> all = [bluetooth, wifi, usb];
  
  /// Check if a connection type is supported
  static bool isSupported(String type) {
    return all.contains(type.toLowerCase());
  }
}

