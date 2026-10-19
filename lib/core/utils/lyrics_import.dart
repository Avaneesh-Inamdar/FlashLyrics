import 'dart:convert';
import 'dart:typed_data';
import '../../data/models/lyrics_model.dart';
import '../../domain/entities/song.dart';
import 'lrc_parser.dart';
import 'song_key.dart';

/// Local imports use the same Unicode-aware identity and cache as online lyrics.
class LyricsImport {
  static const maxBytes = 256 * 1024;
  static final _lineTime = RegExp(r'^\[(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?\]');
  static final _wordTime = RegExp(r'<(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?>');
  static final _metadata = RegExp(
    r'^\[(ti|ar|al|au|by|length|re|ve|offset):([^\]]*)\]$',
    caseSensitive: false,
  );

  static String decode(Uint8List bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('Choose a lyrics file smaller than 256 KB.');
    }
    if (bytes.length >= 2 &&
        ((bytes[0] == 255 && bytes[1] == 254) ||
            (bytes[0] == 254 && bytes[1] == 255))) {
      if (bytes.length.isOdd) {
        throw const FormatException('The UTF-16 file is incomplete.');
      }
      final data = ByteData.sublistView(bytes);
      final endian = bytes[0] == 255 ? Endian.little : Endian.big;
      return String.fromCharCodes([
        for (var i = 2; i < bytes.length; i += 2) data.getUint16(i, endian),
      ]);
    }
    try {
      return utf8.decode(bytes).replaceFirst(RegExp('^\uFEFF'), '');
    } on FormatException {
      throw const FormatException(
        'Save the file as UTF-8 or UTF-16 text and try again.',
      );
    }
  }

  static Map<String, String> metadata(String text) {
    final output = <String, String>{};
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final match = _metadata.firstMatch(line.trim());
      if (match != null) output[match[1]!.toLowerCase()] = match[2]!.trim();
    }
    return output;
  }

  static int _ms(Match match) {
    final seconds = int.parse(match[2]!);
    if (seconds >= 60) {
      throw const FormatException(
        'Timestamp seconds must be between 00 and 59.',
      );
    }
    return int.parse(match[1]!) * 60000 +
        seconds * 1000 +
        int.parse((match[3] ?? '0').padRight(3, '0'));
  }

  static Future<LyricsModel> parse(String input, Song song) async {
    final raw = input
        .replaceFirst(RegExp('^\uFEFF'), '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    if (raw.isEmpty) {
      throw const FormatException('Paste lyrics or choose a text file first.');
    }
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Keep imported lyrics smaller than 256 KB.');
    }
    if (raw.contains(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'))) {
      throw const FormatException('This file is not readable lyrics text.');
    }
    if (songKey('', song.title).isEmpty || songKey('', song.artist).isEmpty) {
      throw const FormatException('Enter a song title and artist.');
    }
    final lines = raw.split('\n');
    if (lines.length > 2000) {
      throw const FormatException('Keep imported lyrics under 2,000 lines.');
    }
    var timed = false;
    var untimed = false;
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim();
      if (line.isEmpty) continue;
      final meta = _metadata.firstMatch(line);
      if (meta != null) {
        if (meta[1]!.toLowerCase() == 'offset' &&
            int.tryParse(meta[2]!) == null) {
          throw const FormatException(
            'The offset tag must contain milliseconds, such as [offset:250].',
          );
        }
        continue;
      }
      final stamps = <int>[];
      Match? match;
      while ((match = _lineTime.firstMatch(line)) != null) {
        stamps.add(_ms(match!));
        line = line.substring(match.end).trimLeft();
      }
      if (stamps.isEmpty) {
        untimed = true;
        if (line.contains(RegExp(r'^[\[<]?\d{1,3}:')) ||
            line.contains(_wordTime)) {
          throw FormatException(
            'Check the timestamp on line ${i + 1}. Use [00:12.50] before the lyrics.',
          );
        }
      } else {
        timed = true;
        var previous = stamps.first;
        for (final word in _wordTime.allMatches(line)) {
          final ms = _ms(word);
          if (ms < previous) {
            throw FormatException(
              'Word timestamps on line ${i + 1} must run forward from the line timestamp.',
            );
          }
          previous = ms;
        }
        final remainder = line.replaceAll(_wordTime, '');
        if (remainder.contains(RegExp(r'[<\[]\d{1,3}:'))) {
          throw FormatException('Check the timestamp on line ${i + 1}.');
        }
      }
    }
    if (timed && untimed) {
      throw const FormatException(
        'Add [mm:ss.xx] to every lyric line, or remove all timestamps to save plain lyrics.',
      );
    }
    final parsed = timed ? await LrcParser.parse(raw) : null;
    final plain = parsed == null
        ? lines
              .where((line) => !_metadata.hasMatch(line.trim()))
              .join('\n')
              .trim()
        : LrcParser.toPlainText(parsed).trim();
    if (plain.isEmpty) {
      throw const FormatException('The text contains no lyrics.');
    }
    return LyricsModel(
      id: 'import_${DateTime.now().microsecondsSinceEpoch}',
      songId: songKey(song.artist, song.title),
      trackName: song.title.trim(),
      artistName: song.artist.trim(),
      albumName: song.album,
      artworkUrl: song.artworkUrl,
      plainLyrics: plain,
      lrcLyrics: timed ? raw : null,
      isSynced: timed,
      source: 'Imported',
      isUserProvided: true,
      isMatchVerified: true,
      fetchedAt: DateTime.now(),
    );
  }
}
