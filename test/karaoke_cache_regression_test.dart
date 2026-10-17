import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyricx/data/models/lyrics_model.dart';
import 'package:lyricx/data/datasources/lyrics_local_datasource.dart';
import 'package:lyricx/data/datasources/lyrics_remote_datasource.dart';
import 'package:lyricx/data/repositories/lyrics_repository_impl.dart';
import 'package:lyricx/domain/entities/song.dart';
import 'package:lyricx/presentation/providers/providers.dart';
import 'package:lyricx/presentation/widgets/lyrics_display.dart';
import 'package:lyricx/presentation/widgets/synced_lyrics_display.dart';
import 'package:lyricx/presentation/widgets/karaoke_line.dart';

LyricsModel song(String id) => LyricsModel(
  id: id,
  songId: id,
  trackName: id,
  artistName: 'Artist',
  plainLyrics: 'Stay with me\nNext line',
  lrcLyrics: '[00:01]Stay with me\n[00:04]Next line',
  isSynced: true,
  source: 'Test',
  fetchedAt: DateTime(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('synced-only provider results are saved and readable offline', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final local = LyricsLocalDataSource(prefs);
    final remote = SyncedOnlyRemote();
    final repository = LyricsRepositoryImpl(
      remoteDataSource: remote,
      localDataSource: local,
    );
    final selected = await repository.getLyrics(
      const Song(id: 'only', artist: 'Artist', title: 'only'),
    );
    expect(selected.lrcLyrics, isNotEmpty);
    expect(
      LyricsLocalDataSource(prefs).getCachedLyrics('only')!.lrcLyrics,
      selected.lrcLyrics,
    );
    await repository.searchLyrics('Artist', 'only');
    expect(remote.calls, 1);
  });
  testWidgets(
    'karaoke choice survives song replacement, restart, and disabling',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      Future<void> show(String id) async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: LyricsDisplay(
                    key: ValueKey(id),
                    lyrics: song(id),
                    currentPosition: const Duration(milliseconds: 1500),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 70)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }

      await show('first');
      await tester.tap(find.text('Karaoke'));
      await tester.pump();
      expect(find.text('Karaoke · estimated timing'), findsOneWidget);
      await show('second');
      expect(
        tester
            .widget<SyncedLyricsDisplay>(find.byType(SyncedLyricsDisplay))
            .estimateWordTiming,
        true,
      );
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      await show('restarted');
      expect(find.text('Karaoke · estimated timing'), findsOneWidget);
      await container
          .read(songOffsetProvider.notifier)
          .setSongOffset(
            generateSongKey(artist: 'Artist', title: 'restarted'),
            600,
          );
      await tester.pump();
      expect(
        tester
            .widget<SyncedLyricsDisplay>(find.byType(SyncedLyricsDisplay))
            .syncOffsetMs,
        600,
      );
      expect(
        tester.widget<KaraokeLine>(find.byType(KaraokeLine)).offset,
        const Duration(milliseconds: 600),
      );
      await tester.tap(find.text('Karaoke'));
      await tester.pump();
      await show('third');
      expect(find.text('Line by line'), findsOneWidget);
      expect(
        tester
            .widget<SyncedLyricsDisplay>(find.byType(SyncedLyricsDisplay))
            .estimateWordTiming,
        false,
      );
      expect(SettingsNotifier(prefs).state.karaokeEnabled, false);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );

  test(
    'damaged entries are isolated; concurrent saves and deletion survive restart',
    () async {
      SharedPreferences.setMockInitialValues({
        'lyrics_cache': jsonEncode({
          'good': song('good').toJson(),
          'damaged': {'fetchedAt': 'invalid'},
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      var changes = 0;
      final local = LyricsLocalDataSource(prefs, onChanged: () => changes++);
      expect(local.getCachedLyrics('damaged'), isNull);
      expect(local.getCachedLyrics('good'), isNotNull);
      expect(local.getAllCachedLyrics().length, 1);
      await Future.wait(
        List.generate(20, (i) => local.cacheLyrics(song('song$i'))),
      );
      await Future.wait([
        local.deleteCachedLyrics('good'),
        local.cacheLyrics(song('final')),
      ]);
      final restarted = LyricsLocalDataSource(prefs);
      expect(restarted.getAllCachedLyrics().length, 21);
      expect(restarted.getCachedLyrics('song0'), isNotNull);
      expect(restarted.getCachedLyrics('final')!.trackName, 'final');
      expect(changes, 22);
    },
  );

  test(
    'manual selection is saved and an already-open Library refreshes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      expect(await container.read(cachedLyricsProvider.future), isEmpty);
      container
          .read(lyricsNotifierProvider.notifier)
          .setLyricsFromModel(song('selected'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        (await container.read(cachedLyricsProvider.future)).single.songId,
        'selected',
      );
      expect(
        container
            .read(lyricsLocalDataSourceProvider)
            .getCachedLyrics('selected')!
            .artistName,
        'Artist',
      );
      container.dispose();
    },
  );

  test('Hindi and Japanese offset keys stay distinct and persist', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final a = generateSongKey(artist: 'कलाकार', title: 'गीत');
    final b = generateSongKey(artist: 'कलाकार', title: 'दूसरा गीत');
    final c = generateSongKey(artist: '歌手', title: '歌');
    expect({a, b, c}.length, 3);
    expect(a, isNotEmpty);
    final offsets = SongOffsetNotifier(prefs);
    await offsets.setSongOffset(a, -500);
    await offsets.setSongOffset(b, 700);
    final restarted = SongOffsetNotifier(prefs);
    expect(restarted.getCustomOffset(a), -500);
    expect(restarted.getCustomOffset(b), 700);
    expect(restarted.getCustomOffset(c), isNull);
    offsets.dispose();
    restarted.dispose();
  });

  for (final estimated in [true, false]) {
    for (final playing in [false, true]) {
      testWidgets(
        'offset immediately updates words and lines, estimated=$estimated, playing=$playing',
        (tester) async {
          Future<void> show(int offset) async {
            await tester.pumpWidget(
              MaterialApp(
                home: SyncedLyricsDisplay(
                  lrcContent: estimated
                      ? '[offset:200]\n[00:01]Stay with me\n[00:04]Next line\n[00:07]End'
                      : '[offset:200]\n[00:01]<00:01>Stay <00:02>with <00:03>me<00:04>\n[00:04]<00:04>Next <00:05>line<00:07>',
                  currentPosition: const Duration(milliseconds: 3500),
                  isPlaying: playing,
                  estimateWordTiming: estimated,
                  syncOffsetMs: offset,
                ),
              ),
            );
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 70)),
            );
            await tester.pump();
          }

          await show(0);
          expect(
            tester.widget<KaraokeLine>(find.byType(KaraokeLine)).line.text,
            'Stay with me',
          );
          await show(1000);
          final later = tester.widget<KaraokeLine>(find.byType(KaraokeLine));
          expect(later.line.text, 'Next line');
          expect(later.offset, const Duration(milliseconds: 800));
          await show(-1000);
          final earlier = tester.widget<KaraokeLine>(find.byType(KaraokeLine));
          expect(earlier.line.text, 'Stay with me');
          expect(earlier.offset, const Duration(milliseconds: -1200));
          expect(
            wordProgress(
              earlier.line.words[1],
              earlier.position.value + earlier.offset,
            ),
            inExclusiveRange(0, 1),
          );
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}

class SyncedOnlyRemote extends LyricsRemoteDataSource {
  SyncedOnlyRemote() : super(Dio());
  int calls = 0;
  @override
  Future<LyricsModel?> fetchAllParallel(
    String artist,
    String title, {
    List<String>? providerPriority,
  }) async {
    calls++;
    return LyricsModel.fromJson({...song('only').toJson(), 'plainLyrics': ''});
  }
}
