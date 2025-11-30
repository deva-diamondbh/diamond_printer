/// Supported printer command languages
class PrinterLanguage {
  static const String escpos = 'escpos';
  static const String cpcl = 'cpcl';
  static const String zpl = 'zpl';
  static const String eos = 'eos';
  
  /// All supported printer languages
  static const List<String> all = [escpos, cpcl, zpl, eos];
  
  /// Check if a language is supported
  static bool isSupported(String language) {
    return all.contains(language.toLowerCase());
  }
}

