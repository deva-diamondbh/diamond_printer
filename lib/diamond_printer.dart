import 'dart:typed_data';
import 'diamond_printer_platform_interface.dart';
import 'models/printer_device.dart';
import 'models/printer_language.dart';
import 'models/connection_type.dart';
import 'models/printer_config.dart';

export 'models/printer_device.dart';
export 'models/printer_language.dart';
export 'models/connection_type.dart';
export 'models/printer_config.dart';

/// Main class for advanced printer functionality
///
/// Supports ESC/POS, CPCL, ZPL, and EOS printer languages
/// Supports Bluetooth, WiFi, and USB connections
class AdvancedPrinter {
  /// Current printer configuration
  PrinterConfig _config = PrinterConfig.mm80; // Default 80mm (most common)
  /// Scan for available printers
  ///
  /// [bluetooth] - Enable Bluetooth scanning (default: true)
  /// [wifi] - Enable WiFi/network scanning (default: true)
  ///
  /// Returns a list of discovered [PrinterDevice]s
  Future<List<PrinterDevice>> scanPrinters({bool bluetooth = true, bool wifi = true}) async {
    final devices = await DiamondPrinterPlatform.instance.scanPrinters(bluetooth: bluetooth, wifi: wifi);
    return devices;
  }

  /// Connect to a printer
  ///
  /// [address] - The printer address (MAC for Bluetooth, IP for WiFi)
  /// [type] - Connection type: 'bluetooth', 'wifi', or 'usb'
  ///
  /// Returns true if connection successful
  Future<bool> connect(String address, {String type = ConnectionType.bluetooth}) async {
    if (!ConnectionType.isSupported(type)) {
      throw ArgumentError('Unsupported connection type: $type');
    }
    return await DiamondPrinterPlatform.instance.connect(address, type: type);
  }

  /// Disconnect from the current printer
  Future<void> disconnect() async {
    await DiamondPrinterPlatform.instance.disconnect();
  }

  /// Print text using the specified printer language
  ///
  /// [text] - The text to print
  /// [language] - Printer language: 'escpos', 'cpcl', 'zpl', or 'eos' (default: 'escpos')
  Future<void> printText(String text, {String language = PrinterLanguage.escpos}) async {
    if (!PrinterLanguage.isSupported(language)) {
      throw ArgumentError('Unsupported printer language: $language');
    }
    await DiamondPrinterPlatform.instance.printText(text, language: language);
  }

  /// Print an image using the specified printer language
  ///
  /// [imageBytes] - The image data as bytes
  /// [language] - Printer language: 'escpos', 'cpcl', 'zpl', or 'eos' (default: 'escpos')
  /// [config] - Optional printer configuration (overrides setPrinterConfig)
  Future<void> printImage(
    Uint8List imageBytes, {
    String language = PrinterLanguage.escpos,
    PrinterConfig? config,
  }) async {
    if (!PrinterLanguage.isSupported(language)) {
      throw ArgumentError('Unsupported printer language: $language');
    }
    await DiamondPrinterPlatform.instance.printImage(
      imageBytes,
      language: language,
      config: (config ?? _config).toMap(),
    );
  }

  /// Print a PDF file using the specified printer language
  ///
  /// [filePath] - Path to the PDF file
  /// [language] - Printer language: 'escpos', 'cpcl', 'zpl', or 'eos' (default: 'escpos')
  Future<void> printPdf(String filePath, {String language = PrinterLanguage.escpos}) async {
    if (!PrinterLanguage.isSupported(language)) {
      throw ArgumentError('Unsupported printer language: $language');
    }
    await DiamondPrinterPlatform.instance.printPdf(filePath, language: language);
  }

  /// Send raw printer command bytes
  ///
  /// [rawBytes] - The raw command bytes to send to the printer
  Future<void> sendRawData(Uint8List rawBytes) async {
    await DiamondPrinterPlatform.instance.sendRawData(rawBytes);
  }

  /// Check if currently connected to a printer
  Future<bool> isConnected() async {
    return await DiamondPrinterPlatform.instance.isConnected();
  }

  /// Set printer configuration (paper width, DPI, etc.)
  ///
  /// [config] - Printer configuration
  ///
  /// Example:
  /// ```dart
  /// // For 80mm paper (most common)
  /// printer.setPrinterConfig(PrinterConfig.mm80);
  ///
  /// // For 58mm paper
  /// printer.setPrinterConfig(PrinterConfig.mm58);
  ///
  /// // Custom size
  /// printer.setPrinterConfig(PrinterConfig.fromWidthMM(100));
  /// ```
  void setPrinterConfig(PrinterConfig config) {
    _config = config;
  }

  /// Get current printer configuration
  PrinterConfig getPrinterConfig() {
    return _config;
  }

  /// Get the platform version (for debugging)
  Future<String?> getPlatformVersion() {
    return DiamondPrinterPlatform.instance.getPlatformVersion();
  }
}
