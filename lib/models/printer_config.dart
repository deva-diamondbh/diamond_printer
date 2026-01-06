/// Configuration for printer paper width and settings.
///
/// This class manages printer paper dimensions, DPI settings, text alignment,
/// and calculates maximum image widths accounting for hardware margins.
/// Most thermal printers have small hardware margins that prevent true
/// edge-to-edge printing.
///
/// Example:
/// ```dart
/// // Use predefined configurations
/// final config80mm = PrinterConfig.mm80; // Most common size
/// final config58mm = PrinterConfig.mm58; // Mobile printers
///
/// // Create custom configuration with alignment
/// final customConfig = PrinterConfig.fromWidthMM(
///   100,
///   dpi: 203,
///   textAlignment: TextAlignment.center,
/// );
///
/// // Use with printer
/// printer.setPrinterConfig(customConfig);
/// ```
class PrinterConfig {
  /// Paper width in dots/pixels at the configured DPI.
  final int paperWidthDots;

  /// DPI (dots per inch) - typically 203 for thermal printers.
  ///
  /// Common DPI values:
  /// - 203 DPI: Standard thermal printers
  /// - 300 DPI: High-resolution printers
  final int dpi;

  /// Text alignment for printed content.
  ///
  /// Defaults to [TextAlignment.left] if not specified.
  final String textAlignment;

  /// Maximum image width in dots, reduced by 2% to account for hardware margins.
  ///
  /// Most thermal printers have small hardware margins that prevent true
  /// edge-to-edge printing. This getter automatically calculates a safe maximum
  /// width to prevent right-side cutoff.
  int get maxImageWidth => (paperWidthDots * 0.98).toInt();

  /// Creates a printer configuration.
  ///
  /// [paperWidthDots] - Paper width in dots (default: 576 for 3 inch/72mm at 203 DPI).
  /// [dpi] - Dots per inch (default: 203).
  /// [textAlignment] - Text alignment: 'left', 'center', or 'right' (default: 'left').
  const PrinterConfig({
    this.paperWidthDots = 576,
    this.dpi = 203,
    this.textAlignment = 'left',
  });

  /// Creates a configuration from paper width in millimeters.
  ///
  /// This factory constructor converts millimeters to dots based on the DPI.
  /// Common paper sizes: 58mm (mobile printers), 80mm (most common), 100mm (wide labels).
  ///
  /// [widthMM] - Paper width in millimeters.
  /// [dpi] - Dots per inch (default: 203).
  /// [textAlignment] - Text alignment: 'left', 'center', or 'right' (default: 'left').
  ///
  /// Example:
  /// ```dart
  /// final config = PrinterConfig.fromWidthMM(80);
  /// print(config.paperWidthDots); // ~640 dots at 203 DPI
  ///
  /// // With custom alignment
  /// final centered = PrinterConfig.fromWidthMM(
  ///   80,
  ///   textAlignment: TextAlignment.center,
  /// );
  /// ```
  factory PrinterConfig.fromWidthMM(
    double widthMM, {
    int dpi = 203,
    String textAlignment = 'left',
  }) {
    // Convert mm to dots: (mm / 25.4) * dpi
    final dots = ((widthMM / 25.4) * dpi).round();
    return PrinterConfig(
      paperWidthDots: dots,
      dpi: dpi,
      textAlignment: textAlignment,
    );
  }

  /// Predefined configuration for 58mm paper (mobile printers).
  ///
  /// Approximately 384 dots at 203 DPI.
  static PrinterConfig mm58 = PrinterConfig.fromWidthMM(58);

  /// Predefined configuration for 80mm paper (most common size).
  ///
  /// Approximately 640 dots at 203 DPI. This is the most commonly used
  /// configuration for receipt printers.
  static PrinterConfig mm80 = PrinterConfig.fromWidthMM(80);

  /// Predefined configuration for 100mm paper (wide labels).
  ///
  /// Approximately 800 dots at 203 DPI.
  static PrinterConfig mm100 = PrinterConfig.fromWidthMM(100);

  /// Predefined configuration for 2-inch paper (58mm equivalent).
  static const PrinterConfig inch2 = PrinterConfig(paperWidthDots: 384);

  /// Predefined configuration for 3-inch paper (72mm equivalent).
  static const PrinterConfig inch3 = PrinterConfig(paperWidthDots: 576);

  /// Predefined configuration for 4-inch paper (104mm equivalent).
  static const PrinterConfig inch4 = PrinterConfig(paperWidthDots: 832);

  /// Gets the paper width in millimeters.
  ///
  /// Calculates the physical width based on dots and DPI.
  double get paperWidthMM => (paperWidthDots / dpi) * 25.4;

  /// Converts the configuration to a map for platform channel communication.
  ///
  /// Returns a map containing:
  /// - `paperWidthDots`: Paper width in dots
  /// - `dpi`: Dots per inch
  /// - `paperWidthMM`: Paper width in millimeters
  /// - `textAlignment`: Text alignment ('left', 'center', or 'right')
  Map<String, dynamic> toMap() {
    return {
      'paperWidthDots': paperWidthDots,
      'dpi': dpi,
      'paperWidthMM': paperWidthMM,
      'textAlignment': textAlignment,
    };
  }

  @override
  String toString() {
    return 'PrinterConfig(width: ${paperWidthDots}dots, ${paperWidthMM.toStringAsFixed(0)}mm, dpi: $dpi)';
  }
}
