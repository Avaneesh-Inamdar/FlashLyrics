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

/// Dio client provider with SSL error handling
final dioClientProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent': 'FlashLyrics/1.0.0',
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'en-US,en;q=0.9,hi;q=0.8',
        'Accept-Encoding': 'gzip, deflate',
      },
    ),
  );

  // Add interceptor for better error handling
  dio.interceptors.add(
    InterceptorsWrapper(
      onError: (error, handler) {
        // Handle certificate errors gracefully
        if (error.type == DioExceptionType.badCertificate ||
            error.message?.contains('certificate') == true ||
            error.message?.contains('CERTIFICATE_VERIFY_FAILED') == true) {
          // Return a network exception with clear message
          handler.reject(
            DioException(
              requestOptions: error.requestOptions,
              type: DioExceptionType.connectionError,
              message:
                  'Server certificate expired or invalid. Try a different lyrics provider.',
              error: error.error,
            ),
          );
          return;
        }
        handler.next(error);
      },
    ),
  );

  return dio;
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

/// Tab index state notifier for controlling bottom navigation
class TabIndexNotifier extends StateNotifier<int> {
  TabIndexNotifier() : super(0);

  void setIndex(int index) {
    state = index;
  }

  void goToHome() {
    state = 0;
  }

  void goToSearch() {
    state = 1;
  }
}

/// Tab index provider for bottom navigation
final tabIndexProvider = StateNotifierProvider<TabIndexNotifier, int>((ref) {
  return TabIndexNotifier();
});
