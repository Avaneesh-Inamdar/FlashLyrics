import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/datasources/lyrics_remote_datasource.dart';
import '../../data/datasources/lyrics_local_datasource.dart';
import '../../data/repositories/lyrics_repository_impl.dart';
import '../../domain/repositories/lyrics_repository.dart';
import '../../domain/usecases/lyrics_usecases.dart';

// Export providers for easy imports
export 'lyrics_provider.dart';
export 'media_provider.dart';
export 'settings_provider.dart';

/// SharedPreferences provider
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be initialized before use');
});

/// Dio client provider
final dioClientProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );
});

/// Lyrics remote data source provider
final lyricsRemoteDataSourceProvider = Provider<LyricsRemoteDataSource>((ref) {
  final dio = ref.watch(dioClientProvider);
  return LyricsRemoteDataSource(dio);
});

/// Lyrics local data source provider
final lyricsLocalDataSourceProvider = Provider<LyricsLocalDataSource>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return LyricsLocalDataSource(prefs);
});

/// Lyrics repository provider
final lyricsRepositoryProvider = Provider<LyricsRepository>((ref) {
  final remoteDataSource = ref.watch(lyricsRemoteDataSourceProvider);
  final localDataSource = ref.watch(lyricsLocalDataSourceProvider);
  return LyricsRepositoryImpl(
    remoteDataSource: remoteDataSource,
    localDataSource: localDataSource,
  );
});

/// Get lyrics use case provider
final getLyricsUseCaseProvider = Provider<GetLyricsUseCase>((ref) {
  final repository = ref.watch(lyricsRepositoryProvider);
  return GetLyricsUseCase(repository);
});

/// Search lyrics use case provider
final searchLyricsUseCaseProvider = Provider<SearchLyricsUseCase>((ref) {
  final repository = ref.watch(lyricsRepositoryProvider);
  return SearchLyricsUseCase(repository);
});

/// Get cached lyrics use case provider
final getCachedLyricsUseCaseProvider = Provider<GetCachedLyricsUseCase>((ref) {
  final repository = ref.watch(lyricsRepositoryProvider);
  return GetCachedLyricsUseCase(repository);
});

/// Get all cached lyrics use case provider
final getAllCachedLyricsUseCaseProvider = Provider<GetAllCachedLyricsUseCase>((
  ref,
) {
  final repository = ref.watch(lyricsRepositoryProvider);
  return GetAllCachedLyricsUseCase(repository);
});

/// Search cached lyrics use case provider
final searchCachedLyricsUseCaseProvider = Provider<SearchCachedLyricsUseCase>((
  ref,
) {
  final repository = ref.watch(lyricsRepositoryProvider);
  return SearchCachedLyricsUseCase(repository);
});
