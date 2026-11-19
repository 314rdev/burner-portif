import 'dart:math';

import 'package:burner/util/codes.dart';
import 'package:burner/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DropCodes', () {
    test('generate produces valid codes', () {
      final r = Random(1);
      for (var i = 0; i < 500; i++) {
        expect(DropCodes.pattern.hasMatch(DropCodes.generate(r)), isTrue);
      }
    });

    test('alphabet has no look-alikes', () {
      for (final c in ['I', 'O', '0', '1']) {
        expect(DropCodes.alphabet.contains(c), isFalse);
      }
      expect(DropCodes.alphabet.length, 32);
    });

    test('parse accepts codes in any case and with separators', () {
      expect(DropCodes.parse('abc234'), 'ABC234');
      expect(DropCodes.parse(' ABC-234 '), 'ABC234');
      expect(DropCodes.parse('abc 234'), 'ABC234');
    });

    test('parse extracts codes from share links', () {
      expect(DropCodes.parse('https://x.web.app/?code=ABC234'), 'ABC234');
      expect(DropCodes.parse('https://x.web.app/?a=1&code=abc-234#top'), 'ABC234');
    });

    test('parse rejects invalid input', () {
      expect(DropCodes.parse(''), isNull);
      expect(DropCodes.parse('ABC23'), isNull);
      expect(DropCodes.parse('ABC2345'), isNull);
      expect(DropCodes.parse('ABC10O'), isNull);
      expect(DropCodes.parse('https://x.web.app/'), isNull);
    });

    test('format splits the code', () {
      expect(DropCodes.format('ABC234'), 'ABC-234');
    });

    test('storageId is 20 alphanumerics', () {
      expect(RegExp(r'^[A-Za-z0-9]{20}$').hasMatch(DropCodes.storageId()), isTrue);
    });
  });

  group('format', () {
    test('formatBytes', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(50 * 1024 * 1024), '50 MB');
    });

    test('formatRemaining', () {
      final now = DateTime(2026, 1, 1, 12);
      expect(formatRemaining(now.subtract(const Duration(seconds: 1)), now), 'expired');
      expect(formatRemaining(now.add(const Duration(minutes: 5)), now), '5m');
      expect(formatRemaining(now.add(const Duration(hours: 2, minutes: 3)), now), '2h 3m');
      expect(formatRemaining(now.add(const Duration(days: 3, hours: 4)), now), '3d 4h');
    });

    test('formatDuration', () {
      expect(formatDuration(const Duration(minutes: 10)), '10 minutes');
      expect(formatDuration(const Duration(hours: 1)), '1 hour');
      expect(formatDuration(const Duration(days: 7)), '7 days');
    });
  });
}
