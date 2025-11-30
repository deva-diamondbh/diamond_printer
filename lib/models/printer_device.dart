/// Represents a discovered printer device
class PrinterDevice {
  /// Device name (e.g., "POS-58", "Zebra ZD220")
  final String name;
  
  /// Device address (MAC address for Bluetooth, IP address for WiFi)
  final String address;
  
  /// Connection type: 'bluetooth' or 'wifi'
  final String type;
  
  /// Additional device information (optional)
  final Map<String, dynamic>? additionalInfo;
  
  PrinterDevice({
    required this.name,
    required this.address,
    required this.type,
    this.additionalInfo,
  });
  
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

