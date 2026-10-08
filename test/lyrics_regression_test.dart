import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyricx/core/utils/song_key.dart';
import 'package:lyricx/data/datasources/lyrics_local_datasource.dart';
import 'package:lyricx/data/datasources/lyrics_remote_datasource.dart';
import 'package:lyricx/data/models/lyrics_model.dart';
import 'package:lyricx/data/repositories/lyrics_repository_impl.dart';
import 'package:lyricx/domain/entities/song.dart';
import 'package:lyricx/presentation/providers/providers.dart';
import 'package:lyricx/presentation/screens/search_screen.dart';

LyricsModel model(String title, {String? key}) => LyricsModel(
  id: title,
  songId: key ?? songKey('Artist', title),
  plainLyrics: 'Test words',
  isSynced: false,
  source: 'Test',
  fetchedAt: DateTime(2026),
  artistName: 'Artist',
  trackName: title,
);

class ControlledRemote extends LyricsRemoteDataSource {
  ControlledRemote() : super(Dio());
  final search = Completer<List<LyricsModel>>();
  int fetches = 0;
  Completer<LyricsModel?>? nextFetch;

  @override
  Future<List<LyricsModel>> searchByQuery(
    String query, {
    List<String>? providerPriority,
  }) => search.future;

  @override
  Future<LyricsModel?> fetchAllParallel(
    String artist,
    String title, {
    List<String>? providerPriority,
  }) async {
    fetches++;
    return nextFetch == null ? model(title) : await nextFetch!.future;
  }
}

void main() {
  test('overlapping startup detection coalesces the same song lookup', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final remote = ControlledRemote()..nextFetch = Completer<LyricsModel?>();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      lyricsRemoteDataSourceProvider.overrideWithValue(remote),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(lyricsNotifierProvider.notifier);
    const song = Song(id: 'playing', artist: 'Artist', title: 'Song');
    final first = notifier.setSong(song);
    await notifier.setSong(song);
    await Future<void>.delayed(Duration.zero);
    expect(remote.fetches, 1);
    remote.nextFetch!.complete(model('Song'));
    await first;
    expect(container.read(lyricsNotifierProvider).lyrics, isNotNull);
  });

  test(
    'manual selection survives an earlier playback lookup completing',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final remote = ControlledRemote()..nextFetch = Completer<LyricsModel?>();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          lyricsRemoteDataSourceProvider.overrideWithValue(remote),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(lyricsNotifierProvider.notifier);
      final pending = notifier.setSong(
        const Song(id: 'old', artist: 'Artist', title: 'Old song'),
      );
      await Future<void>.delayed(Duration.zero);
      notifier.setLyricsFromModel(model('Selected song'));
      remote.nextFetch!.complete(model('Old song'));
      await pending;
      expect(
        container.read(lyricsNotifierProvider).currentSong!.title,
        'Selected song',
      );
    },
  );

  test(
    'refresh bypasses cache; legacy Unicode entries stay accessible',
    () async {
      SharedPreferences.setMockInitialValues({});
      final local = LyricsLocalDataSource(
        await SharedPreferences.getInstance(),
      );
      final remote = ControlledRemote();
      final repository = LyricsRepositoryImpl(
        remoteDataSource: remote,
        localDataSource: local,
      );
      await local.cacheLyrics(model('दिन', key: 'legacy_key'));
      const song = Song(id: 'playing', title: 'दिन', artist: 'Artist');
      expect((await repository.getLyrics(song)).id, 'दिन');
      expect(remote.fetches, 0);
      await repository.getLyrics(song, forceRefresh: true);
      expect(remote.fetches, 1);
      expect(local.getCachedLyrics(songKey('Artist', 'दिन')), isNotNull);
    },
  );

  testWidgets('clearing search prevents late results from reappearing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final remote = ControlledRemote();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          lyricsRemoteDataSourceProvider.overrideWithValue(remote),
        ],
        child: const MaterialApp(home: SearchScreen()),
      ),
    );
    await tester.enterText(find.byType(TextField), 'late song');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField), '');
    remote.search.complete([model('Late result')]);
    await tester.pumpAndSettle();
    expect(find.text('Late result'), findsNothing);
    expect(prefs.getStringList('search_history_v2') ?? [], isEmpty);
    expect(tester.takeException(), isNull);
  });
}
