import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/song.dart';

/// Displays current song information with glassmorphism effect
class SongCard extends StatelessWidget {
  final Song song;
  final VoidCallback? onTap;

  const SongCard({super.key, required this.song, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child:
          Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.surfaceColor.withValues(alpha: 0.8),
                            AppTheme.surfaceLight.withValues(alpha: 0.6),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.2),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withValues(
                              alpha: 0.15,
                            ),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            _buildAlbumArt(),
                            const SizedBox(width: 16),
                            Expanded(child: _buildSongInfo(context)),
                            _buildPlayingIndicator(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .animate()
              .fadeIn(duration: 400.ms)
              .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
    );
  }

  Widget _buildAlbumArt() {
    return Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: song.artworkUrl != null
                ? Image.network(
                    song.artworkUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildArtPlaceholder(),
                  )
                : _buildArtPlaceholder(),
          ),
        )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .shimmer(
          duration: 2.seconds,
          color: AppTheme.primaryColor.withValues(alpha: 0.1),
        );
  }

  Widget _buildArtPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor.withValues(alpha: 0.3),
            AppTheme.primaryDark.withValues(alpha: 0.5),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.music_note_rounded,
          color: AppTheme.textPrimary,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildSongInfo(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [AppTheme.textPrimary, AppTheme.primaryLight],
          ).createShader(bounds),
          child: Text(
            song.title,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          song.artist,
          style: textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        if (song.source != null) _buildSourceBadge(),
      ],
    );
  }

  Widget _buildSourceBadge() {
    final sourceColor = _getSourceColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            sourceColor.withValues(alpha: 0.25),
            sourceColor.withValues(alpha: 0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: sourceColor.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_getSourceIcon(), size: 12, color: sourceColor),
          const SizedBox(width: 4),
          Text(
            song.source!,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: sourceColor,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayingIndicator() {
    return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppTheme.primaryGradient,
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.equalizer_rounded, color: Colors.white, size: 18),
          ),
        )
        .animate(onPlay: (c) => c.repeat())
        .scale(
          begin: const Offset(1.0, 1.0),
          end: const Offset(1.1, 1.1),
          duration: 800.ms,
          curve: Curves.easeInOut,
        )
        .then()
        .scale(
          begin: const Offset(1.1, 1.1),
          end: const Offset(1.0, 1.0),
          duration: 800.ms,
          curve: Curves.easeInOut,
        );
  }

  Color _getSourceColor() {
    switch (song.source?.toLowerCase()) {
      case 'spotify':
        return const Color(0xFF1DB954);
      case 'youtube music':
        return const Color(0xFFFF0000);
      case 'apple music':
        return const Color(0xFFFC3C44);
      default:
        return AppTheme.secondaryColor;
    }
  }

  IconData _getSourceIcon() {
    switch (song.source?.toLowerCase()) {
      case 'spotify':
        return Icons.podcasts_rounded;
      case 'youtube music':
        return Icons.play_circle_outline_rounded;
      case 'apple music':
        return Icons.apple_rounded;
      default:
        return Icons.music_note_rounded;
    }
  }
}
