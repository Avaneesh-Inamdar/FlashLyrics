import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricx/core/utils/lyrics_image_generator.dart';
import 'package:lyricx/domain/entities/song.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'exported PNG from imported LRC is identical to clean lyric image',
    () async {
      await (FontLoader(
        'Ahem',
      )..addFont(rootBundle.load('assets/fonts/Manrope-Regular.ttf'))).load();
      final directory = await Directory(
        'build/share-export-v16',
      ).create(recursive: true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => directory.absolute.path,
          );
      const tagged =
          '[ti:Test]\n[00:01.50]<00:01.50>Hello <00:02.00>world\n[00:04.00]Next line';
      final song = Song(
        id: 'test',
        title: 'Test song',
        artist: 'Artist',
        artworkUrl: Uri.file(File('icon/Icon.png').absolute.path).toString(),
      );
      final imported = await LyricsImageGenerator.generateLyricsImage(
        song: song,
        lines: [tagged],
        isDark: true,
      );
      final plain = await LyricsImageGenerator.generateLyricsImage(
        song: song,
        lines: ['Hello world', 'Next line'],
        isDark: true,
      );
      expect(imported, isNotNull);
      expect(plain, isNotNull);
      final imageBytes = await imported!.readAsBytes();
      expect(imageBytes, await plain!.readAsBytes());
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 1080);
      expect(frame.image.height, greaterThan(300));
      frame.image.dispose();
      codec.dispose();
      await imported.copy('${directory.path}/imported-lyrics.png');
    },
  );
}
