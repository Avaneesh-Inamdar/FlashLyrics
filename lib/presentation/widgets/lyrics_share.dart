import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/lrc_parser.dart';
import '../../core/utils/lyrics_image_generator.dart';
import '../../data/models/lyrics_model.dart';
import '../../domain/entities/lyrics.dart';
import '../../domain/entities/song.dart';

/// The song shown with [lyrics]: the lyrics' own track details when known
/// (with the playing song's artwork if it is the same track), otherwise the
/// song that is playing.
Song? songForLyrics(Lyrics lyrics, Song? current) {
  if (lyrics is LyricsModel &&
      lyrics.trackName != null &&
      lyrics.artistName != null) {
    final sameTrack =
        current?.title == lyrics.trackName &&
        current?.artist == lyrics.artistName;
    return Song(
      id: lyrics.songId,
      title: lyrics.trackName!,
      artist: lyrics.artistName!,
      album: lyrics.albumName,
      artworkUrl: lyrics.artworkUrl ?? (sameTrack ? current?.artworkUrl : null),
    );
  }
  return current;
}

/// Shares [lines] as a lyrics image for [song], falling back to plain text if
/// the image can't be made. Shows progress and errors as snack bars.
/// Timestamps and blank lines are removed first.
Future<void> shareLyricLines(
  BuildContext context, {
  required Song? song,
  required List<String> lines,
}) async {
  final cleaned = lines
      .map(LrcParser.stripTimeTags)
      .where((line) => line.trim().isNotEmpty)
      .toList();
  if (cleaned.isEmpty) return;
  if (song == null) {
    await Share.share('${cleaned.join('\n')}\n\n— Shared via FlashLyrics');
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      content: const Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          SizedBox(width: 12),
          Text('Creating lyrics image...'),
        ],
      ),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppTheme.surfaceLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 30),
    ),
  );

  try {
    final imageFile = await LyricsImageGenerator.generateLyricsImage(
      song: song,
      lines: cleaned,
      isDark: Theme.of(context).brightness == Brightness.dark,
    );
    messenger.clearSnackBars();
    if (imageFile != null) {
      await Share.shareXFiles(
        [XFile(imageFile.path)],
        text: '${song.title} - ${song.artist}\n\nShared from FlashLyrics',
      );
    } else {
      await Share.share(
        '${song.title} - ${song.artist}\n\n${cleaned.join('\n')}\n\n— Shared via FlashLyrics',
      );
    }
  } catch (e) {
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text('Error sharing: $e')),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.surfaceLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
