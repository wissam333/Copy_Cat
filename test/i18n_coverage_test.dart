// Guards the EN map: every Arabic string literal in lib/ must exist as a
// key in i18n.dart's _en map, so EN mode can never show bare Arabic.
// (Wrapped-but-unmapped was the bug behind "من سيلعب؟" showing in English.)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every Arabic literal in lib/ has an English entry', () {
    final i18nSrc = File('lib/i18n.dart').readAsStringSync();
    final one = RegExp(r"'((?:[^'\\\n]|\\.)*)'");
    // Map keys, joining adjacent literal pieces (keys may be wrapped).
    final defined = RegExp(
            r"'(?:[^'\\\n]|\\.)*'(?:\s*'(?:[^'\\\n]|\\.)*')*(?=\s*:)")
        .allMatches(i18nSrc)
        .map((m) => one.allMatches(m.group(0)!).map((e) => e.group(1)!).join())
        .toSet();

    // Shown as-is by design: the toggle pill offers the OTHER language.
    const exemptLiterals = {'عربي'};
    // Translates via parallel EN arrays, not the map.
    const exemptFiles = {'lib\\funny_lines.dart', 'lib/i18n.dart'};

    // A maximal run of adjacent string literals (Dart concatenates them,
    // so the runtime key is the joined text).
    final run = RegExp(r"'(?:[^'\\\n]|\\.)*'(?:\s*'(?:[^'\\\n]|\\.)*')*");
    final arabic = RegExp(r'[\u0600-\u06FF]');

    final missing = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !exemptFiles.contains(f.path))) {
      final src = _stripLineComments(f.readAsStringSync());
      for (final m in run.allMatches(src)) {
        final key = one.allMatches(m.group(0)!).map((e) => e.group(1)!).join();
        if (key.contains(arabic) &&
            !defined.contains(key) &&
            !exemptLiterals.contains(key)) {
          missing.add('${f.path}: $key');
        }
      }
    }
    expect(missing, isEmpty,
        reason: 'Keys used in lib/ but missing from the _en map '
            '(EN mode shows these as bare Arabic):\n${missing.join('\n')}');
  });
}

/// Cuts `//` comments, but only when the cut point is outside a string
/// literal (even number of quotes before it) — keeps URLs in strings intact.
String _stripLineComments(String src) {
  final out = <String>[];
  for (final line in src.split('\n')) {
    var quotes = 0;
    var cut = line.length;
    for (var i = 0; i < line.length - 1; i++) {
      if (line[i] == "'" && (i == 0 || line[i - 1] != r'\')) quotes++;
      if (line[i] == '/' &&
          line[i + 1] == '/' &&
          quotes % 2 == 0 &&
          cut == line.length) {
        cut = i;
      }
    }
    out.add(line.substring(0, cut));
  }
  return out.join('\n');
}
