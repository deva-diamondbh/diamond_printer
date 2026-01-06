import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'diamond_printer_platform_interface.dart';
import 'models/printer_device.dart';
import 'models/printer_language.dart';
import 'models/connection_type.dart';
import 'models/printer_config.dart';
import 'models/text_alignment.dart';

export 'models/printer_device.dart';
export 'models/printer_language.dart';
export 'models/connection_type.dart';
export 'models/printer_config.dart';
export 'models/text_alignment.dart';

/// Advanced printer functionality for Flutter applications.
///
/// This class provides a high-level API for connecting to and printing to
/// thermal and label printers via Bluetooth, WiFi, or USB connections.
/// It supports multiple printer languages (ESC/POS, CPCL, ZPL, EOS) and
/// includes features like automatic image resizing, auto-cut, and paper
/// width configuration.
///
/// ## Quick Start
///
/// ```dart
/// final printer = AdvancedPrinter();
///
/// // Scan for printers
/// final devices = await printer.scanPrinters();
///
/// // Connect to a printer
/// await printer.connect(devices.first.address, type: devices.first.type);
///
/// // Print text
/// await printer.printText('Hello, World!');
///
/// // Print image
/// final imageBytes = await loadImageBytes();
/// await printer.printImage(imageBytes);
///
/// // Disconnect
/// await printer.disconnect();
/// ```
///
/// ## Features
///
/// - Multiple printer languages: ESC/POS, CPCL, ZPL, EOS
/// - Multiple connection types: Bluetooth, WiFi, USB
/// - Automatic image resizing to fit paper width
/// - Auto-cut functionality
/// - Configurable paper widths (58mm, 80mm, 100mm, custom)
/// - PDF printing support
/// - Raw command support for advanced control
class AdvancedPrinter {
  /// Current printer configuration for paper width and DPI settings.
  PrinterConfig _config = PrinterConfig.mm80;

  /// Auto-cut option - automatically cuts paper after each print job.
  bool _autoCut = false;

  /// Default text alignment for print operations.
  String _defaultAlignment = TextAlignment.left;

  /// Scans for available printers on the network or via Bluetooth.
  ///
  /// This method searches for printers using the specified connection methods.
  /// On Android, Bluetooth scanning requires location permissions. On iOS,
  /// Bluetooth scanning requires CoreBluetooth permissions.
  ///
  /// [bluetooth] - Enable Bluetooth scanning (default: true).
  /// [wifi] - Enable WiFi/network scanning (default: true).
  ///
  /// Returns a list of discovered [PrinterDevice] objects. Returns an empty
  /// list if no printers are found or if scanning fails.
  ///
  /// Example:
  /// ```dart
  /// // Scan for Bluetooth printers only
  /// final devices = await printer.scanPrinters(bluetooth: true, wifi: false);
  ///
  /// // Scan for all printer types
  /// final allDevices = await printer.scanPrinters();
  ///
  /// for (final device in devices) {
  ///   print('Found: ${device.name} at ${device.address}');
  /// }
  /// ```
  Future<List<PrinterDevice>> scanPrinters({
    bool bluetooth = true,
    bool wifi = true,
  }) async {
    final devices = await DiamondPrinterPlatform.instance.scanPrinters(
      bluetooth: bluetooth,
      wifi: wifi,
    );
    return devices;
  }

  /// Connects to a printer at the specified address.
  ///
  /// Establishes a connection to the printer using the specified connection
  /// type. The connection must be established before any print operations
  /// can be performed.
  ///
  /// [address] - The printer address:
  ///   - For Bluetooth: MAC address (e.g., "00:11:22:33:44:55")
  ///   - For WiFi: IP address (e.g., "192.168.1.100")
  ///   - For USB: Platform-specific device identifier
  /// [type] - Connection type: 'bluetooth', 'wifi', or 'usb'
  ///   (default: [ConnectionType.bluetooth]).
  ///
  /// Returns `true` if the connection was successful, `false` otherwise.
  ///
  /// Throws [ArgumentError] if the connection type is not supported.
  ///
  /// Example:
  /// ```dart
  /// // Connect via Bluetooth
  /// final connected = await printer.connect(
  ///   '00:11:22:33:44:55',
  ///   type: ConnectionType.bluetooth,
  /// );
  ///
  /// // Connect via WiFi
  /// final wifiConnected = await printer.connect(
  ///   '192.168.1.100',
  ///   type: ConnectionType.wifi,
  /// );
  /// ```
  Future<bool> connect(
    String address, {
    String type = ConnectionType.bluetooth,
  }) async {
    if (!ConnectionType.isSupported(type)) {
      throw ArgumentError('Unsupported connection type: $type');
    }
    return await DiamondPrinterPlatform.instance.connect(address, type: type);
  }

