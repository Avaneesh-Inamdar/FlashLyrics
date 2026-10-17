import 'lrc_parser.dart';

/// Optional visual approximation only. Never stored as provider word timings.
List<LrcWord> estimateWords(LrcLine line, Duration? nextLine) {
  if (line.words.isNotEmpty) return line.words;
  if (nextLine == null ||
      nextLine <= line.timestamp ||
      line.text.trim().isEmpty) {
    return const [];
  }
  final tokens = RegExp(
    r'\S+\s*',
    unicode: true,
  ).allMatches(line.text).map((m) => m.group(0)!).toList();
  if (tokens.length < 2) return const [];
  final duration = (nextLine - line.timestamp).inMilliseconds.clamp(1, 10000);
  final total = tokens.fold<int>(0, (n, t) => n + t.trim().runes.length);
  var consumed = 0;
  return tokens.map((text) {
    final start = consumed;
    consumed += text.trim().runes.length;
    return LrcWord(
      text: text,
      start:
          line.timestamp +
          Duration(milliseconds: (duration * start / total).round()),
      end:
          line.timestamp +
          Duration(milliseconds: (duration * consumed / total).round()),
    );
  }).toList();
}
