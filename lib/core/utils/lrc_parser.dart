import 'package:flutter/foundation.dart';

/// Represents a single line in synced lyrics with timestamp
class LrcLine {
  final Duration timestamp;
  final String text;

  const LrcLine({required this.timestamp, required this.text});

  @override
  String toString() => '[$timestamp] $text';
}

/// Parsed LRC lyrics data
class ParsedLrc {
  final String? title;
  final String? artist;
  final String? album;
  final String? author;
  final Duration? offset;
  final List<LrcLine> lines;

  const ParsedLrc({
    this.title,
    this.artist,
    this.album,
    this.author,
    this.offset,
    required this.lines,
  });

  /// Get the line for a given position
  LrcLine? getLineAtTime(Duration position) {
    if (lines.isEmpty) return null;

    // Apply offset if present
    final adjustedPosition = offset != null ? position - offset! : position;

    LrcLine? currentLine;
    for (final line in lines) {
      if (line.timestamp <= adjustedPosition) {
        currentLine = line;
      } else {
        break;
      }
    }
    return currentLine;
  }

  /// Get index of the current line
  int getLineIndexAtTime(Duration position) {
    if (lines.isEmpty) return -1;

    final adjustedPosition = offset != null ? position - offset! : position;

    int currentIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].timestamp <= adjustedPosition) {
        currentIndex = i;
      } else {
        break;
      }
    }
    return currentIndex;
  }
}

/// Parser for LRC (synced lyrics) format
class LrcParser {
  // Regex patterns
  static final RegExp _timeTagPattern = RegExp(
    r'\[(\d{2}):(\d{2})\.(\d{2,3})\]',
  );
  static final RegExp _metaTagPattern = RegExp(
    r'\[(ti|ar|al|au|offset|length|by):(.+?)\]',
    caseSensitive: false,
  );

  /// Parse LRC string into structured data
  /// Uses compute for heavy parsing to avoid blocking UI
  static Future<ParsedLrc> parse(String lrc) async {
    return compute(_parseSync, lrc);
  }

  /// Synchronous parsing (for use in isolates)
  static ParsedLrc _parseSync(String lrc) {
    final lines = lrc.split('\n');

    String? title;
    String? artist;
    String? album;
    String? author;
    Duration? offset;
    final parsedLines = <LrcLine>[];

    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty) continue;

      // Check for metadata tags
      final metaMatch = _metaTagPattern.firstMatch(trimmedLine);
      if (metaMatch != null) {
        final tag = metaMatch.group(1)?.toLowerCase();
        final value = metaMatch.group(2)?.trim();

        switch (tag) {
          case 'ti':
            title = value;
            break;
          case 'ar':
            artist = value;
            break;
          case 'al':
            album = value;
            break;
          case 'au':
          case 'by':
            author = value;
            break;
          case 'offset':
            if (value != null) {
              final offsetMs = int.tryParse(value);
              if (offsetMs != null) {
                offset = Duration(milliseconds: offsetMs);
              }
            }
            break;
        }
        continue;
      }

      // Parse time tags and lyrics
      final timeMatches = _timeTagPattern.allMatches(trimmedLine).toList();
      if (timeMatches.isNotEmpty) {
        // Get the text after all time tags
        final lastMatch = timeMatches.last;
        final text = trimmedLine.substring(lastMatch.end).trim();

        // Create a line for each time tag (for repeated lines)
        for (final match in timeMatches) {
          final minutes = int.parse(match.group(1)!);
          final seconds = int.parse(match.group(2)!);
          final centiseconds = int.parse(match.group(3)!.padRight(3, '0'));

          final timestamp = Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: centiseconds,
          );

          parsedLines.add(LrcLine(timestamp: timestamp, text: text));
        }
      }
    }

    // Sort by timestamp
    parsedLines.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return ParsedLrc(
      title: title,
      artist: artist,
      album: album,
      author: author,
      offset: offset,
      lines: parsedLines,
    );
  }

  /// Quick check if string is valid LRC format
  static bool isValidLrc(String text) {
    return _timeTagPattern.hasMatch(text);
  }

  /// Convert parsed LRC back to plain text
  static String toPlainText(ParsedLrc lrc) {
    return lrc.lines.map((l) => l.text).join('\n');
  }

  /// Strip all LRC timestamp tags from a line or block of text
  /// e.g. "[00:12.34]Hello [00:15.00]world" -> "Hello world"
  static String stripTimeTags(String text) {
    if (text.isEmpty) return text;
    // Remove all occurrences of [mm:ss.xx] or [mm:ss.xxx]
    var cleaned = text.replaceAll(_timeTagPattern, '');
    // Also remove metadata tags like [ti:...], [ar:...] etc. that may remain
    cleaned = cleaned.replaceAll(_metaTagPattern, '');
    // Remove any residual brackets that look like timestamps but with single digit
    cleaned = cleaned.replaceAll(RegExp(r'\[\d{1,2}:\d{2}(\.\d{1,3})?\]'), '');
    return cleaned.trim();
  }

  /// Strip timestamps from each line and return cleaned lines
  static List<String> stripTimeTagsFromLines(List<String> lines) {
    return lines.map((l) => stripTimeTags(l)).toList();
  }

  /// Detect if text likely contains LRC timestamps
  static bool containsTimeTags(String text) {
    return _timeTagPattern.hasMatch(text);
  }

  /// Convert any raw lyrics (possibly LRC) to clean plain text without timestamps
  static String toCleanPlainText(String raw) {
    if (!containsTimeTags(raw)) return raw;
    final lines = raw.split('\n');
    final cleaned = <String>[];
    for (final line in lines) {
      final stripped = stripTimeTags(line);
      // Preserve empty lines as paragraph breaks but avoid adding empty due to pure timestamp lines
      if (line.trim().isEmpty) {
        cleaned.add('');
      } else if (stripped.isEmpty) {
        // Line was only timestamp/marker - skip
        continue;
      } else {
        cleaned.add(stripped);
      }
    }
    return cleaned.join('\n');
  }
}
