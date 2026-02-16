import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_theme.dart';
import '../providers/lyrics_provider.dart';
import '../providers/media_provider.dart';
import '../widgets/lyrics_display.dart';
import '../widgets/song_card.dart';
import '../widgets/permission_card.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(mediaNotifierProvider.notifier).checkPermissions();
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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lyricsState = ref.watch(lyricsNotifierProvider);
    final mediaState = ref.watch(mediaNotifierProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Keep screen on when showing lyrics
    if (lyricsState.lyrics != null && lyricsState.currentSong != null) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(mediaState, isDark),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? AppTheme.backgroundGradient
              : AppTheme.lightBackgroundGradient,
        ),
        child: SafeArea(child: _buildBody(lyricsState, mediaState)),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(MediaState mediaState, bool isDark) {
    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            shaderCallback: (bounds) =>
                AppTheme.primaryGradient.createShader(bounds),
            child: const Text(
              'FlashLyrics',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          if (mediaState.isListening) ...[
            const SizedBox(width: 10),
            _buildStatusIndicator(mediaState),
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
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatusIndicator(MediaState mediaState) {
    final isPlaying = mediaState.isPlaying;
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

  Widget _buildBody(LyricsState lyricsState, MediaState mediaState) {
    // If we have lyrics from search, show them regardless of permission status
    if (lyricsState.currentSong != null) {
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            SongCard(song: lyricsState.currentSong!),
            const SizedBox(height: 16),
            if (lyricsState.lyrics != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: LyricsDisplay(
                  lyrics: lyricsState.lyrics!,
                  currentPosition: mediaState.currentPosition,
                  isPlaying: mediaState.isPlaying,
                ),
              )
            else
              _buildNoLyricsState(),
            const SizedBox(height: 40),
          ],
        ),
      );
    }

    if (!mediaState.hasPermission) {
      return _buildPermissionRequest(mediaState);
    }

    if (lyricsState.isLoading) {
      return _buildLoadingState();
    }

    if (lyricsState.error != null) {
      return _buildErrorState(lyricsState.error!);
    }

    return _buildEmptyState(mediaState);
  }

  Widget _buildLoadingState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
                width: 80,
                height: 80,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.surfaceColor : AppTheme.lightSurface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.2),
                      blurRadius: 30,
                    ),
                  ],
                ),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation(
                    AppTheme.primaryColor.withValues(alpha: 0.8),
                  ),
                ),
              )
              .animate(onPlay: (c) => c.repeat())
              .shimmer(
                duration: 1500.ms,
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
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

  Widget _buildPermissionRequest(MediaState mediaState) {
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

  Widget _buildEmptyState(MediaState mediaState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated icon container
            Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryColor.withValues(alpha: 0.15),
                        AppTheme.primaryColor.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.2),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    mediaState.isListening
                        ? Icons.headphones_rounded
                        : Icons.music_note_rounded,
                    size: 56,
                    color: AppTheme.primaryLight,
                  ),
                )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(
                  begin: const Offset(1.0, 1.0),
                  end: const Offset(1.05, 1.05),
                  duration: 1500.ms,
                  curve: Curves.easeInOut,
                )
                .animate()
                .fadeIn(duration: 500.ms)
                .scale(begin: const Offset(0.8, 0.8)),
            const SizedBox(height: 32),
            Text(
              mediaState.isListening
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
              mediaState.isListening
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
        // Fun tip card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primaryColor.withValues(alpha: isDark ? 0.15 : 0.1),
                AppTheme.primaryColor.withValues(alpha: isDark ? 0.08 : 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        randomTip.$1,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .rotate(begin: -0.02, end: 0.02, duration: 2000.ms),
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
