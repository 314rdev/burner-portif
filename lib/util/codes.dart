import 'dart:math';

/// Generation and parsing of drop codes.
///
/// Codes are 6 characters from a 32-symbol alphabet without look-alikes
/// (no I, O, 0, 1): ~1.07 billion combinations. They double as the Firestore
/// document id, so `firestore.rules` validates the same pattern.
class DropCodes {
  const DropCodes._();

  static const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const length = 6;
  static final pattern = RegExp('^[$alphabet]{$length}\$');

  static final Random _random = Random.secure();

  static String generate([Random? random]) {
    final r = random ?? _random;
    return List.generate(length, (_) => alphabet[r.nextInt(alphabet.length)])
        .join();
  }

  /// Random id for the Storage folder of a drop. Kept separate from the code
  /// so knowing an object path does not reveal the code and vice versa.
  static String storageId([Random? random]) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = random ?? _random;
    return List.generate(20, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Length of a public-link token. Public drops can be opened without
  /// signing in, so they use a long secret (62^24 ≈ 10^43) instead of the
  /// short code, which would be guessable without auth as a barrier.
  static const publicTokenLength = 24;
  static final publicTokenPattern = RegExp('^[A-Za-z0-9]{$publicTokenLength}\$');

  static String publicToken([Random? random]) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final r = random ?? _random;
    return List.generate(publicTokenLength, (_) => chars[r.nextInt(chars.length)])
        .join();
  }

  /// Extracts a public-link token from a link containing `?p=...` (or a bare
  /// token). Returns null if none is found.
  static String? parsePublicToken(String input) {
    var text = input.trim();
    final fromLink = RegExp(r'[?&#]p=([^&#\s]+)').firstMatch(text);
    if (fromLink != null) text = Uri.decodeComponent(fromLink.group(1)!);
    return publicTokenPattern.hasMatch(text) ? text : null;
  }

  /// `ABC234` -> `ABC-234`.
  static String format(String code) => code.length == length
      ? '${code.substring(0, 3)}-${code.substring(3)}'
      : code;

  /// Extracts a valid code from user input: a bare code (any case, with or
  /// without separators) or a share link containing `?code=...`.
  /// Returns null if nothing valid is found.
  static String? parse(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    final fromLink = RegExp(r'[?&#]code=([^&#\s]+)').firstMatch(text);
    if (fromLink != null) {
      text = Uri.decodeComponent(fromLink.group(1)!);
    }
    final cleaned = text.toUpperCase().replaceAll(RegExp(r'[\s\-_.·]'), '');
    return pattern.hasMatch(cleaned) ? cleaned : null;
  }
}
