import 'package:url_launcher/url_launcher.dart';

class FfmAssistantExternalLink {
  const FfmAssistantExternalLink({
    required this.start,
    required this.end,
    required this.label,
    required this.uri,
  });

  final int start;
  final int end;
  final String label;
  final Uri uri;
}

class FfmAssistantExternalLinkParser {
  const FfmAssistantExternalLinkParser._();

  static final RegExp _candidatePattern = RegExp(
    r'\[([^\]\r\n]+)\]\(([^()\s]+)\)|(?:https?://|www\.)[^\s<]+',
    caseSensitive: false,
  );
  static final RegExp _trailingPunctuation = RegExp(r'[.,;:!?\]\}]+$');

  static List<FfmAssistantExternalLink> parse(String text) {
    final links = <FfmAssistantExternalLink>[];
    for (final match in _candidatePattern.allMatches(text)) {
      final markdownLabel = match.group(1);
      final markdownTarget = match.group(2);
      final isMarkdown = markdownLabel != null && markdownTarget != null;
      final rawTarget = markdownTarget ?? match.group(0)!;
      final target = isMarkdown
          ? rawTarget
          : rawTarget.replaceFirst(_trailingPunctuation, '');
      if (target.isEmpty) continue;
      final uri = _toSafeExternalUri(target);
      if (uri == null) continue;
      final end = isMarkdown ? match.end : match.start + target.length;
      links.add(
        FfmAssistantExternalLink(
          start: match.start,
          end: end,
          label: markdownLabel ?? target,
          uri: uri,
        ),
      );
    }
    return links;
  }

  static Uri? _toSafeExternalUri(String value) {
    final normalized = value.toLowerCase().startsWith('www.')
        ? 'https://$value'
        : value;
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') return null;
    return uri;
  }
}

class FfmAssistantExternalLinkOpener {
  const FfmAssistantExternalLinkOpener._();

  static Future<bool> open(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
