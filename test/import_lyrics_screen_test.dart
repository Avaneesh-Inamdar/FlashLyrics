import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyricx/core/utils/lyrics_import.dart';
import 'package:lyricx/data/datasources/lyrics_local_datasource.dart';
import 'package:lyricx/data/models/lyrics_model.dart';
import 'package:lyricx/presentation/providers/providers.dart';
import 'package:lyricx/presentation/screens/import_lyrics_screen.dart';
import 'package:lyricx/services/lyrics_file_service.dart';
import 'lyrics_import_test.dart' show CountingRemote, target, timed;

class SelectedFile extends LyricsFileService {
  SelectedFile(this.text);
  String? text;
  bool fail = false;
  @override
  Future<String?> pickText() async {
    if (fail) throw Exception('Unreadable file');
    return text;
  }
}

class FailingStorage extends LyricsLocalDataSource {
  FailingStorage(super.prefs);
  @override
  Future<void> cacheLyrics(
    LyricsModel lyrics, {
    bool preserveUserProvided = false,
  }) async => throw Exception('Disk full');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<ProviderContainer> launch(
    WidgetTester tester, {
    bool blank = false,
    SelectedFile? file,
    bool fail = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        lyricsRemoteDataSourceProvider.overrideWithValue(CountingRemote()),
        if (file != null) lyricsFileServiceProvider.overrideWithValue(file),
        if (fail)
          lyricsLocalDataSourceProvider.overrideWithValue(
            FailingStorage(prefs),
          ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ImportLyricsScreen(song: blank ? null : target),
                  ),
                ),
                child: const Text('Open import'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open import'));
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> action(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      find.text(label),
      label == 'Choose lyrics file' ? -160 : 160,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
    await tester.ensureVisible(find.text(label));
    await tester.pump();
    await tester.tap(find.text(label));
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(AlertDialog).evaluate().isNotEmpty ||
          find.byType(CircularProgressIndicator).evaluate().isEmpty)
        break;
    }
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets(
    'pasted timed lyrics preview, save and reopen offline with cover art',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = await launch(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('import-title')))
            .controller!
            .text,
        target.title,
      );
      await tester.enterText(find.byKey(const Key('import-text')), timed);
      await action(tester, 'Preview');
      expect(find.text('Timed lyrics · 2 lines'), findsOneWidget);
      expect(find.text('Hello world\nNext line'), findsOneWidget);
      expect(tester.takeException(), null);
      await action(tester, 'Save for this song');
      expect(find.text('Open import'), findsOneWidget);
      final saved = await container
          .read(lyricsRepositoryProvider)
          .getCachedLyrics('कलाकार_गीत');
      expect(saved?.source, 'Imported');
      expect(saved?.lrcLyrics, timed);
      expect(
        container.read(lyricsNotifierProvider).currentSong?.artworkUrl,
        target.artworkUrl,
      );
      expect((await container.read(cachedLyricsProvider.future)).length, 1);
    },
  );

  testWidgets(
    'file import fills empty metadata and cancellation preserves entered text',
    (tester) async {
      final file = SelectedFile(timed);
      final container = await launch(tester, blank: true, file: file);
      await action(tester, 'Choose lyrics file');
      await tester.scrollUntilVisible(
        find.byKey(const Key('import-title')),
        -160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('import-title')))
            .controller!
            .text,
        target.title,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('import-artist')))
            .controller!
            .text,
        target.artist,
      );
      file.text = null;
      await action(tester, 'Choose lyrics file');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('import-text')))
            .controller!
            .text,
        timed,
      );
      await action(tester, 'Save for this song');
      expect(
        (await container.read(cachedLyricsProvider.future)).single.source,
        'Imported',
      );
    },
  );

  testWidgets(
    'replacement requires confirmation and only replaces the chosen song',
    (tester) async {
      final container = await launch(tester);
      final repository = container.read(lyricsRepositoryProvider);
      final original = await LyricsImport.parse('Original words', target);
      await repository.cacheLyrics(original);
      await repository.cacheLyrics(
        await LyricsImport.parse(
          'Other words',
          target.copyWith(title: 'Other song'),
        ),
      );
      await tester.enterText(find.byKey(const Key('import-text')), timed);
      await action(tester, 'Save for this song');
      expect(find.text('Replace saved lyrics?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        (await repository.getCachedLyrics(original.songId))?.plainLyrics,
        'Original words',
      );
      await action(tester, 'Save for this song');
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      expect(
        (await repository.getCachedLyrics(original.songId))?.plainLyrics,
        'Hello world\nNext line',
      );
      expect((await repository.getAllCachedLyrics()).length, 2);
      expect(
        (await repository.getCachedLyrics('कलाकार_other_song'))?.plainLyrics,
        'Other words',
      );
    },
  );

  testWidgets(
    'invalid timing, unreadable files and failed saves keep the import open',
    (tester) async {
      final file = SelectedFile(null)..fail = true;
      final container = await launch(tester, file: file, fail: true);
      await action(tester, 'Choose lyrics file');
      expect(find.textContaining('Could not read the file'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('import-text')),
        '[00:99]Bad',
      );
      await action(tester, 'Save for this song');
      expect(find.textContaining('seconds must be'), findsOneWidget);
      expect(
        await container.read(lyricsRepositoryProvider).getAllCachedLyrics(),
        isEmpty,
      );
      await tester.enterText(find.byKey(const Key('import-text')), timed);
      await action(tester, 'Save for this song');
      expect(find.textContaining('Could not save lyrics'), findsOneWidget);
      expect(find.byType(ImportLyricsScreen), findsOneWidget);
    },
  );
}
