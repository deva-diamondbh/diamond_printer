import 'dart:typed_data';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'diamond_printer_method_channel.dart';
import 'models/printer_device.dart';

/// Platform interface for diamond_printer plugin.
///
/// This abstract class defines the interface that platform-specific
/// implementations must follow. It uses the platform interface pattern to
/// allow for testable implementations and platform-specific code.
///
/// The default implementation is [MethodChannelDiamondPrinter], which uses
/// Flutter's method channels to communicate with native code (Android/iOS).
///
/// Custom implementations can be provided for testing or alternative
/// communication methods:
///
/// ```dart
/// class MockDiamondPrinter extends DiamondPrinterPlatform {
///   @override
///   Future<bool> connect(String address, {String type = 'bluetooth'}) async {
///     // Mock implementation
///     return true;
///   }
///   // ... implement other methods
/// }
///
/// // Use in tests
/// DiamondPrinterPlatform.instance = MockDiamondPrinter();
/// ```
abstract class DiamondPrinterPlatform extends PlatformInterface {
  /// Constructs a [DiamondPrinterPlatform].
  ///
  /// This constructor is protected and should only be called by subclasses.
  DiamondPrinterPlatform() : super(token: _token);

  static final Object _token = Object();

  static DiamondPrinterPlatform _instance = MethodChannelDiamondPrinter();

  /// The default instance of [DiamondPrinterPlatform] to use.
  ///
  /// Defaults to [MethodChannelDiamondPrinter] for production use.
  ///
  /// This can be overridden for testing or custom implementations:
  /// ```dart
  /// DiamondPrinterPlatform.instance = MyCustomImplementation();
  /// ```
  static DiamondPrinterPlatform get instance => _instance;

