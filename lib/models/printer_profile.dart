/// Printer profile storing capabilities and optimal settings for a specific printer
class PrinterProfile {
  final String address;
  final String name;
  final String? model; // Detected or user-provided model name
  final PrinterCapabilities capabilities;
  final PrinterSettings settings;
  final DateTime lastUsed;
  
  const PrinterProfile({
    required this.address,
    required this.name,
    this.model,
    required this.capabilities,
    required this.settings,
    required this.lastUsed,
  });
  
  factory PrinterProfile.fromMap(Map<String, dynamic> map) {
    return PrinterProfile(
      address: map['address'] as String,
      name: map['name'] as String,
      model: map['model'] as String?,
      capabilities: PrinterCapabilities.fromMap(map['capabilities'] as Map<String, dynamic>),
      settings: PrinterSettings.fromMap(map['settings'] as Map<String, dynamic>),
      lastUsed: DateTime.parse(map['lastUsed'] as String),
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'address': address,
      'name': name,
      'model': model,
      'capabilities': capabilities.toMap(),
      'settings': settings.toMap(),
      'lastUsed': lastUsed.toIso8601String(),
    };
  }
  
  PrinterProfile copyWith({
    String? address,
    String? name,
    String? model,
    PrinterCapabilities? capabilities,
    PrinterSettings? settings,
    DateTime? lastUsed,
  }) {
    return PrinterProfile(
      address: address ?? this.address,
      name: name ?? this.name,
      model: model ?? this.model,
      capabilities: capabilities ?? this.capabilities,
      settings: settings ?? this.settings,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }
}

/// Printer capabilities detected through probing or known from database
class PrinterCapabilities {
  final bool supportsImages;
  final bool supportsGraphics;
  final bool supportsBarcodes;
  final bool supportsQRCode;
  final List<String> supportedLanguages; // ['escpos', 'cpcl', 'zpl']
  final List<ImageEncodingMode> supportedImageModes;
  final int maxPaperWidthMM;
  final int dpi;
  
  const PrinterCapabilities({
    this.supportsImages = true,
    this.supportsGraphics = true,
    this.supportsBarcodes = true,
    this.supportsQRCode = true,
    this.supportedLanguages = const ['escpos'],
    this.supportedImageModes = const [ImageEncodingMode.raster],
    this.maxPaperWidthMM = 80,
    this.dpi = 203,
  });
  