  /// Disconnects from the current printer.
  ///
  /// Closes the connection to the currently connected printer. This should
  /// be called when done printing to free up resources.
  ///
  /// Does nothing if no printer is currently connected.
  ///
  /// Example:
  /// ```dart
  /// await printer.disconnect();
  /// ```
  Future<void> disconnect() async {
    await DiamondPrinterPlatform.instance.disconnect();
  }

  /// Prints text to the connected printer.
  ///
  /// Sends text data to the printer using the specified printer language.
  /// The text is formatted according to the printer language's capabilities.
  /// If auto-cut is enabled, the paper will be cut after printing.
  ///
  /// [text] - The text content to print.
  /// [language] - Printer language: 'escpos', 'cpcl', 'zpl', or 'eos'
  ///   (default: [PrinterLanguage.escpos]).
  /// [alignment] - Text alignment: 'left', 'center', or 'right'
  ///   (default: uses default alignment set by [setDefaultAlignment] or 'left').
  ///
  /// Throws [ArgumentError] if the printer language or alignment is not supported.
  ///
  /// Example:
  /// ```dart
  /// // Print simple text (uses default alignment)
  /// await printer.printText('Hello, World!');
  ///
  /// // Print centered text
  /// await printer.printText('Centered', alignment: TextAlignment.center);
  ///
  /// // Print formatted receipt
  /// final receipt = '''
  /// ================================
  ///         RECEIPT
  /// ================================
  /// Item 1              \$10.00
  /// Item 2              \$15.50
  /// --------------------------------
  /// TOTAL:              \$25.50
  /// ================================
  /// ''';
  /// await printer.printText(receipt);
  ///
  /// // Print using CPCL language with right alignment
  /// await printer.printText(
  ///   'Label',
  ///   language: PrinterLanguage.cpcl,
  ///   alignment: TextAlignment.right,
  /// );
  /// ```
  Future<void> printText(
    String text, {
    String language = PrinterLanguage.escpos,
    String? alignment,
  }) async {
    if (!PrinterLanguage.isSupported(language)) {
      throw ArgumentError('Unsupported printer language: $language');
    }
    final textAlignment = alignment ?? _defaultAlignment;
    if (!TextAlignment.isValid(textAlignment)) {
      throw ArgumentError('Unsupported alignment: $textAlignment');
    }
    await DiamondPrinterPlatform.instance.printText(
      text,
      language: language,
      alignment: textAlignment,
    );

    if (_autoCut) {
      await cutPaper(language: language);
    }
  }

  /// Prints an image to the connected printer.
  ///
  /// Converts and sends image data to the printer. The image is automatically
  /// processed (resized, converted to monochrome) based on the printer
  /// configuration and language. Images are automatically resized to fit
  /// within the paper width if they're too large.
  ///
  /// [imageBytes] - The image data as bytes (PNG, JPEG, etc.).
  /// [language] - Printer language: 'escpos', 'cpcl', 'zpl', or 'eos'
  ///   (default: [PrinterLanguage.escpos]).
  /// [config] - Optional printer configuration that overrides the default
  ///   configuration set by [setPrinterConfig]. If not provided, uses the
  ///   current configuration.
  /// [alignment] - Text/image alignment: 'left', 'center', or 'right'
  ///   (default: uses alignment from config or default alignment).
  ///
  /// Throws [ArgumentError] if the printer language or alignment is not supported.
  ///
  /// Example:
  /// ```dart
  /// // Load image from assets
  /// final ByteData data = await rootBundle.load('assets/logo.png');
  /// final imageBytes = data.buffer.asUint8List();
  ///
  /// // Print with default configuration
  /// await printer.printImage(imageBytes);
  ///
  /// // Print centered image
  /// await printer.printImage(
  ///   imageBytes,
  ///   alignment: TextAlignment.center,
  /// );
  ///
  /// // Print with custom paper width
  /// await printer.printImage(
  ///   imageBytes,
  ///   config: PrinterConfig.mm58,
  /// );
  ///
  /// // Print using ZPL language
  /// await printer.printImage(
  ///   imageBytes,
  ///   language: PrinterLanguage.zpl,
  /// );
  /// ```
  Future<void> printImage(
    Uint8List imageBytes, {
    String language = PrinterLanguage.escpos,
    PrinterConfig? config,
    String? alignment,
  }) async {
    if (!PrinterLanguage.isSupported(language)) {
      throw ArgumentError('Unsupported printer language: $language');
    }

    final printerConfig = config ?? _config;
    final textAlignment = alignment ?? printerConfig.textAlignment;
    if (!TextAlignment.isValid(textAlignment)) {
      throw ArgumentError('Unsupported alignment: $textAlignment');
    }

    final resizedImageBytes = await _resizeImageIfNeeded(
      imageBytes,
      printerConfig,
    );

    final configMap = printerConfig.toMap();
    configMap['textAlignment'] = textAlignment;

    await DiamondPrinterPlatform.instance.printImage(
      resizedImageBytes,
      language: language,
      config: configMap,
    );

    if (_autoCut) {
      await cutPaper(language: language);
    }
  }

