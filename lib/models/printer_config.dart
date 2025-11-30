/// Printer configuration for paper width and settings
class PrinterConfig {
  /// Paper width in dots/pixels
  final int paperWidthDots;
  
  /// DPI (dots per inch) - usually 203 for thermal printers
  final int dpi;
  
  /// Maximum image width in dots (auto-calculated from paperWidthDots with margins)
  int get maxImageWidth => (paperWidthDots * 0.9).toInt(); // 90% to allow margins
  
  const PrinterConfig({
    this.paperWidthDots = 576, // Default 3 inch (72mm)
    this.dpi = 203,
  });
  
  /// Create configuration from paper width in millimeters
  /// Common sizes: 58mm, 80mm, 100mm
  factory PrinterConfig.fromWidthMM(double widthMM, {int dpi = 203}) {
    // Convert mm to dots: (mm / 25.4) * dpi
    final dots = ((widthMM / 25.4) * dpi).round();
    return PrinterConfig(paperWidthDots: dots, dpi: dpi);
  }
  
  /// Common printer configurations by paper width in MM
  static PrinterConfig mm58 = PrinterConfig.fromWidthMM(58); // ~384 dots
  static PrinterConfig mm80 = PrinterConfig.fromWidthMM(80); // ~640 dots - Very common!
  static PrinterConfig mm100 = PrinterConfig.fromWidthMM(100); // ~800 dots
  
  /// Common printer configurations by inch
  static const PrinterConfig inch2 = PrinterConfig(paperWidthDots: 384);  // 58mm
  static const PrinterConfig inch3 = PrinterConfig(paperWidthDots: 576);  // 72mm
  static const PrinterConfig inch4 = PrinterConfig(paperWidthDots: 832);  // 104mm
  
  /// Get paper width in millimeters
  double get paperWidthMM => (paperWidthDots / dpi) * 25.4;
  
  /// Convert to map for platform channel
  Map<String, dynamic> toMap() {
    return {
      'paperWidthDots': paperWidthDots,
      'dpi': dpi,
      'paperWidthMM': paperWidthMM,
    };
  }
  
  @override
  String toString() {
    return 'PrinterConfig(width: ${paperWidthDots}dots, ${paperWidthMM.toStringAsFixed(0)}mm, dpi: $dpi)';
  }
}

