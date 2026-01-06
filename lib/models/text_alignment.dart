/// Text alignment options for printer output.
///
/// This class provides constants for text alignment that work across
/// all supported printer languages (ESC/POS, CPCL, ZPL, EOS).
///
/// Example:
/// ```dart
/// // Use alignment constants
/// await printer.printText('Centered Text', alignment: TextAlignment.center);
///
/// // Set default alignment
/// printer.setDefaultAlignment(TextAlignment.right);
/// ```
class TextAlignment {
  /// Left alignment (default).
  ///
  /// Text is aligned to the left margin of the paper.
  static const String left = 'left';

  /// Center alignment.
  ///
  /// Text is centered on the paper width.
  static const String center = 'center';

  /// Right alignment.
  ///
  /// Text is aligned to the right margin of the paper.
  static const String right = 'right';

  /// All supported alignment options.
  static const List<String> all = [left, center, right];

  /// Checks if an alignment string is valid.
  ///
  /// Performs case-insensitive comparison against all supported alignments.
  ///
  /// [alignment] - The alignment string to check (e.g., 'left', 'CENTER').
  ///
  /// Returns `true` if the alignment is supported, `false` otherwise.
  ///
  /// Example:
  /// ```dart
  /// TextAlignment.isValid('left'); // true
  /// TextAlignment.isValid('CENTER'); // true (case-insensitive)
  /// TextAlignment.isValid('invalid'); // false
  /// ```
  static bool isValid(String alignment) {
    return all.contains(alignment.toLowerCase());
  }
}

