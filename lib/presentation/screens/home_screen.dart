import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../services/media_detection_service.dart';
import '../providers/lyrics_provider.dart';
import '../providers/media_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/lyrics_display.dart';
import '../widgets/song_card.dart';
import '../widgets/song_controls.dart';
import '../widgets/permission_card.dart';
import '../widgets/floating_overlay_button.dart';
import 'search_screen.dart';

/// Home screen showing current song and lyrics
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.read(mediaNotifierProvider.notifier).checkPermissions();
      // Request post-notification permission for music detection toasts (Android 13+)
      try {
        final hasPost = await MediaDetectionService.checkPostNotificationPermission();
        if (!hasPost) await MediaDetectionService.requestPostNotificationPermission();
      } catch (_) {}
      // Initialize by fetching current song if available
      _initializeCurrentSong();
    });
  }

  // Initialize by fetching the currently playing song
  Future<void> _initializeCurrentSong() async {
    try {
      final song = await ref
          .read(mediaNotifierProvider.notifier)
          .getCurrentSong();
      if (song != null) {
        await ref.read(lyricsNotifierProvider.notifier).setSong(song);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  dispose() {
    // Disable keep screen on when leaving
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lyricsState = ref.watch(lyricsNotifierProvider);
    final hasPermission = ref.watch(mediaNotifierProvider.select((s) => s.hasPermission));
    final isListening = ref.watch(mediaNotifierProvider.select((s) => s.isListening));
    final isPlaying = ref.watch(mediaNotifierProvider.select((s) => s.isPlaying));
    final hasMediaSong = ref.watch(mediaNotifierProvider.select((s) => s.currentDuration.inMilliseconds > 0 || s.currentSong != null));
    final settings = ref.watch(settingsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Cache latest lyrics for native notification -> floating window (battery-efficient)
    // Note: Overlay auto-update (title/lrc swap when song changes) is now handled centrally
    // inside OverlayNotifier's lyrics listener. This cache is kept as redundant safety for
    // the native notification's "Float" action and the service's cache-polling fallback.
    ref.listen<LyricsState>(lyricsNotifierProvider, (prev, next) {
      if (next.lyrics != null && next.currentSong != null) {
        final lrc = next.lyrics!.lrcLyrics ?? '';
        final plain = next.lyrics!.plainLyrics;
        // Use fresh settings to avoid stale capture
        final s = ref.read(settingsProvider);
        MediaDetectionService.cacheOverlayLyricsStatic(
          title: next.currentSong!.title,
          artist: next.currentSong!.artist,
          lrcLyrics: lrc,
          plainLyrics: plain,
          syncOffsetMs: s.lyricsSyncOffset,
          enableSeek: s.floatingOverlaySeekEnabled,
        );
      }
    });
    // Also re-cache when sync offset or seek toggle changes
    ref.listen<AppSettings>(settingsProvider, (prev, next) {
      final offsetChanged = prev?.lyricsSyncOffset != next.lyricsSyncOffset;
      final seekChanged = prev?.floatingOverlaySeekEnabled != next.floatingOverlaySeekEnabled;
      if (offsetChanged || seekChanged) {
        final cur = ref.read(lyricsNotifierProvider);
        if (cur.lyrics != null && cur.currentSong != null) {
          final lrc = cur.lyrics!.lrcLyrics ?? '';
          final plain = cur.lyrics!.plainLyrics;
          MediaDetectionService.cacheOverlayLyricsStatic(
            title: cur.currentSong!.title,
            artist: cur.currentSong!.artist,
            lrcLyrics: lrc,
            plainLyrics: plain,
            syncOffsetMs: next.lyricsSyncOffset,
            enableSeek: next.floatingOverlaySeekEnabled,
          );
        } else if (seekChanged) {
          // No song yet — still persist seek flag for future overlay (cache with empty lyrics keeps flag)
          // We keep last cached title if any; otherwise do a lightweight seek flag persist via empty update
          // Use try to avoid crash if cache empty
          try {
            final cur2 = ref.read(lyricsNotifierProvider);
            if (cur2.currentSong != null) {
              MediaDetectionService.cacheOverlayLyricsStatic(
                title: cur2.currentSong!.title,
                artist: cur2.currentSong!.artist,
                lrcLyrics: cur2.lyrics?.lrcLyrics ?? '',
                plainLyrics: cur2.lyrics?.plainLyrics ?? '',
                syncOffsetMs: next.lyricsSyncOffset,
                enableSeek: next.floatingOverlaySeekEnabled,
              );
            }
          } catch (_) {}
        }
      }
    });

    // Keep screen on when showing lyrics and setting is enabled
    if (settings.keepScreenOn &&
        lyricsState.lyrics != null &&
        lyricsState.currentSong != null) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
    return Scaffold(
      extendBodyBehindAppBar: false,
      appBar: _buildAppBar(isListening, isPlaying, isDark),
      backgroundColor: isDark ? AppTheme.backgroundColor : AppTheme.lightBackground,
      body: SafeArea(child: _buildBody(lyricsState, hasPermission, hasMediaSong)),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isListening, bool isPlaying, bool isDark) {
    return AppBar(
      backgroundColor: isDark ? AppTheme.backgroundColor : AppTheme.lightBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'FlashLyrics',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : AppTheme.lightTextPrimary,
              fontSize: 20,
            ),
          ),
          if (isListening) ...[
            const SizedBox(width: 10),
            _buildStatusIndicator(isPlaying),
          ],
        ],
      ),
      actions: [
        // Refresh button
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () async {
              // Fetch current song and lyrics
              try {
                await ref
                    .read(mediaNotifierProvider.notifier)
                    .refreshCurrentSong();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Refreshing...'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to refresh: $e'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatusIndicator(bool isPlaying) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (isPlaying ? AppTheme.successColor : Colors.orange).withValues(
          alpha: 0.15,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (isPlaying ? AppTheme.successColor : Colors.orange).withValues(
            alpha: 0.3,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isPlaying ? AppTheme.successColor : Colors.orange,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isPlaying ? AppTheme.successColor : Colors.orange)
                          .withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              )
              .animate(onPlay: (c) => c.repeat())
              .scale(
                begin: const Offset(1.0, 1.0),
                end: const Offset(1.3, 1.3),
                duration: 800.ms,
              )
              .then()
              .scale(
                begin: const Offset(1.3, 1.3),
                end: const Offset(1.0, 1.0),
                duration: 800.ms,
              ),
          const SizedBox(width: 6),
          Text(
            isPlaying ? 'Live' : 'Idle',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isPlaying ? AppTheme.successColor : Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(LyricsState lyricsState, bool hasPermission, bool hasMediaSong) {
    // If we have lyrics from search, show them regardless of permission status
    if (lyricsState.currentSong != null) {
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            SongCard(song: lyricsState.currentSong!),
            const SizedBox(height: 8),
            // Song controls with seek bar + next/prev
            if (hasMediaSong)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Consumer(
                  builder: (context, ref, _) {
                    final currentPos = ref.watch(mediaNotifierProvider.select((s) => s.currentPosition));
                    final totalDur = ref.watch(mediaNotifierProvider.select((s) => s.currentDuration));
                    final playing = ref.watch(mediaNotifierProvider.select((s) => s.isPlaying));
                    return SongControls(
                      currentPosition: currentPos,
                      totalDuration: totalDur.inMilliseconds > 0
                          ? totalDur
                          : (lyricsState.currentSong?.duration ?? Duration.zero),
                      isPlaying: playing,
                      onSeek: (position) {
                        ref.read(mediaNotifierProvider.notifier).seekTo(position);
                      },
                      onPlayPause: () {
                        ref
                            .read(mediaNotifierProvider.notifier)
                            .setPlaying(!playing);
                      },
                      onNext: () {
                        ref.read(mediaNotifierProvider.notifier).skipToNext();
                      },
                      onPrevious: () {
                        ref.read(mediaNotifierProvider.notifier).skipToPrevious();
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 6),
            // Floating overlay button (when song available)
            if (lyricsState.currentSong != null && lyricsState.lyrics != null)
              const FloatingLyricsButton(),
            const SizedBox(height: 4),
            if (lyricsState.isLoading && lyricsState.lyrics == null)
              _buildLoadingState()
            else if (lyricsState.error != null && lyricsState.lyrics == null)
              _buildErrorState(lyricsState.error!)
            else if (lyricsState.lyrics != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Consumer(
                  builder: (context, ref, _) {
                    final currentPos = ref.watch(mediaNotifierProvider.select((s) => s.currentPosition));
                    final playing = ref.watch(mediaNotifierProvider.select((s) => s.isPlaying));
                    return LyricsDisplay(
                      lyrics: lyricsState.lyrics!,
                      currentPosition: currentPos,
                      isPlaying: playing,
                      onSeek: (position) {
                        ref.read(mediaNotifierProvider.notifier).seekTo(position);
                      },
                    );
                  },
                ),
              )
            else
              _buildNoLyricsState(),
            const SizedBox(height: 40),
          ],
        ),
      );
    }

    if (!hasPermission) {
      return _buildPermissionRequest();
    }

    if (lyricsState.isLoading) {
      return _buildLoadingState();
    }

    if (lyricsState.error != null) {
      return _buildErrorState(lyricsState.error!);
    }

    return Consumer(
      builder: (context, ref, _) {
        final isListening = ref.watch(mediaNotifierProvider.select((s) => s.isListening));
        return _buildEmptyState(isListening: isListening);
      },
    );
  }

  Widget _buildLoadingState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final indicatorColor = isDark
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation(indicatorColor),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Fetching lyrics...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppTheme.textSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildPermissionRequest() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: PermissionCard(
          onRequestPermission: () {
            ref.read(mediaNotifierProvider.notifier).requestPermission();
          },
          onCheckAgain: () {
            ref.read(mediaNotifierProvider.notifier).checkPermissions();
          },
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildEmptyState({required bool isListening}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Static icon container - no repeating animation for performance
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              child: Icon(
                isListening
                    ? Icons.headphones_rounded
                    : Icons.music_note_rounded,
                size: 48,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              isListening
                  ? 'Listening for music...'
                  : 'No song playing',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppTheme.textPrimary
                    : AppTheme.lightTextPrimary,
                letterSpacing: -0.5,
              ),
            ).animate().fadeIn(delay: 100.ms),
            const SizedBox(height: 12),
            Text(
              isListening
                  ? 'Play a song on Spotify, YouTube Music,\nor any music app'
                  : 'Enable music detection to get started',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: isDark
                    ? AppTheme.textSecondary
                    : AppTheme.lightTextSecondary,
                height: 1.5,
              ),
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 40),
            // Fun tips section
            _buildFunTipsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildFunTipsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tips = [
      ('🎵', 'Did you know?', 'The average song is 3.5 minutes long'),
      ('🎧', 'Fun fact', 'Music can boost your workout by 15%'),
      ('🎤', 'Pro tip', 'Singing releases endorphins'),
      ('🎹', 'Music trivia', 'The longest song ever is 13 hours!'),
      ('🎸', 'Rock on!', 'Listening to music releases dopamine'),
      ('🎻', 'Classical vibes', 'Mozart wrote his first symphony at age 8'),
      ('🎷', 'Jazz it up', 'Jazz originated in New Orleans around 1900'),
      ('🥁', 'Beat drop', 'The fastest drummer played 20+ notes per second'),
      ('🧠', 'Brain boost', 'Music can improve memory and focus'),
      ('🌍', 'Global groove', 'There are over 1,200 music genres worldwide'),
      ('🎼', 'Composer tip', 'A melody usually sticks within 8 notes'),
      ('📻', 'Radio fact', 'The first FM station launched in 1933'),
      ('💿', 'Throwback', 'The first CD pressed was ABBA in 1982'),
      ('🎺', 'Brass facts', 'Trumpets were used in ancient Egypt'),
      ('🪩', 'Dance note', 'Dancing to music burns more calories than jogging'),
      ('🎧', 'Headphones', 'Stereo sound was popularized in the 1960s'),
      ('🎙️', 'Studio life', 'Most songs are mixed with 20+ audio tracks'),
      ('🌙', 'Night vibes', 'Slow tempo music can lower heart rate'),
    ];

    final randomTip = tips[(DateTime.now().millisecond % tips.length)];

    return Column(
      children: [
        // Feature cards row
        Row(
          children: [
            Expanded(
              child: _buildFeatureCard(
                icon: Icons.auto_awesome_rounded,
                title: 'Auto Sync',
                subtitle: 'Real-time lyrics',
                gradient: [AppTheme.primaryColor, AppTheme.primaryLight],
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFeatureCard(
                icon: Icons.offline_bolt_rounded,
                title: 'Offline',
                subtitle: 'Save favorites',
                gradient: [Colors.orange, Colors.amber],
                isDark: isDark,
              ),
            ),
          ],
        ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.1, end: 0),
        const SizedBox(height: 16),
        // Fun tip card - solid, no blur
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceColor : AppTheme.lightSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    randomTip.$1,
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      randomTip.$2,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryLight,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      randomTip.$3,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? AppTheme.textSecondary
                            : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ).animate().fadeIn(delay: 350.ms).slideY(begin: 0.1, end: 0),
      ],
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradient,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.surfaceColor.withValues(alpha: 0.5)
            : AppTheme.lightSurface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: gradient[0].withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppTheme.textPrimary
                        : AppTheme.lightTextPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppTheme.textHint : AppTheme.lightTextHint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoLyricsState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color:
                    (isDark
                            ? AppTheme.surfaceLight
                            : AppTheme.lightSurfaceLight)
                        .withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lyrics_outlined,
                size: 40,
                color: isDark ? AppTheme.textHint : AppTheme.lightTextHint,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No lyrics found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppTheme.textSecondary
                    : AppTheme.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'We couldn\'t find lyrics for this song',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? AppTheme.textHint : AppTheme.lightTextHint,
              ),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () => _showSearchDialog(context),
              icon: const Icon(Icons.search_rounded),
              label: const Text('Search manually'),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildErrorState(String error) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: AppTheme.errorColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppTheme.textPrimary
                    : AppTheme.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? AppTheme.textSecondary
                    : AppTheme.lightTextSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    ref.read(lyricsNotifierProvider.notifier).clear();
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.refresh_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Try Again',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).shake(duration: 500.ms, hz: 3);
  }

  void _showSearchDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SearchScreen()),
    );
  }
}
