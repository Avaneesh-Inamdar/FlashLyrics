import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyricx/data/datasources/genius_lyrics_datasource.dart';
import 'package:lyricx/data/models/lyrics_model.dart';
import 'package:lyricx/presentation/providers/providers.dart';
import 'package:lyricx/presentation/screens/genius_lyrics_screen.dart';
import 'genius_lyrics_test.dart' show fixture;

class ControlledGenius extends GeniusLyricsDataSource {
  ControlledGenius() : super(Dio());
  final pendingSearch = Completer<List<GeniusSong>>();
  @override
  Future<List<GeniusSong>> search(String query, {CancelToken? cancelToken}) =>
      pendingSearch.future;
  @override
  Future<LyricsModel> fetch(
    GeniusSong song, {
    CancelToken? cancelToken,
  }) async => GeniusLyricsDataSource.parsePage(fixture, song);
}

void main() {
  final song = GeniusSong(
    title: 'Test track',
    artist: 'Test artist',
    url: Uri.parse('https://genius.com/Test-artist-test-track-lyrics'),
  );

  Future<ControlledGenius> mount(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final source = ControlledGenius();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          geniusLyricsDataSourceProvider.overrideWithValue(source),
        ],
        child: const MaterialApp(home: GeniusLyricsScreen()),
      ),
    );
    return source;
  }

  testWidgets('Genius search, selection, preview, and offline save', (
    tester,
  ) async {
    final source = await mount(tester);
    await tester.enterText(find.byType(TextField), 'Test artist Test track');
    await tester.tap(find.byWidgetPredicate((widget) => widget is FilledButton));
    source.pendingSearch.complete([song]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test track'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Original & test words'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Save offline & read'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Save offline & read'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GeniusLyricsScreen)),
    );
    expect(
      container.read(lyricsNotifierProvider).currentSong!.title,
      'Test track',
    );
    final saved = container
        .read(lyricsLocalDataSourceProvider)
        .getAllCachedLyrics();
    expect(saved, hasLength(1));
    expect(saved.single.sourceUrl, song.url.toString());
    expect(tester.takeException(), isNull);
  });

  testWidgets('edited query discards even a late uncancellable search result', (
    tester,
  ) async {
    final source = await mount(tester);
    await tester.enterText(find.byType(TextField), 'Old query');
    await tester.tap(find.byWidgetPredicate((widget) => widget is FilledButton));
    await tester.enterText(find.byType(TextField), 'New query');
    source.pendingSearch.complete([song]);
    await tester.pumpAndSettle();
    expect(find.text('Test track'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