  factory PrinterCapabilities.fromMap(Map<String, dynamic> map) {
    return PrinterCapabilities(
      supportsImages: map['supportsImages'] as bool? ?? true,
      supportsGraphics: map['supportsGraphics'] as bool? ?? true,
      supportsBarcodes: map['supportsBarcodes'] as bool? ?? true,
      supportsQRCode: map['supportsQRCode'] as bool? ?? true,
      supportedLanguages: (map['supportedLanguages'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ?? ['escpos'],
      supportedImageModes: (map['supportedImageModes'] as List<dynamic>?)
          ?.map((e) => ImageEncodingMode.values[e as int])
          .toList() ?? [ImageEncodingMode.raster],
      maxPaperWidthMM: map['maxPaperWidthMM'] as int? ?? 80,
      dpi: map['dpi'] as int? ?? 203,
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'supportsImages': supportsImages,
      'supportsGraphics': supportsGraphics,
      'supportsBarcodes': supportsBarcodes,
      'supportsQRCode': supportsQRCode,
      'supportedLanguages': supportedLanguages,
      'supportedImageModes': supportedImageModes.map((e) => e.index).toList(),
      'maxPaperWidthMM': maxPaperWidthMM,
      'dpi': dpi,
    };
  }
  
  /// Create default capabilities for unknown printers (maximum compatibility)
  factory PrinterCapabilities.universalCompatibility() {
    return const PrinterCapabilities(
      supportsImages: true,
      supportsGraphics: true,
      supportsBarcodes: true,
      supportsQRCode: false, // Not all printers support QR
      supportedLanguages: ['escpos', 'cpcl', 'zpl'],
      supportedImageModes: [
        ImageEncodingMode.raster,
        ImageEncodingMode.bitImage8Single,
        ImageEncodingMode.bitImage8Double,
        ImageEncodingMode.bitImage24,
      ],
      maxPaperWidthMM: 80,
      dpi: 203,
    );
  }
}

/// Image encoding modes for ESC/POS printers
enum ImageEncodingMode {
  raster,           // GS v 0 - Most compatible, modern printers
  bitImage8Single,  // ESC * 0 - 8-dot single density
  bitImage8Double,  // ESC * 1 - 8-dot double density
  bitImage24,       // ESC * 33 - 24-dot triple density (highest quality)
  graphics,         // CPCL GRAPHICS command
  zplGraphics,      // ZPL ^GF command
}

/// Optimal settings for a specific printer
class PrinterSettings {
  final String preferredLanguage;
  final ImageEncodingMode preferredImageMode;
  final int paperWidthMM;
  final int imageMaxWidth; // Pixels
  final bool useCompression;
  final bool useDithering;
  final int printSpeed; // 0-5, lower = slower but higher quality
  final int printDensity; // 0-15, higher = darker
  
  const PrinterSettings({
    this.preferredLanguage = 'escpos',
    this.preferredImageMode = ImageEncodingMode.raster,
    this.paperWidthMM = 80,
    this.imageMaxWidth = 576,
    this.useCompression = false,
    this.useDithering = true,
    this.printSpeed = 3,
    this.printDensity = 8,
  });
  
  factory PrinterSettings.fromMap(Map<String, dynamic> map) {
    return PrinterSettings(
      preferredLanguage: map['preferredLanguage'] as String? ?? 'escpos',
      preferredImageMode: ImageEncodingMode.values[map['preferredImageMode'] as int? ?? 0],
      paperWidthMM: map['paperWidthMM'] as int? ?? 80,
      imageMaxWidth: map['imageMaxWidth'] as int? ?? 576,
      useCompression: map['useCompression'] as bool? ?? false,
      useDithering: map['useDithering'] as bool? ?? true,
      printSpeed: map['printSpeed'] as int? ?? 3,
      printDensity: map['printDensity'] as int? ?? 8,
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'preferredLanguage': preferredLanguage,
      'preferredImageMode': preferredImageMode.index,
      'paperWidthMM': paperWidthMM,
      'imageMaxWidth': imageMaxWidth,
      'useCompression': useCompression,
      'useDithering': useDithering,
      'printSpeed': printSpeed,
      'printDensity': printDensity,
    };
  }
  
  /// Create optimal settings for maximum compatibility
  factory PrinterSettings.safeDefaults() {
    return const PrinterSettings(
      preferredLanguage: 'escpos',
      preferredImageMode: ImageEncodingMode.bitImage8Single, // Most compatible
      paperWidthMM: 80,
      imageMaxWidth: 384, // Conservative width for 58mm/80mm printers
      useCompression: false,
      useDithering: true,
      printSpeed: 2, // Slower = more reliable
      printDensity: 8,
    );
  }
}

/// Known printer models with pre-configured optimal settings
class KnownPrinterDatabase {
  static final Map<String, PrinterProfile> knownPrinters = {
    // Epson TM series
    'TM-T88': PrinterProfile(
      address: '',
      name: 'Epson TM-T88',
      model: 'TM-T88',
      capabilities: const PrinterCapabilities(
        supportedLanguages: ['escpos'],
        supportedImageModes: [
          ImageEncodingMode.raster,
          ImageEncodingMode.bitImage24,
        ],
        maxPaperWidthMM: 80,
        dpi: 203,
      ),
      settings: const PrinterSettings(
        preferredLanguage: 'escpos',
        preferredImageMode: ImageEncodingMode.raster,
        paperWidthMM: 80,
        imageMaxWidth: 576,
      ),
      lastUsed: DateTime.now(),
    ),
    
    // Zebra mobile printers
    'QLn': PrinterProfile(
      address: '',
      name: 'Zebra QLn Series',
      model: 'QLn',
      capabilities: const PrinterCapabilities(
        supportedLanguages: ['cpcl', 'zpl'],
        supportedImageModes: [ImageEncodingMode.graphics],
        maxPaperWidthMM: 108,
        dpi: 203,
      ),
      settings: const PrinterSettings(
        preferredLanguage: 'cpcl',
        preferredImageMode: ImageEncodingMode.graphics,
        paperWidthMM: 108,
        imageMaxWidth: 832,
      ),
      lastUsed: DateTime.now(),
    ),
    
    // Generic 58mm printers (cheap Chinese models)
    'Generic58mm': PrinterProfile(
      address: '',
      name: 'Generic 58mm Thermal',
      model: 'Generic58mm',
      capabilities: const PrinterCapabilities(
        supportedLanguages: ['escpos'],
        supportedImageModes: [
          ImageEncodingMode.bitImage8Single,
          ImageEncodingMode.bitImage8Double,
        ],
        maxPaperWidthMM: 58,
        dpi: 203,
        supportsQRCode: false,
      ),
      settings: const PrinterSettings(
        preferredLanguage: 'escpos',
        preferredImageMode: ImageEncodingMode.bitImage8Single,
        paperWidthMM: 58,
        imageMaxWidth: 384,
        printSpeed: 2, // Slower for cheap printers
      ),
      lastUsed: DateTime.now(),
    ),
  };
  
  /// Try to identify printer model from name/address
  static PrinterProfile? identifyPrinter(String name, String address) {
    // Check for known patterns in printer name
    final lowerName = name.toLowerCase();
    
    if (lowerName.contains('tm-t88') || lowerName.contains('tmt88')) {
      return knownPrinters['TM-T88']?.copyWith(address: address, name: name);
    }
    
    if (lowerName.contains('qln') || lowerName.contains('zebra')) {
      return knownPrinters['QLn']?.copyWith(address: address, name: name);
    }
    
    // Check for generic patterns
    if (lowerName.contains('58mm') || lowerName.contains('5802')) {
      return knownPrinters['Generic58mm']?.copyWith(address: address, name: name);
    }
    
    // Unknown printer - return universal compatibility profile
    return PrinterProfile(
      address: address,
      name: name,
      model: null,
      capabilities: PrinterCapabilities.universalCompatibility(),
      settings: PrinterSettings.safeDefaults(),
      lastUsed: DateTime.now(),
    );
  }
}