  /// Resizes image to fit within paper width if needed.
  ///
  /// This private method automatically resizes images that are too large or
  /// too small to fit the configured paper width. It maintains aspect ratio
  /// and uses appropriate interpolation methods for quality.
  ///
  /// Returns the original bytes if no resizing is needed, or the resized
  /// image bytes if resizing was performed.
  Future<Uint8List> _resizeImageIfNeeded(
    Uint8List imageBytes,
    PrinterConfig config,
  ) async {
    try {
      final decodedImage = img.decodeImage(imageBytes);
      if (decodedImage == null) {
        debugPrint(
          '[diamond_printer] Failed to decode image, using original bytes',
        );
        return imageBytes;
      }

      final originalWidth = decodedImage.width;
      final originalHeight = decodedImage.height;
      final maxWidth = config.maxImageWidth;

      debugPrint('[diamond_printer] 📐 RESIZE CHECK:');
      debugPrint(
        '[diamond_printer]   Original image: ${originalWidth}x${originalHeight} pixels',
      );
      debugPrint(
        '[diamond_printer]   Target width: $maxWidth dots (${config.paperWidthMM.toStringAsFixed(1)}mm at ${config.dpi} DPI)',
      );

      if (originalWidth == maxWidth) {
        debugPrint(
          '[diamond_printer] ✓ Image width ($originalWidth) matches paper width ($maxWidth), no resizing needed',
        );
        return imageBytes;
      }

      final aspectRatio = decodedImage.height / decodedImage.width;
      final newHeight = (maxWidth * aspectRatio).toInt();

      if (originalWidth > maxWidth) {
        debugPrint(
          '[diamond_printer] ⬇️ Image width ($originalWidth) is larger than paper width ($maxWidth), scaling DOWN to ${maxWidth}x$newHeight',
        );
      } else {
        final scalePercent = ((maxWidth / originalWidth - 1) * 100)
            .toStringAsFixed(1);
        debugPrint(
          '[diamond_printer] ⬆️ Image width ($originalWidth) is smaller than paper width ($maxWidth), scaling UP by $scalePercent% to ${maxWidth}x$newHeight',
        );
      }

      // Use cubic interpolation for upscaling (better quality), linear for downscaling (faster)
      final interpolation = originalWidth < maxWidth
          ? img.Interpolation.cubic
          : img.Interpolation.linear;

      final resizedImage = img.copyResize(
        decodedImage,
        width: maxWidth,
        height: newHeight,
        interpolation: interpolation,
      );

      // Validate resized image width never exceeds maxWidth
      if (resizedImage.width > maxWidth) {
        debugPrint(
          '[diamond_printer] ⚠️ WARNING: Resized image width (${resizedImage.width}) exceeds maxWidth ($maxWidth), forcing correction',
        );
        final correctedImage = img.copyResize(
          decodedImage,
          width: maxWidth,
          height: (maxWidth * aspectRatio).toInt(),
          interpolation: interpolation,
        );
        final resizedBytes = Uint8List.fromList(img.encodePng(correctedImage));
        debugPrint(
          '[diamond_printer] ✓ Image resized and corrected: ${correctedImage.width}x${correctedImage.height} pixels, ${resizedBytes.length} bytes',
        );
        return resizedBytes;
      }

      final resizedBytes = Uint8List.fromList(img.encodePng(resizedImage));
      debugPrint(
        '[diamond_printer] ✓ Image resized successfully: ${resizedImage.width}x${resizedImage.height} pixels, ${resizedBytes.length} bytes',
      );

      return resizedBytes;
    } catch (e) {
      debugPrint(
        '[diamond_printer] ❌ Error resizing image: $e, using original bytes',
      );
      return imageBytes;
    }
  }

