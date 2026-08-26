import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'ffm_assistant_external_link.dart';

class FfmAssistantMarkdownText extends StatelessWidget {
  const FfmAssistantMarkdownText({
    required this.text,
    required this.color,
    this.fontSize = 16.5,
    this.onOpenLink,
    super.key,
  });

  final String text;
  final Color color;
  final double fontSize;
  final Future<bool> Function(Uri uri)? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final children = <Widget>[];
    var inCode = false;
    final codeLines = <String>[];

    void flushCode() {
      if (codeLines.isEmpty) return;
      children.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(9),
          ),
          child: SelectableText(
            codeLines.join('\n'),
            style: TextStyle(
              color: color,
              fontFamily: 'monospace',
              fontSize: fontSize - 3,
              height: 1.35,
            ),
          ),
        ),
      );
      codeLines.clear();
    }

    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      if (line.trimLeft().startsWith('```')) {
        if (inCode) {
          flushCode();
          inCode = false;
        } else {
          inCode = true;
        }
        continue;
      }
      if (inCode) {
        codeLines.add(line);
        continue;
      }
      if (line.trim().isEmpty) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 6));
        continue;
      }

      final trimmed = line.trimLeft();
      final heading = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(trimmed);
      final bullet = RegExp(r'^([-*])\s+(.*)$').firstMatch(trimmed);
      final numbered = RegExp(r'^(\d+)[.)]\s+(.*)$').firstMatch(trimmed);
      final quote = trimmed.startsWith('> ')
          ? trimmed.substring(2).trim()
          : null;

      if (heading != null) {
        final level = heading.group(1)!.length;
        children.add(
          Padding(
            padding: EdgeInsets.only(top: level == 1 ? 7 : 3, bottom: 2),
            child: Text.rich(
              _inlineSpans(heading.group(2)!, color, bold: true),
              style: TextStyle(
                color: color,
                fontSize: level == 1
                    ? fontSize + 2
                    : level == 2
                    ? fontSize + 1
                    : fontSize,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        );
      } else if (bullet != null || numbered != null) {
        final marker = bullet?.group(1) ?? '${numbered!.group(1)}.';
        final content = bullet?.group(2) ?? numbered!.group(2)!;
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    marker == '-' || marker == '*' ? '•' : marker,
                    style: TextStyle(
                      color: color,
                      height: 1.42,
                      fontSize: fontSize,
                    ),
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    _inlineSpans(content, color),
                    style: TextStyle(
                      color: color,
                      height: 1.45,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (quote != null) {
        children.add(
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: color.withValues(alpha: .55), width: 3),
              ),
            ),
            child: Text.rich(
              _inlineSpans(quote, color),
              style: TextStyle(
                color: color,
                fontStyle: FontStyle.italic,
                height: 1.42,
                fontSize: fontSize,
              ),
            ),
          ),
        );
      } else {
        children.add(
          Text.rich(
            _inlineSpans(line.trim(), color),
            style: TextStyle(
              color: color,
              height: 1.45,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }
    }
    if (inCode) flushCode();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  InlineSpan _inlineSpans(String value, Color color, {bool bold = false}) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'(\*\*|__)(.+?)\1');
    var cursor = 0;
    for (final match in pattern.allMatches(value)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(
            children: _linkSpans(
              value.substring(cursor, match.start),
              color,
              bold: bold,
            ),
          ),
        );
      }
      spans.add(
        TextSpan(
          children: _linkSpans(match.group(2)!, color, bold: true),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      );
      cursor = match.end;
    }
    if (cursor < value.length) {
      spans.add(
        TextSpan(
          children: _linkSpans(value.substring(cursor), color, bold: bold),
        ),
      );
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(children: _linkSpans(value, color, bold: bold)));
    }
    if (bold) {
      return TextSpan(
        children: spans
            .map(
              (span) => span is TextSpan
                  ? TextSpan(
                      text: span.text,
                      children: span.children,
                      style:
                          span.style?.copyWith(fontWeight: FontWeight.w900) ??
                          const TextStyle(fontWeight: FontWeight.w900),
                    )
                  : span,
            )
            .toList(growable: false),
      );
    }
    return TextSpan(children: spans);
  }

  List<InlineSpan> _linkSpans(String value, Color color, {required bool bold}) {
    final spans = <InlineSpan>[];
    final inlineCode = RegExp(r'`([^`]+)`');
    var cursor = 0;
    for (final match in inlineCode.allMatches(value)) {
      if (match.start > cursor) {
        spans.addAll(
          _plainOrLinkSpans(
            value.substring(cursor, match.start),
            color,
            bold: bold,
          ),
        );
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: TextStyle(
            color: color,
            fontFamily: 'monospace',
            fontSize: 12.5,
            fontWeight: bold ? FontWeight.w800 : null,
            backgroundColor: color.withValues(alpha: .12),
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < value.length) {
      spans.addAll(
        _plainOrLinkSpans(value.substring(cursor), color, bold: bold),
      );
    }
    return spans;
  }

  List<InlineSpan> _plainOrLinkSpans(
    String value,
    Color color, {
    required bool bold,
  }) {
    final spans = <InlineSpan>[];
    final links = FfmAssistantExternalLinkParser.parse(value);
    var cursor = 0;
    for (final link in links) {
      if (link.start > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, link.start)));
      }
      final linkColor = color.computeLuminance() > .45
          ? const Color(0xFF9BE8E0)
          : const Color(0xFF006E64);
      spans.add(
        TextSpan(
          text: link.label,
          semanticsLabel: 'Buka tautan eksternal ${link.label}',
          recognizer: TapGestureRecognizer()
            ..onTap = () => unawaited(_openLink(link.uri)),
          style: TextStyle(
            color: linkColor,
            fontWeight: bold ? FontWeight.w800 : null,
            decoration: TextDecoration.underline,
            decorationColor: linkColor,
          ),
        ),
      );
      cursor = link.end;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor)));
    }
    return spans;
  }

  Future<bool> _openLink(Uri uri) =>
      onOpenLink?.call(uri) ?? FfmAssistantExternalLinkOpener.open(uri);
}
