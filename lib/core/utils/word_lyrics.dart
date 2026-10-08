import 'package:yaml/yaml.dart';

/// Convert LRCLIB Lyricsfile word timings to enhanced LRC. Keeping timings in
/// lrcLyrics preserves compatibility with the existing cache and offline library.
String? wordSyncedLrc(Map<String, dynamic> record) {
  final fallback = record['syncedLyrics'] as String?;
  final raw = record['lyricsfile'];
  if (raw is! String || raw.length > 500000) return fallback;
  try {
    final document = loadYaml(raw);
    if (document is! Map || document['lines'] is! List) return fallback;
    final output = <String>[];
    bool hasWords = false;
    for (final line in document['lines'] as List) {
      if (line is! Map || line['text'] is! String) return fallback;
      final words = line['words'];
      final start =
          line['start_ms'] ??
          (words is List && words.isNotEmpty && words.first is Map
              ? words.first['start_ms']
              : null);
      if (start is! int || start < 0) return fallback;
      final text = line['text'] as String;
      var content = text;
      if (words is List && words.isNotEmpty) {
        final buffer = StringBuffer();
        final reconstructed = StringBuffer();
        var previous = start;
        for (final word in words) {
          if (word is! Map ||
              word['text'] is! String ||
              word['start_ms'] is! int ||
              word['start_ms'] < previous) {
            return fallback;
          }
          final time = word['start_ms'] as int;
          buffer.write('<${_stamp(time)}>${word['text']}');
          reconstructed.write(word['text']);
          previous = time;
          final end = word['end_ms'];
          if (end is int && end >= time) {
            buffer.write('<${_stamp(end)}>');
            previous = end;
          }
        }
        if (reconstructed.toString() == text) {
          content = buffer.toString();
          hasWords = true;
        }
      }
      output.add('[${_stamp(start)}]$content');
    }
    return hasWords ? output.join('\n') : fallback;
  } catch (_) {
    // A malformed optional field must never break normal lyrics loading.
    return fallback;
  }
}

String _stamp(int ms) =>
    '${(ms ~/ 60000).toString().padLeft(2, '0')}:'
    '${(ms ~/ 1000 % 60).toString().padLeft(2, '0')}.'
    '${(ms % 1000).toString().padLeft(3, '0')}';
