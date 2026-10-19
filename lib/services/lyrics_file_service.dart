import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/lyrics_import.dart';

final lyricsFileServiceProvider = Provider((ref) => LyricsFileService());

class LyricsFileService {
  Future<String?> pickText() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Lyrics',
          extensions: ['lrc', 'txt'],
          mimeTypes: ['text/*', 'application/octet-stream'],
        ),
      ],
    );
    if (file == null) return null;
    return read(file);
  }

  Future<String> read(XFile file) async {
    final extension = file.name.split('.').last.toLowerCase();
    if (!['lrc', 'txt'].contains(extension)) {
      throw const FormatException('Choose a .lrc or .txt lyrics file.');
    }
    if (await file.length() > LyricsImport.maxBytes) {
      throw const FormatException('Choose a lyrics file smaller than 256 KB.');
    }
    final output = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (output.length + chunk.length > LyricsImport.maxBytes) {
        throw const FormatException(
          'Choose a lyrics file smaller than 256 KB.',
        );
      }
      output.add(chunk);
    }
    return LyricsImport.decode(output.takeBytes());
  }
}
