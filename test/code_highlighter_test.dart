import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/shared/widgets/code_highlighter.dart';

void main() {
  group('CodeHighlighter', () {
    test('format returns TextSpan for simple code', () {
      const highlighter = CodeHighlighter(isDark: false);
      final span = highlighter.format('print("hello")');

      expect(span, isA<TextSpan>());
      expect(span.style?.fontFamily, 'monospace');
    });

    test('format handles Dart code without throwing', () {
      const highlighter = CodeHighlighter(isDark: true);
      const code = '''
void main() {
  final greeting = 'Hello, World!';
  print(greeting);
  for (var i = 0; i < 5; i++) {
    print('Count: \$i');
  }
}
''';

      final span = highlighter.format(code);
      expect(span, isA<TextSpan>());
    });

    test('format handles JSON without throwing', () {
      const highlighter = CodeHighlighter(isDark: false);
      const code = '{"name": "Hermes", "version": 42, "active": true}';

      final span = highlighter.format(code);
      expect(span, isA<TextSpan>());
    });

    test('format handles empty string gracefully', () {
      const highlighter = CodeHighlighter(isDark: false);
      final span = highlighter.format('');

      expect(span, isA<TextSpan>());
    });

    test('dark and light themes produce different colors', () {
      const darkHighlighter = CodeHighlighter(isDark: true);
      const lightHighlighter = CodeHighlighter(isDark: false);

      const code = 'void main() {}';
      final darkSpan = darkHighlighter.format(code);
      final lightSpan = lightHighlighter.format(code);

      // Both should be TextSpans with monospace font
      expect(darkSpan.style?.fontFamily, 'monospace');
      expect(lightSpan.style?.fontFamily, 'monospace');

      // Default text color should differ between dark and light themes
      final darkColor = darkSpan.style?.color;
      final lightColor = lightSpan.style?.color;
      expect(darkColor, isNot(equals(lightColor)));
    });

    test('format handles Python code without throwing', () {
      const highlighter = CodeHighlighter(isDark: true);
      const code = '''
def hello(name: str) -> None:
    print(f"Hello, {name}!")

hello("World")
''';

      final span = highlighter.format(code);
      expect(span, isA<TextSpan>());
    });
  });
}