  /// Sets the platform instance.
  ///
  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [DiamondPrinterPlatform] when
  /// they register themselves.
  ///
  /// The instance is verified to ensure it's a valid subclass.
  ///
  /// [instance] - The platform implementation instance.
  static set instance(DiamondPrinterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Gets the platform version string.
  ///
  /// Returns a string identifying the platform and version, typically
  /// used for debugging purposes.
  ///
  /// Returns the platform version string (e.g., "Android 13" or "iOS 16.0"),
  /// or `null` if unavailable.
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  /// Scans for available printers.
  ///
  /// Searches for printers using the specified connection methods.
  /// The implementation should handle permissions and platform-specific
  /// requirements for device discovery.
  ///
  /// [bluetooth] - Whether to scan for Bluetooth printers (default: true).
  /// [wifi] - Whether to scan for WiFi/network printers (default: true).
  ///
  /// Returns a list of discovered [PrinterDevice] objects. Returns an empty
  /// list if no printers are found or if scanning fails.
  ///
  /// Throws platform-specific exceptions if permissions are not granted
  /// or if scanning cannot be performed.
  Future<List<PrinterDevice>> scanPrinters({
    bool bluetooth = true,
    bool wifi = true,
  }) {
    throw UnimplementedError('scanPrinters() has not been implemented.');
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
  /// [type] - Connection type: 'bluetooth', 'wifi', or 'usb' (default: 'bluetooth').
  ///
  /// Returns `true` if the connection was successful, `false` otherwise.
  ///
  /// Throws platform-specific exceptions if connection fails or if the
  /// connection type is not supported.
  Future<bool> connect(String address, {String type = 'bluetooth'}) {
    throw UnimplementedError('connect() has not been implemented.');
  }

  /// Disconnects from the current printer.
  ///
  /// Closes the connection to the currently connected printer. This should
  /// be called when done printing to free up resources.
  ///
  /// Does nothing if no printer is currently connected.
  ///
  /// Throws platform-specific exceptions if disconnection fails.
  Future<void> disconnect() {
    throw UnimplementedError('disconnect() has not been implemented.');
  }

  /// Prints text to the connected printer.
  ///
  /// Sends text data to the printer using the specified printer language.
  /// The text is formatted according to the printer language's capabilities.
  ///
  /// [text] - The text content to print.
  /// [language] - Printer language: 'escpos', 'cpcl', 'zpl', or 'eos'
  ///   (default: 'escpos').
  /// [alignment] - Text alignment: 'left', 'center', or 'right'
  ///   (default: 'left').
  ///
  /// Throws exceptions if:
  /// - No printer is connected
  /// - The printer language is not supported
  /// - The alignment is not supported
  /// - Printing fails
  Future<void> printText(
    String text, {
    String language = 'escpos',
    String? alignment,
  }) {
    throw UnimplementedError('printText() has not been implemented.');
  }

  /// Prints an image to the connected printer.
  ///
  /// Converts and sends image data to the printer. The image is automatically
  /// processed (resized, converted to monochrome) based on the printer
  /// configuration and language.
  ///
  /// [imageBytes] - The image data as bytes (PNG, JPEG, etc.).
  /// [language] - Printer language: 'escpos', 'cpcl', 'zpl', or 'eos'
  ///   (default: 'escpos').
  /// [config] - Optional printer configuration map containing:
  ///   - `paperWidthDots`: Paper width in dots
  ///   - `dpi`: Dots per inch
  ///   - `paperWidthMM`: Paper width in millimeters
  ///   - `textAlignment`: Text alignment ('left', 'center', or 'right')
  /// [alignment] - Image alignment: 'left', 'center', or 'right'
  ///   (default: uses alignment from config or 'left').
  ///
  /// Throws exceptions if:
  /// - No printer is connected
  /// - The image cannot be decoded
  /// - The printer language is not supported
  /// - The alignment is not supported
  /// - Printing fails
  Future<void> printImage(
    Uint8List imageBytes, {
    String language = 'escpos',
    Map<String, dynamic>? config,
    String? alignment,
  }) {
    throw UnimplementedError('printImage() has not been implemented.');
  }

  /// Prints a PDF file to the connected printer.
  ///
  /// Renders each page of the PDF as an image and sends it to the printer.
  /// Pages are printed sequentially with appropriate spacing.
  ///
  /// [filePath] - The local file path to the PDF file.
  /// [language] - Printer language: 'escpos', 'cpcl', 'zpl', or 'eos'
  ///   (default: 'escpos').
  /// [alignment] - Text/image alignment: 'left', 'center', or 'right'
  ///   (default: 'left').
  ///
  /// Throws exceptions if:
  /// - No printer is connected
  /// - The PDF file cannot be found or opened
  /// - The printer language is not supported
  /// - The alignment is not supported
  /// - Printing fails
  Future<void> printPdf(
    String filePath, {
    String language = 'escpos',
    String? alignment,
  }) {
    throw UnimplementedError('printPdf() has not been implemented.');
  }

  /// Sends raw command bytes directly to the printer.
  ///
  /// This method allows sending low-level printer commands directly,
  /// bypassing the high-level formatting. Useful for custom commands
  /// or advanced printer control.
  ///
  /// [rawBytes] - The raw command bytes to send to the printer.
  ///
  /// Throws exceptions if:
  /// - No printer is connected
  /// - Sending data fails
  ///
  /// Example:
  /// ```dart
  /// // Send ESC/POS cut command
  /// final cutCommand = Uint8List.fromList([0x1D, 0x56, 0x01]);
  /// await platform.sendRawData(cutCommand);
  /// ```
  Future<void> sendRawData(Uint8List rawBytes) {
    throw UnimplementedError('sendRawData() has not been implemented.');
  }

  /// Checks if a printer is currently connected.
  ///
  /// Returns the current connection status. This should be checked before
  /// attempting print operations.
  ///
  /// Returns `true` if a printer is connected and ready, `false` otherwise.
  ///
  /// Note: The connection status may change asynchronously, so this is
  /// a snapshot of the current state.
  Future<bool> isConnected() {
    throw UnimplementedError('isConnected() has not been implemented.');
  }
}