  /// Prints a PDF file to the connected printer.
  ///
  /// Renders each page of the PDF as an image and sends it to the printer.
  /// Pages are printed sequentially with appropriate spacing between them.
  /// If auto-cut is enabled, the paper will be cut after the last page.
  ///
  /// [filePath] - The local file path to the PDF file.
  /// [language] - Printer language: 'escpos', 'cpcl', 'zpl', or 'eos'
  ///   (default: [PrinterLanguage.escpos]).
  /// [alignment] - Text/image alignment: 'left', 'center', or 'right'
  ///   (default: uses default alignment set by [setDefaultAlignment] or 'left').
  ///
  /// Throws [ArgumentError] if the printer language or alignment is not supported.
  ///
  /// Example:
  /// ```dart
  /// // Print PDF from file path
  /// await printer.printPdf('/path/to/document.pdf');
  ///
  /// // Print centered PDF
  /// await printer.printPdf(
  ///   '/path/to/document.pdf',
  ///   alignment: TextAlignment.center,
  /// );
  ///
  /// // Print PDF using CPCL language
  /// await printer.printPdf(
  ///   '/path/to/label.pdf',
  ///   language: PrinterLanguage.cpcl,
  /// );
  /// ```
  Future<void> printPdf(
    String filePath, {
    String language = PrinterLanguage.escpos,
    String? alignment,
  }) async {
    if (!PrinterLanguage.isSupported(language)) {
      throw ArgumentError('Unsupported printer language: $language');
    }
    final textAlignment = alignment ?? _defaultAlignment;
    if (!TextAlignment.isValid(textAlignment)) {
      throw ArgumentError('Unsupported alignment: $textAlignment');
    }
    await DiamondPrinterPlatform.instance.printPdf(
      filePath,
      language: language,
      alignment: textAlignment,
    );

    if (_autoCut) {
      await cutPaper(language: language);
    }
  }

  /// Sends raw printer command bytes directly to the printer.
  ///
  /// This method allows sending low-level printer commands directly,
  /// bypassing the high-level formatting. Useful for custom commands
  /// or advanced printer control.
  ///
  /// [rawBytes] - The raw command bytes to send to the printer.
  ///
  /// Example:
  /// ```dart
  /// // Send ESC/POS cut command
  /// final cutCommand = Uint8List.fromList([0x1D, 0x56, 0x01]);
  /// await printer.sendRawData(cutCommand);
  ///
  /// // Send custom ESC/POS command
  /// final customCommand = Uint8List.fromList([0x1B, 0x40]); // Initialize printer
  /// await printer.sendRawData(customCommand);
  /// ```
  Future<void> sendRawData(Uint8List rawBytes) async {
    await DiamondPrinterPlatform.instance.sendRawData(rawBytes);
  }

  /// Cuts paper after printing.
  ///
  /// Sends the appropriate cut command based on the printer language.
  /// ESC/POS and EOS support paper cutting, while CPCL and ZPL typically
  /// don't have standard cut commands.
  ///
  /// [language] - Printer language: 'escpos', 'cpcl', 'zpl', or 'eos'
  ///   (default: [PrinterLanguage.escpos]).
  ///
  /// For ESC/POS and EOS, sends GS V 1 (Full cut) command.
  /// For CPCL and ZPL, this method does nothing as these languages
  /// don't support standard cut commands.
  ///
  /// Throws [ArgumentError] if the printer language is not supported.
  ///
  /// Example:
  /// ```dart
  /// // Cut paper after printing
  /// await printer.printText('Receipt content');
  /// await printer.cutPaper();
  /// ```
  Future<void> cutPaper({String language = PrinterLanguage.escpos}) async {
    if (!PrinterLanguage.isSupported(language)) {
      throw ArgumentError('Unsupported printer language: $language');
    }

    Uint8List cutCommand;
    switch (language.toLowerCase()) {
      case PrinterLanguage.escpos:
      case PrinterLanguage.eos:
        // ESC/POS and EOS: GS V 1 (Full cut) - Bytes: [0x1D, 0x56, 0x01]
        cutCommand = Uint8List.fromList([0x1D, 0x56, 0x01]);
        debugPrint('[diamond_printer] Sending paper cut command (ESC/POS/EOS)');
        break;
      case PrinterLanguage.cpcl:
      case PrinterLanguage.zpl:
        debugPrint(
          '[diamond_printer] Paper cut not supported for $language, skipping',
        );
        return;
      default:
        debugPrint(
          '[diamond_printer] Unknown printer language: $language, skipping cut',
        );
        return;
    }

    await sendRawData(cutCommand);
    debugPrint('[diamond_printer] Paper cut command sent');
  }

  /// Checks if a printer is currently connected.
  ///
  /// Returns the current connection status. This should be checked before
  /// attempting print operations.
  ///
  /// Returns `true` if a printer is connected and ready, `false` otherwise.
  ///
  /// Example:
  /// ```dart
  /// if (await printer.isConnected()) {
  ///   await printer.printText('Hello');
  /// } else {
  ///   print('Not connected to printer');
  /// }
  /// ```
  Future<bool> isConnected() async {
    return await DiamondPrinterPlatform.instance.isConnected();
  }

