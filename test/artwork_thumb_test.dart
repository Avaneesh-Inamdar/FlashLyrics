import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyricx/presentation/widgets/artwork_thumb.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final lookups = <String>[];
  const placeholderKey = Key('placeholder');

  setUp(() {
    lookups.clear();
    ArtworkThumb.resetCache();
    ArtworkThumb.lookup = (artist, title) async {
      lookups.add('$artist|$title');
      return 'https://is1-ssl.mzstatic.com/$title.jpg';
    };
  });

  Widget thumb(String? url, {String title = 'Song', String artist = 'Artist'}) =>
      MaterialApp(
        home: SizedBox(
          width: 48,
          height: 48,
          child: ArtworkThumb(
            artworkUrl: url,
            title: title,
            artist: artist,
            placeholder: const SizedBox(key: placeholderKey),
          ),
        ),
      );

  String? imageSource(WidgetTester tester) {
    final images = tester.widgetList<Image>(find.byType(Image));
    if (images.isEmpty) return null;
    final provider = images.first.image;
    if (provider is ResizeImage) {
      final inner = provider.imageProvider;
      if (inner is NetworkImage) return inner.url;
      if (inner is FileImage) {
        return 'file://${inner.file.path.replaceAll(r'\', '/')}';
      }
    }
    return provider.toString();
  }

  test('normalize keeps displayable artwork and rejects the rest', () {
    expect(ArtworkThumb.normalize(null), isNull);
    expect(ArtworkThumb.normalize('  '), isNull);
    expect(ArtworkThumb.normalize('content://media/1/albumart'), isNull);
    expect(ArtworkThumb.normalize('ftp://x/y.jpg'), isNull);
    expect(ArtworkThumb.normalize('http://a.com/x.jpg'), 'https://a.com/x.jpg');
    expect(
      ArtworkThumb.normalize('https://a.com/{w}x{h}bb.jpg'),
      'https://a.com/300x300bb.jpg',
    );
    expect(
      ArtworkThumb.normalize('file:/data/user/0/app/cache/art.png'),
      'file:///data/user/0/app/cache/art.png',
    );
    expect(
      ArtworkThumb.normalize('file:///data/cache/art.png'),
      'file:///data/cache/art.png',
    );
  });

  test('reads iTunes results whether they arrive as text or JSON', () {
    const body =
        '{"resultCount":1,"results":[{"trackName":"Heroes Tonight",'
        '"artworkUrl100":"https://is1-ssl.mzstatic.com/a/100x100bb.jpg"}]}';
    const expected = 'https://is1-ssl.mzstatic.com/a/300x300bb.jpg';
    // iTunes replies with Content-Type text/javascript, so Dio gives a string.
    expect(ArtworkThumb.parseItunesArtwork(body), expected);
    expect(
      ArtworkThumb.parseItunesArtwork({
        'results': [
          {'artworkUrl100': 'https://is1-ssl.mzstatic.com/a/100x100bb.jpg'},
        ],
      }),
      expected,
    );
    expect(ArtworkThumb.parseItunesArtwork('{"resultCount":0,"results":[]}'), isNull);
    expect(ArtworkThumb.parseItunesArtwork('not json'), isNull);
    expect(ArtworkThumb.parseItunesArtwork(null), isNull);
    expect(
      ArtworkThumb.parseItunesArtwork('{"results":[{"artworkUrl100":""}]}'),
      isNull,
    );
  });

  testWidgets('web artwork is shown without a lookup', (tester) async {
    await tester.pumpWidget(thumb('https://a.com/cover.jpg'));
    expect(imageSource(tester), 'https://a.com/cover.jpg');
    expect(lookups, isEmpty);
  });

  testWidgets('artwork saved by the music player is shown from the file', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('art');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/art_song.png')
      ..writeAsBytesSync(List.filled(16, 0));
    final url = Uri.file(file.path).toString();
    await tester.runAsync(() async {
      await tester.pumpWidget(thumb(url));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(imageSource(tester), 'file://${file.path.replaceAll(r'\', '/')}');
    expect(lookups, isEmpty);
  });

  for (final url in [
    null,
    '',
    'content://media/external/audio/albumart/7',
    'file:///no/such/cleared/cache/art.png',
  ]) {
    testWidgets('missing artwork ($url) falls back to a lookup', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(thumb(url, title: 'Mortals', artist: 'Warriyo'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(lookups, ['Warriyo|Mortals']);
      expect(imageSource(tester), 'https://is1-ssl.mzstatic.com/Mortals.jpg');
    });
  }

  testWidgets('no artwork found keeps the placeholder', (tester) async {
    ArtworkThumb.lookup = (artist, title) async => null;
    await tester.runAsync(() async {
      await tester.pumpWidget(thumb(null));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.byKey(placeholderKey), findsOneWidget);
  });

  testWidgets('each song is looked up once for the whole library', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              for (var i = 0; i < 3; i++)
                SizedBox(
                  width: 48,
                  height: 48,
                  child: ArtworkThumb(
                    artworkUrl: null,
                    title: 'Royalty',
                    artist: 'Egzod',
                    placeholder: const SizedBox(),
                  ),
                ),
            ],
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(lookups, ['Egzod|Royalty']);
  });
}
