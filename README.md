# diamond_printer

[![pub package](https://img.shields.io/pub/v/diamond_printer.svg)](https://pub.dev/packages/diamond_printer)

Advanced printer plugin for Flutter with ESC/POS, CPCL, ZPL, and EOS support for thermal and label printers via Bluetooth, WiFi, and USB connections.

## Features

- 🖨️ **Multiple Printer Languages**: Support for ESC/POS, CPCL, ZPL, and EOS
- 📱 **Multiple Connection Types**: Bluetooth, WiFi, and USB
- 🖼️ **Image Printing**: Automatic image resizing and monochrome conversion
- 📄 **PDF Printing**: Print multi-page PDF documents
- ✂️ **Auto-Cut**: Automatic paper cutting after print jobs
- 📏 **Configurable Paper Sizes**: Support for 58mm, 80mm, 100mm, and custom sizes
- 🔧 **Raw Command Support**: Send custom printer commands for advanced control
- 🎯 **Smart Image Resizing**: Automatically resizes images to fit paper width
- 🔌 **Cross-Platform**: Works on both Android and iOS

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  diamond_printer: ^0.0.1
```

Then run:

```bash
flutter pub get
```

## Platform Setup

### Android

The plugin automatically adds required permissions to your `AndroidManifest.xml`. However, you may need to request runtime permissions for Bluetooth scanning.

**Required Permissions** (automatically added):
- `BLUETOOTH` / `BLUETOOTH_CONNECT` (for Bluetooth printing)
- `BLUETOOTH_SCAN` (for Bluetooth device discovery on Android 12+)
- `ACCESS_FINE_LOCATION` (for Bluetooth discovery on Android 6-11)
- `INTERNET` (for WiFi printing)
- `ACCESS_NETWORK_STATE` (for WiFi printing)

**Note**: On Android 6.0+, location permission is required for Bluetooth device discovery. The plugin will automatically request these permissions when scanning for printers.

### iOS

Add the following to your `Info.plist` file:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app needs Bluetooth access to connect to printers</string>
<key>NSBluetoothWhileUsingUsageDescription</key>
<string>This app needs Bluetooth access to connect to printers</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app needs Bluetooth access to connect to printers</string>
```

For MFi (Made for iPhone) printers, add the supported protocols:

```xml
<key>UISupportedExternalAccessoryProtocols</key>
<array>
    <string>com.zebra.rawport</string>
</array>
```

## Quick Start

```dart
import 'package:diamond_printer/diamond_printer.dart';

// Create printer instance
final printer = AdvancedPrinter();

// Scan for printers
final devices = await printer.scanPrinters();

// Connect to a printer
await printer.connect(
  devices.first.address,
  type: devices.first.type,
);

// Print text
await printer.printText('Hello, World!');

// Disconnect
await printer.disconnect();
```

## Usage Examples

### Scanning for Printers

```dart
// Scan for Bluetooth printers only
final bluetoothDevices = await printer.scanPrinters(
  bluetooth: true,
  wifi: false,
);

// Scan for all printer types
final allDevices = await printer.scanPrinters();

for (final device in allDevices) {
  print('Found: ${device.name} at ${device.address}');
}
```

### Connecting to a Printer

```dart
// Connect via Bluetooth
final connected = await printer.connect(
  '00:11:22:33:44:55', // MAC address
  type: ConnectionType.bluetooth,
);

// Connect via WiFi
final wifiConnected = await printer.connect(
  '192.168.1.100', // IP address
  type: ConnectionType.wifi,
);

// Check connection status
if (await printer.isConnected()) {
  print('Connected successfully');
}
```

### Printing Text

```dart
// Simple text printing
await printer.printText('Hello, World!');

// Formatted receipt
final receipt = '''
================================
         RECEIPT
================================
Date: ${DateTime.now()}

Item 1              \$10.00
Item 2              \$15.50
Item 3               \$7.25
--------------------------------
Subtotal:           \$32.75
Tax (10%):           \$3.28
--------------------------------
TOTAL:              \$36.03
================================
   Thank you for your purchase!
================================
''';
await printer.printText(receipt);

// Print using different language
await printer.printText(
  'Label Text',
  language: PrinterLanguage.cpcl,
);

// Print with text alignment
await printer.printText(
  'Left Aligned',
  alignment: TextAlignment.left, // Default
);

await printer.printText(
  'Centered Text',
  alignment: TextAlignment.center,
);

await printer.printText(
  'Right Aligned',
  alignment: TextAlignment.right,
);

// Set default alignment for all print operations
printer.setDefaultAlignment(TextAlignment.center);
await printer.printText('This will be centered');
await printer.printText('This too');

// Override default alignment for specific call
await printer.printText(
  'This will be right-aligned',
  alignment: TextAlignment.right,
);
```

### Text Alignment

The plugin supports text alignment (left, center, right) for all printer languages:

```dart
// Alignment constants
TextAlignment.left    // Left alignment (default)
TextAlignment.center  // Center alignment
TextAlignment.right   // Right alignment

// Set default alignment
printer.setDefaultAlignment(TextAlignment.center);

// Get current default alignment
final alignment = printer.getDefaultAlignment();

// Per-call alignment override
await printer.printText(
  'Centered Title',
  alignment: TextAlignment.center,
);
```

**Note:** Alignment support varies by printer language:
- **ESC/POS & EOS**: Full support using `ESC a` commands
- **CPCL**: Calculated x-position based on paper width
- **ZPL**: Uses `^FO` (Field Origin) and `^FB` (Field Block) commands

### Printing Images

```dart
// Load image from assets
final ByteData data = await rootBundle.load('assets/logo.png');
final imageBytes = data.buffer.asUint8List();

// Print with default configuration (80mm)
await printer.printImage(imageBytes);

// Print with custom paper width
await printer.printImage(
  imageBytes,
  config: PrinterConfig.mm58, // For 58mm printers
);

// Print using ZPL language
await printer.printImage(
  imageBytes,
  language: PrinterLanguage.zpl,
  config: PrinterConfig.mm100,
);

// Print image with alignment
await printer.printImage(
  imageBytes,
  alignment: TextAlignment.center,
);
```

### Printing PDFs

```dart
// Print PDF file
await printer.printPdf('/path/to/document.pdf');

// Print PDF using CPCL language
await printer.printPdf(
  '/path/to/label.pdf',
  language: PrinterLanguage.cpcl,
);

// Print PDF with alignment
await printer.printPdf(
  '/path/to/document.pdf',
  alignment: TextAlignment.center,
);
```

### Auto-Cut Feature

```dart
// Enable auto-cut
printer.setAutoCut(true);

// All print operations will now automatically cut paper
await printer.printText('Receipt content');
// Paper is automatically cut after printing

// Disable auto-cut
printer.setAutoCut(false);
```

### Configuring Paper Size

```dart
// Set default paper width (80mm - most common)
printer.setPrinterConfig(PrinterConfig.mm80);

// For 58mm mobile printers
printer.setPrinterConfig(PrinterConfig.mm58);

// For 100mm wide labels
printer.setPrinterConfig(PrinterConfig.mm100);

// Custom paper width
printer.setPrinterConfig(
  PrinterConfig.fromWidthMM(120, dpi: 203),
);

// Get current configuration
final config = printer.getPrinterConfig();
print('Paper width: ${config.paperWidthMM}mm');
```

### Sending Raw Commands

```dart
// Send ESC/POS cut command
final cutCommand = Uint8List.fromList([0x1D, 0x56, 0x01]);
await printer.sendRawData(cutCommand);

// Send custom ESC/POS command (initialize printer)
final initCommand = Uint8List.fromList([0x1B, 0x40]);
await printer.sendRawData(initCommand);
```

## API Reference

### AdvancedPrinter

Main class for printer operations.

#### Methods

- `scanPrinters({bool bluetooth, bool wifi})` - Scan for available printers
- `connect(String address, {String type})` - Connect to a printer
- `disconnect()` - Disconnect from current printer
- `printText(String text, {String language, String? alignment})` - Print text with optional alignment
- `printImage(Uint8List imageBytes, {String language, PrinterConfig? config, String? alignment})` - Print image with optional alignment
- `printPdf(String filePath, {String language, String? alignment})` - Print PDF file with optional alignment
- `sendRawData(Uint8List rawBytes)` - Send raw command bytes
- `cutPaper({String language})` - Cut paper manually
- `isConnected()` - Check connection status
- `setPrinterConfig(PrinterConfig config)` - Set printer configuration
- `getPrinterConfig()` - Get current configuration
- `setDefaultAlignment(String alignment)` - Set default text alignment
- `getDefaultAlignment()` - Get current default alignment
- `setAutoCut(bool enabled)` - Enable/disable auto-cut
- `getAutoCut()` - Get auto-cut status

### PrinterConfig

Configuration for paper width and DPI settings.

#### Predefined Configurations

- `PrinterConfig.mm58` - 58mm paper (mobile printers)
- `PrinterConfig.mm80` - 80mm paper (most common)
- `PrinterConfig.mm100` - 100mm paper (wide labels)

#### Factory Constructors

- `PrinterConfig.fromWidthMM(double widthMM, {int dpi})` - Create from millimeters

### PrinterLanguage

Supported printer command languages.

#### Constants

- `PrinterLanguage.escpos` - ESC/POS (most common)
- `PrinterLanguage.cpcl` - CPCL (Zebra mobile printers)
- `PrinterLanguage.zpl` - ZPL (Zebra industrial printers)
- `PrinterLanguage.eos` - EOS (Epson printers)

### ConnectionType

Supported connection types.

#### Constants

- `ConnectionType.bluetooth` - Bluetooth connection
- `ConnectionType.wifi` - WiFi/Network connection
- `ConnectionType.usb` - USB connection

## Supported Printers

This plugin has been tested with:

- **ESC/POS Printers**:
  - Epson TM series (TM-T88, TM-T20, etc.)
  - Star Micronics printers
  - Generic thermal receipt printers
  - Most 58mm and 80mm thermal printers

- **CPCL Printers**:
  - Zebra QLn series mobile printers
  - Zebra ZQ series printers

- **ZPL Printers**:
  - Zebra industrial label printers
  - Zebra ZD series printers

## Printer Languages

### ESC/POS

The most common language for thermal receipt printers. Used by Epson, Star Micronics, and most generic thermal printers.

**Best for**: Receipt printing, POS systems, general thermal printing

**Supports**: Text, images, barcodes, QR codes, paper cutting

### CPCL

Comtec Printer Control Language, used by Zebra mobile printers.

**Best for**: Mobile printing, portable printers, label printing

**Supports**: Text, graphics, labels, barcodes

### ZPL

Zebra Programming Language, used by Zebra industrial printers.

**Best for**: Industrial label printing, high-volume printing, advanced formatting

**Supports**: Labels, graphics, barcodes, advanced formatting

### EOS

Epson Original Standard, similar to ESC/POS.

**Best for**: Epson printers, ESC/POS-compatible operations

**Supports**: Text, images, barcodes, QR codes, paper cutting

## Connection Types

### Bluetooth

Wireless connection to nearby printers. Requires Bluetooth to be enabled and printer to be paired (on some platforms).

**Address format**: MAC address (e.g., "00:11:22:33:44:55")

**Best for**: Mobile printers, portable devices, close-range printing

**Requirements**:
- Bluetooth enabled on device
- Printer paired (Android) or discoverable (iOS)
- Location permission (Android 6-11 for discovery)

### WiFi

Network connection to printers on the same network.

**Address format**: IP address (e.g., "192.168.1.100") or hostname

**Best for**: Fixed printers, office environments, high-volume printing

**Requirements**:
- Printer and device on same network
- Printer IP address or hostname
- Network connectivity

### USB

Direct wired connection via USB.

**Address format**: USB device identifier (platform-specific)

**Best for**: Desktop applications, reliable connections, high-speed printing

**Requirements**:
- USB cable connection
- USB host mode support (Android)
- USB permissions

## Troubleshooting

### No Printers Found

**Problem**: `scanPrinters()` returns empty list

**Solutions**:
1. Ensure Bluetooth is enabled on your device
2. Make sure the printer is powered on and in pairing/discovery mode
3. Grant location permission (required for Bluetooth discovery on Android 6-11)
4. Try pairing the printer manually in device settings first
5. For WiFi printers, ensure both device and printer are on the same network

### Connection Fails

**Problem**: `connect()` returns `false`

**Solutions**:
1. Verify the printer address is correct
2. Ensure the printer is powered on
3. Try disconnecting and reconnecting
4. For Bluetooth: Ensure printer is paired (Android) or discoverable (iOS)
5. For WiFi: Verify IP address and network connectivity
6. Check if another app is using the printer

### Images Not Printing Correctly

**Problem**: Images are cut off or distorted

**Solutions**:
1. Set the correct paper width using `setPrinterConfig()`
2. Ensure images are not too large (they're automatically resized)
3. Try different printer languages (ESC/POS usually works best)
4. Check printer DPI settings match your configuration

### Auto-Cut Not Working

**Problem**: Paper doesn't cut after printing

**Solutions**:
1. Auto-cut only works with ESC/POS and EOS languages
2. Ensure your printer has a cutter installed
3. Try manually cutting with `cutPaper()`
4. CPCL and ZPL printers don't support standard cut commands

### Permission Errors (Android)

**Problem**: Permission denied errors

**Solutions**:
1. Grant location permission (required for Bluetooth discovery)
2. Grant Bluetooth permissions (Android 12+)
3. Check `AndroidManifest.xml` has required permissions
4. Request permissions at runtime before scanning

### Permission Errors (iOS)

**Problem**: Bluetooth permission denied

**Solutions**:
1. Add Bluetooth usage descriptions to `Info.plist`
2. Grant Bluetooth permission when prompted
3. Check iOS Settings > Privacy > Bluetooth

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For issues, questions, or contributions, please visit the [GitHub repository](https://github.com/yourusername/diamond_printer).

