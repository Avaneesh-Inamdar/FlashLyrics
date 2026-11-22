/// Converts a TTML document (as returned by the BetterLyrics API) to a
/// line-synced LRC string. Word-level spans are flattened to plain line text so
/// the result is always safe for the regular LRC parser.
String? ttmlToLrc(String ttml) {
  if (ttml.length > 2000000) return null;
  final lines = <String>[];
  final paragraph = RegExp(
    r'<p\b([^>]*)>(.*?)</p>',
    dotAll: true,
    caseSensitive: false,
  );
  final beginAttr = RegExp(r'\bbegin="([^"]+)"');
  for (final match in paragraph.allMatches(ttml)) {
    final begin = beginAttr.firstMatch(match.group(1) ?? '');
    if (begin == null) continue;
    final ms = parseTtmlTime(begin.group(1)!);
    if (ms == null) continue;
    // Drop background-vocal / translation spans' tags, keep the text.
    final text = _decode(
      match.group(2)!.replaceAll(RegExp(r'<[^>]+>'), ''),
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) continue;
    lines.add('[${_stamp(ms)}]$text');
  }
  if (lines.isEmpty) return null;
  return lines.join('\n');
}

/// Parses TTML clock values: "33.642", "1:02.5", "01:02:03.5", "12.5s", "500ms".
int? parseTtmlTime(String value) {
  final v = value.trim();
  if (v.isEmpty) return null;
  if (v.endsWith('ms')) {
    final n = double.tryParse(v.substring(0, v.length - 2));
    return n == null ? null : n.round();
  }
  if (v.endsWith('s')) {
    final n = double.tryParse(v.substring(0, v.length - 1));
    return n == null ? null : (n * 1000).round();
  }
  final parts = v.split(':');
  if (parts.length > 3) return null;
  var seconds = 0.0;
  for (final part in parts) {
    final n = double.tryParse(part);
    if (n == null) return null;
    seconds = seconds * 60 + n;
  }
  return (seconds * 1000).round();
}

String _stamp(int ms) {
  final minutes = ms ~/ 60000;
  final seconds = (ms % 60000) / 1000;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toStringAsFixed(2).padLeft(5, '0')}';
}

String _decode(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&#39;', "'");