  /// Sets the printer configuration (paper width, DPI, etc.).
  ///
  /// This configuration is used for all subsequent print operations unless
  /// overridden by method-specific configuration parameters.
  ///
  /// [config] - The printer configuration to use.
  ///
  /// Example:
  /// ```dart
  /// // For 80mm paper (most common)
  /// printer.setPrinterConfig(PrinterConfig.mm80);
  ///
  /// // For 58mm paper (mobile printers)
  /// printer.setPrinterConfig(PrinterConfig.mm58);
  ///
  /// // Custom size
  /// printer.setPrinterConfig(PrinterConfig.fromWidthMM(100));
  /// ```
  void setPrinterConfig(PrinterConfig config) {
    _config = config;
  }

  /// Gets the current printer configuration.
  ///
  /// Returns the [PrinterConfig] that is currently set for this printer instance.
  ///
  /// Example:
  /// ```dart
  /// final config = printer.getPrinterConfig();
  /// print('Paper width: ${config.paperWidthMM}mm');
  /// ```
  PrinterConfig getPrinterConfig() {
    return _config;
  }

  /// Sets the default text alignment for print operations.
  ///
  /// This alignment will be used for all print operations unless overridden
  /// by a per-call alignment parameter. The default alignment is 'left'.
  ///
  /// [alignment] - Text alignment: 'left', 'center', or 'right'.
  ///
  /// Throws [ArgumentError] if the alignment is not supported.
  ///
  /// Example:
  /// ```dart
  /// // Set default to center alignment
  /// printer.setDefaultAlignment(TextAlignment.center);
  /// await printer.printText('This will be centered');
  ///
  /// // Override for specific call
  /// await printer.printText(
  ///   'This will be right-aligned',
  ///   alignment: TextAlignment.right,
  /// );
  ///
  /// // Reset to left
  /// printer.setDefaultAlignment(TextAlignment.left);
  /// ```
  void setDefaultAlignment(String alignment) {
    if (!TextAlignment.isValid(alignment)) {
      throw ArgumentError('Unsupported alignment: $alignment');
    }
    _defaultAlignment = alignment;
    debugPrint('[diamond_printer] Default alignment set to: $alignment');
  }

  /// Gets the current default text alignment.
  ///
  /// Returns the default alignment string ('left', 'center', or 'right').
  ///
  /// Example:
  /// ```dart
  /// final alignment = printer.getDefaultAlignment();
  /// print('Default alignment: $alignment');
  /// ```
  String getDefaultAlignment() {
    return _defaultAlignment;
  }

  /// Enables or disables the auto-cut feature.
  ///
  /// When enabled, the printer will automatically cut paper after each print job
  /// (text, image, or PDF). This only works with ESC/POS and EOS printer languages.
  /// CPCL and ZPL printers don't support standard cut commands, so auto-cut
  /// will be silently skipped for those languages.
  ///
  /// [enabled] - Set to `true` to enable auto-cut, `false` to disable
  ///   (default: `false`).
  ///
  /// Example:
  /// ```dart
  /// // Enable auto-cut
  /// printer.setAutoCut(true);
  /// await printer.printText('Hello'); // Will automatically cut after printing
  ///
  /// // Disable auto-cut
  /// printer.setAutoCut(false);
  /// await printer.printText('Hello'); // No automatic cut
  /// ```
  void setAutoCut(bool enabled) {
    _autoCut = enabled;
    debugPrint(
      '[diamond_printer] Auto-cut ${enabled ? "enabled" : "disabled"}',
    );
  }

  /// Gets the current auto-cut setting.
  ///
  /// Returns `true` if auto-cut is enabled, `false` otherwise.
  ///
  /// Example:
  /// ```dart
  /// if (printer.getAutoCut()) {
  ///   print('Auto-cut is enabled');
  /// }
  /// ```
  bool getAutoCut() {
    return _autoCut;
  }

  /// Gets the platform version string (for debugging).
  ///
  /// Returns a string identifying the platform and version, typically
  /// used for debugging purposes (e.g., "Android 13" or "iOS 16.0").
  ///
  /// Returns the platform version string, or `null` if unavailable.
  ///
  /// Example:
  /// ```dart
  /// final version = await printer.getPlatformVersion();
  /// print('Platform: $version');
  /// ```
  Future<String?> getPlatformVersion() {
    return DiamondPrinterPlatform.instance.getPlatformVersion();
  }
}
