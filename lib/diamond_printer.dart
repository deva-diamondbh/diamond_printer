import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
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
  ///
  /// The image will be automatically resized to fit within the paper width if it's too large.
  Future<void> printImage(
    Uint8List imageBytes, {
    String language = PrinterLanguage.escpos,
    PrinterConfig? config,
  }) async {
    if (!PrinterLanguage.isSupported(language)) {
      throw ArgumentError('Unsupported printer language: $language');
    }
    
    final printerConfig = config ?? _config;
    
    // Resize image to fit paper width if needed
    final resizedImageBytes = await _resizeImageIfNeeded(imageBytes, printerConfig);
    
    await DiamondPrinterPlatform.instance.printImage(
      resizedImageBytes,
      language: language,
      config: printerConfig.toMap(),
    );
  }
  
  /// Resize image to fit within paper width if it's too large
  /// Returns the original bytes if no resizing is needed
  Future<Uint8List> _resizeImageIfNeeded(Uint8List imageBytes, PrinterConfig config) async {
    try {
      // Decode image
      final decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) {
        debugPrint('[diamond_printer] Failed to decode image, using original bytes');
        return imageBytes;
      }
      
      final originalWidth = decodedImage.width;
      final maxWidth = config.maxImageWidth;
      
      // If image fits within paper width, return original
      if (originalWidth <= maxWidth) {
        debugPrint('[diamond_printer] Image width ($originalWidth) fits within paper width ($maxWidth), no resizing needed');
        return imageBytes;
      }
      
      // Calculate new height maintaining aspect ratio
      final aspectRatio = decodedImage.height / decodedImage.width;
      final newHeight = (maxWidth * aspectRatio).toInt();
      
      debugPrint('[diamond_printer] Resizing image from ${originalWidth}x${decodedImage.height} to ${maxWidth}x$newHeight to fit paper width');
      
      // Resize image
      final resizedImage = img.copyResize(
        decodedImage,
        width: maxWidth,
        height: newHeight,
        interpolation: img.Interpolation.linear,
      );
      
      // Convert back to bytes (PNG format)
      final resizedBytes = Uint8List.fromList(img.encodePng(resizedImage));
      debugPrint('[diamond_printer] Image resized successfully, new size: ${resizedBytes.length} bytes');
      
      return resizedBytes;
    } catch (e) {
      debugPrint('[diamond_printer] Error resizing image: $e, using original bytes');
      return imageBytes; // Return original if resize fails
    }
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
