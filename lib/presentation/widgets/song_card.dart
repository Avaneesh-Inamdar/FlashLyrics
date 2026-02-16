import 'dart:io';
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/song.dart';

/// Displays current song information with glassmorphism effect
class SongCard extends StatefulWidget {
  final Song song;
  final VoidCallback? onTap;

  const SongCard({super.key, required this.song, this.onTap});

  @override
  State<SongCard> createState() => _SongCardState();
}

class _SongCardState extends State<SongCard> {
  String? _resolvedArtworkUrl;

  @override
  void initState() {
    super.initState();
    _resolveArtwork();
  }

  @override
  void didUpdateWidget(covariant SongCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id ||
        oldWidget.song.artworkUrl != widget.song.artworkUrl) {
      _resolveArtwork();
    }
  }

  Future<void> _resolveArtwork() async {
    final normalized = _normalizeArtworkUrl(widget.song.artworkUrl);
    if (normalized != null) {
      if (!mounted) return;
      setState(() => _resolvedArtworkUrl = normalized);
      return;
    }

    final fetched = await _fetchArtworkFromItunes(
      widget.song.artist,
      widget.song.title,
    );
    if (!mounted) return;
    setState(() => _resolvedArtworkUrl = fetched);
  }

  String? _normalizeArtworkUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    if (url.startsWith('file://') || url.startsWith('content://')) {
      return url;
    }
    return url
        .replaceAll('{w}x{h}bb', '600x600bb')
        .replaceAll('{w}x{h}', '600x600');
  }

  Future<String?> _fetchArtworkFromItunes(String artist, String title) async {
    try {
      final dio = Dio();
      final response = await dio.get(
        'https://itunes.apple.com/search',
        queryParameters: {
          'term': '$artist $title',
          'entity': 'song',
          'limit': 1,
        },
      );
      if (response.statusCode != 200 || response.data == null) return null;
      final data = response.data as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];
      if (results.isEmpty) return null;
      final result = results.first as Map<String, dynamic>;
      final artworkUrl = result['artworkUrl100'] as String?;
      if (artworkUrl == null || artworkUrl.isEmpty) return null;
      return artworkUrl.replaceAll('100x100', '600x600');
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.surfaceColor : AppTheme.lightSurface;
    final surfaceLight = isDark
        ? AppTheme.surfaceLight
        : AppTheme.lightSurfaceLight;
    return GestureDetector(
      onTap: widget.onTap,
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
                            surfaceColor.withValues(alpha: 0.8),
                            surfaceLight.withValues(alpha: 0.6),
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
                            _buildAlbumArt(surfaceLight),
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

  Widget _buildAlbumArt(Color surfaceLight) {
    // Debug: Print artwork URL to console
    final artworkUrl = _resolvedArtworkUrl;

    if (artworkUrl != null && artworkUrl.isNotEmpty) {
      debugPrint('🎨 Album art URL: $artworkUrl');
    } else {
      debugPrint('🎨 No album art URL available for: ${widget.song.title}');
    }

    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: (artworkUrl != null && artworkUrl.isNotEmpty)
            ? _buildArtworkImage(artworkUrl, surfaceLight)
            : _buildArtPlaceholder(surfaceLight),
      ),
    );
  }

  Widget _buildArtworkImage(String artworkUrl, Color surfaceLight) {
    final uri = Uri.tryParse(artworkUrl);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progressColor = isDark
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;
    if (uri != null && uri.scheme == 'file') {
      return Image.file(
        File(uri.toFilePath()),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('🎨 Failed to load local album art: $error');
          return _buildArtPlaceholder(surfaceLight);
        },
      );
    }

    return Image.network(
      artworkUrl,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: surfaceLight,
          child: Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                  : null,
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        debugPrint('🎨 Failed to load album art: $error');
        return _buildArtPlaceholder(surfaceLight);
      },
    );
  }

  Widget _buildArtPlaceholder(Color surfaceLight) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;
    return Container(
      decoration: BoxDecoration(color: surfaceLight),
      child: Center(
        child: Icon(Icons.music_note_rounded, color: iconColor, size: 32),
      ),
    );
  }

  Widget _buildSongInfo(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? AppTheme.textPrimary
        : AppTheme.lightTextPrimary;
    final textSecondary = isDark
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;
    final accent = isDark ? AppTheme.primaryLight : AppTheme.primaryDark;
    final rawSource = widget.song.source?.trim() ?? '';
    final displaySource = rawSource.isEmpty ? 'Media Player' : rawSource;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [textPrimary, accent],
          ).createShader(bounds),
          child: Text(
            widget.song.title,
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
          widget.song.artist,
          style: textTheme.bodyMedium?.copyWith(color: textSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        _buildSourceBadge(displaySource, isDark),
      ],
    );
  }

  Widget _buildSourceBadge(String source, bool isDark) {
    final sourceColor = _getSourceColor(source);
    final bgAlpha = isDark ? 0.25 : 0.18;
    final bgAlphaLight = isDark ? 0.15 : 0.12;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            sourceColor.withValues(alpha: bgAlpha),
            sourceColor.withValues(alpha: bgAlphaLight),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: sourceColor.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_getSourceIcon(source), size: 12, color: sourceColor),
          const SizedBox(width: 4),
          Text(
            source,
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

  Color _getSourceColor(String source) {
    switch (source.toLowerCase()) {
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

  IconData _getSourceIcon(String source) {
    switch (source.toLowerCase()) {
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
