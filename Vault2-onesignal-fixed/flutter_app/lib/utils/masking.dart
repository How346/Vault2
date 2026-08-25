/// Pure functions for privacy masking. Originals are never mutated.
class Masking {
  /// Masks all but the last [visibleTail] alphanumeric characters.
  /// "1234 5678 9012" -> "XXXX XXXX 9012"
  static String maskTail(String value, {int visibleTail = 4, String maskChar = 'X'}) {
    if (value.trim().isEmpty) return value;
    final chars = value.split('');
    var remaining = _alphanumCount(value) - visibleTail;
    if (remaining <= 0) return value;
    for (var i = 0; i < chars.length && remaining > 0; i++) {
      if (_isAlphanum(chars[i])) {
        chars[i] = maskChar;
        remaining--;
      }
    }
    return chars.join();
  }

  /// Aadhaar style: hide the first 8 digits, keep the last 4.
  static String maskAadhaar(String value) => maskTail(value, visibleTail: 4);

  /// PAN style: keep first 2 and last 2 (ABXXXXXX1X).
  static String maskPan(String value) {
    if (value.length < 6) return maskTail(value, visibleTail: 2);
    final chars = value.split('');
    for (var i = 2; i < chars.length - 2; i++) {
      if (_isAlphanum(chars[i])) chars[i] = 'X';
    }
    return chars.join();
  }

  static String forCategory(String categoryId, String value) {
    switch (categoryId) {
      case 'pan':
        return maskPan(value);
      case 'aadhaar':
      case 'dl':
      case 'passport':
        return maskTail(value, visibleTail: 4);
      default:
        return maskTail(value, visibleTail: 4);
    }
  }

  static bool _isAlphanum(String c) => RegExp(r'[A-Za-z0-9]').hasMatch(c);
  static int _alphanumCount(String v) => v.split('').where(_isAlphanum).length;
}
