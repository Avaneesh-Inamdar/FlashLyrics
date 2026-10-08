import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyricx/data/datasources/lyrics_remote_datasource.dart';
import 'package:lyricx/data/models/lyrics_model.dart';
import 'package:lyricx/domain/entities/song.dart';
import 'package:lyricx/presentation/providers/providers.dart';
import 'package:lyricx/services/media_detection_service.dart';
import 'lyrics_regression_test.dart' show model;

class RecoveryRemote extends LyricsRemoteDataSource {
  RecoveryRemote() : super(Dio());
  int calls = 0;
  int failures = 1;
  @override
  Future<LyricsModel?> fetchAllParallel(String artist, String title,
      {List<String>? providerPriority}) async {
    calls++;
    if (calls <= failures) throw Exception('Temporary network failure');
    return model(title);
  }
}

class PlaybackService extends MediaDetectionService {
  final songs = StreamController<Song>.broadcast();
  final playback = StreamController<bool>.broadcast();
  final positions = StreamController<PlaybackPosition>.broadcast();
  @override
  Stream<Song> get songStream => songs.stream;
  @override
  Stream<bool> get playbackStream => playback.stream;
  @override
  Stream<PlaybackPosition> get positionStream => positions.stream;
  @override
  void startListening() {}
  @override
  void stopListening() {}
  @override
  Future<Song?> getCurrentPlayingSong() async => null;
  @override
  void dispose() {
    songs.close();
    playback.close();
    positions.close();
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.lyricx/media'),
            (_) async => false);
  });

  for (final scenario in ['resume', 'bounded', 'manual', 'new song', 'dispose']) {
    testWidgets('failed lyrics recovery: $scenario', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final remote = RecoveryRemote();
      final service = PlaybackService();
      final container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        lyricsRemoteDataSourceProvider.overrideWithValue(remote),
        mediaDetectionServiceProvider.overrideWithValue(service),
      ]);
      final media = container.read(mediaNotifierProvider.notifier);
      await tester.pump();
      await media.startListening();
      service.songs.add(const Song(id: 'song', artist: 'Artist', title: 'Song'));
      await tester.pump();
      expect(remote.calls, 1);
      expect(container.read(lyricsNotifierProvider).error, isNotNull);

      if (scenario == 'resume') {
        service.playback.add(false); // Ad/buffering interruption.
        await tester.pump();
        await tester.pump(const Duration(seconds: 10));
        expect(remote.calls, 1);
        // Polling can resume playback without another metadata callback.
        service.positions.add(const PlaybackPosition(position: Duration(seconds: 5),
            duration: Duration(minutes: 3), isPlaying: true));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(remote.calls, 2);
        expect(container.read(lyricsNotifierProvider).lyrics, isNotNull);
      } else if (scenario == 'bounded') {
        remote.failures = 99;
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 5));
        service.songs.add(const Song(id: 'song', artist: 'Artist', title: 'Song'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 30));
        expect(remote.calls, 3);
      } else if (scenario == 'manual') {
        container.read(lyricsNotifierProvider.notifier).setLyricsFromModel(model('Chosen'));
        await tester.pump(const Duration(seconds: 10));
        expect(remote.calls, 1);
        expect(container.read(lyricsNotifierProvider).currentSong!.title, 'Chosen');
      } else if (scenario == 'new song') {
        service.songs.add(const Song(id: 'next', artist: 'Artist', title: 'Next'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 10));
        expect(remote.calls, 2);
        expect(container.read(lyricsNotifierProvider).currentSong!.title, 'Next');
      }
      container.dispose();
      service.dispose();
      await tester.pump(const Duration(seconds: 10));
      expect(tester.takeException(), isNull);
    });
  }
}
