/// Supported printer command languages.
///
/// Different printer manufacturers use different command languages to control
/// their printers. This class provides constants and utilities for working with
/// supported printer languages.
///
/// Example:
/// ```dart
/// // Use language constants
/// await printer.printText('Hello', language: PrinterLanguage.escpos);
///
/// // Check if a language is supported
/// if (PrinterLanguage.isSupported('zpl')) {
///   await printer.printText('Label', language: PrinterLanguage.zpl);
/// }
/// ```
class PrinterLanguage {
  /// ESC/POS (Epson Standard Code for Point of Sale).
  ///
  /// The most common language for thermal receipt printers. Used by:
  /// - Epson TM series
  /// - Star Micronics printers
  /// - Most generic thermal printers
  ///
  /// Supports: text, images, barcodes, QR codes, paper cutting.
  static const String escpos = 'escpos';

  /// CPCL (Comtec Printer Control Language).
  ///
  /// Used by Zebra mobile printers and some label printers. Optimized for
  /// mobile and portable printing applications.
  ///
  /// Supports: text, graphics, labels, barcodes.
  static const String cpcl = 'cpcl';

  /// ZPL (Zebra Programming Language).
  ///
  /// Industrial label printing language used by Zebra printers. Designed for
  /// high-volume label printing with advanced formatting options.
  ///
  /// Supports: labels, graphics, barcodes, advanced formatting.
  static const String zpl = 'zpl';

  /// EOS (Epson Original Standard).
  ///
  /// Similar to ESC/POS, used by some Epson printers. Compatible with
  /// ESC/POS commands.
  static const String eos = 'eos';

  /// All supported printer languages.
  ///
  /// Returns a list of all language constants: [escpos, cpcl, zpl, eos].
  static const List<String> all = [escpos, cpcl, zpl, eos];

  /// Checks if a language string is supported.
  ///
  /// Performs case-insensitive comparison against all supported languages.
  ///
  /// [language] - The language string to check (e.g., 'escpos', 'ESC/POS').
  ///
  /// Returns `true` if the language is supported, `false` otherwise.
  ///
  /// Example:
  /// ```dart
  /// PrinterLanguage.isSupported('escpos'); // true
  /// PrinterLanguage.isSupported('ESC/POS'); // true (case-insensitive)
  /// PrinterLanguage.isSupported('invalid'); // false
  /// ```
  static bool isSupported(String language) {
    return all.contains(language.toLowerCase());
  }
}
