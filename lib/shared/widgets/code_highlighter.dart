import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:highlight/highlight.dart';

/// Syntax highlighter for flutter_markdown code blocks.
///
/// Uses the `highlight` package with auto-detection to render
/// code with syntax-aware coloring. Falls back to plain monospace
/// if parsing fails.
class CodeHighlighter implements SyntaxHighlighter {
  final bool isDark;

  const CodeHighlighter({this.isDark = false});

  static const _darkTheme = {
    'keyword': Color(0xFFC678DD),
    'built_in': Color(0xFFE5C07B),
    'type': Color(0xFFE5C07B),
    'literal': Color(0xFFD19A66),
    'number': Color(0xFFD19A66),
    'operator': Color(0xFF56B6C2),
    'punctuation': Color(0xFFABB2BF),
    'property': Color(0xFFE06C75),
    'regexp': Color(0xFF98C379),
    'string': Color(0xFF98C379),
    'char.escape_': Color(0xFF98C379),
    'variable': Color(0xFFE06C75),
    'variable.constant_': Color(0xFFD19A66),
    'variable.language_': Color(0xFFC678DD),
    'title': Color(0xFF61AFEF),
    'title.function_': Color(0xFF61AFEF),
    'title.class_': Color(0xFFE5C07B),
    'params': Color(0xFFABB2BF),
    'comment': Color(0xFF7F848E),
    'doctag': Color(0xFF7F848E),
    'meta': Color(0xFF7F848E),
    'section': Color(0xFFE5C07B),
    'tag': Color(0xFFE06C75),
    'name': Color(0xFFE06C75),
    'attr': Color(0xFFD19A66),
    'attribute': Color(0xFFD19A66),
    'symbol': Color(0xFF56B6C2),
    'bullet': Color(0xFFD19A66),
    'addition': Color(0xFF98C379),
    'deletion': Color(0xFFE06C75),
    'change': Color(0xFFD19A66),
  };

  static const _lightTheme = {
    'keyword': Color(0xFFA626A4),
    'built_in': Color(0xFFC18401),
    'type': Color(0xFFC18401),
    'literal': Color(0xFF986801),
    'number': Color(0xFF986801),
    'operator': Color(0xFF0184BC),
    'punctuation': Color(0xFF383A42),
    'property': Color(0xFFE45649),
    'regexp': Color(0xFF50A14F),
    'string': Color(0xFF50A14F),
    'char.escape_': Color(0xFF50A14F),
    'variable': Color(0xFFE45649),
    'variable.constant_': Color(0xFF986801),
    'variable.language_': Color(0xFFA626A4),
    'title': Color(0xFF4078F2),
    'title.function_': Color(0xFF4078F2),
    'title.class_': Color(0xFFC18401),
    'params': Color(0xFF383A42),
    'comment': Color(0xFFA0A1A7),
    'doctag': Color(0xFFA0A1A7),
    'meta': Color(0xFFA0A1A7),
    'section': Color(0xFFC18401),
    'tag': Color(0xFFE45649),
    'name': Color(0xFFE45649),
    'attr': Color(0xFF986801),
    'attribute': Color(0xFF986801),
    'symbol': Color(0xFF0184BC),
    'bullet': Color(0xFF986801),
    'addition': Color(0xFF50A14F),
    'deletion': Color(0xFFE45649),
    'change': Color(0xFF986801),
  };

  @override
  TextSpan format(String source) {
    try {
      final result = highlight.parse(source, autoDetection: true);
      final theme = isDark ? _darkTheme : _lightTheme;
      final nodes = result.nodes ?? [Node(value: source)];
      final children = nodes.map((n) => _nodeToSpan(n, theme)).toList();
      return TextSpan(
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: isDark ? const Color(0xFFABB2BF) : const Color(0xFF383A42),
        ),
        children: children,
      );
    } catch (_) {
      return TextSpan(
        text: source,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: isDark ? Colors.white70 : Colors.black87,
        ),
      );
    }
  }

  TextSpan _nodeToSpan(Node node, Map<String, Color> theme) {
    final color = node.className != null ? theme[node.className] : null;
    final style = color != null ? TextStyle(color: color) : null;

    if (node.value != null) {
      return TextSpan(text: node.value, style: style);
    }

    if (node.children != null) {
      return TextSpan(
        style: style,
        children: node.children!.map((n) => _nodeToSpan(n, theme)).toList(),
      );
    }

    return TextSpan(text: '', style: style);
  }
}
