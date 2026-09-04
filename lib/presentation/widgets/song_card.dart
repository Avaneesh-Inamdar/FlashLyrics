import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
    // If normalized is a file:// URL, verify file exists; otherwise fallback to iTunes
    if (normalized != null) {
      if (normalized.startsWith('file://')) {
        final filePath = _filePathFromUrl(normalized);
        if (filePath != null && await File(filePath).exists()) {
          if (!mounted) return;
          setState(() => _resolvedArtworkUrl = normalized);
          return;
        }
        // File doesn't exist (stale cache) -> fall through to network fallback
      } else if (!normalized.startsWith('content://')) {
        // Valid http/https url
        if (!mounted) return;
        setState(() => _resolvedArtworkUrl = normalized);
        return;
      }
      // content:// cannot be rendered directly by Flutter -> fallback to iTunes
    }

    final fetched = await _fetchArtworkFromItunes(
      widget.song.artist,
      widget.song.title,
    );
    if (!mounted) return;
    if (fetched != null) {
      setState(() => _resolvedArtworkUrl = fetched);
    } else if (normalized != null && !normalized.startsWith('content://')) {
      setState(() => _resolvedArtworkUrl = normalized);
    } else {
      setState(() => _resolvedArtworkUrl = null);
    }
  }

  String? _filePathFromUrl(String fileUrl) {
    try {
      final uri = Uri.parse(fileUrl);
      if (uri.scheme == 'file') return uri.toFilePath();
      // Handle malformed file:/path (single slash) from older caches
      if (fileUrl.startsWith('file:/')) {
        return fileUrl.replaceFirst(RegExp(r'^file:/+'), '/');
      }
      return fileUrl;
    } catch (_) {
      return null;
    }
  }

  String? _normalizeArtworkUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final trimmed = url.trim();
    // Handle file URIs (including file:/ with single slash from old cache)
    if (trimmed.startsWith('file://') || trimmed.startsWith('file:/')) {
      // Normalize to proper file://
      final path = trimmed.replaceFirst(RegExp(r'^file:/+'), '/');
      return 'file://$path';
    }
    if (trimmed.startsWith('content://')) {
      return trimmed;
    }
    // Remote URL cleanup
    var cleaned = trimmed
        .replaceAll('{w}x{h}bb', '600x600bb')
        .replaceAll('{w}x{h}', '600x600')
        .replaceAll('100x100bb', '600x600bb')
        .replaceAll('100x100', '600x600');
    // Ensure https for network images (Android 10+ cleartext issues)
    if (cleaned.startsWith('http://')) {
      cleaned = cleaned.replaceFirst('http://', 'https://');
    }
    return cleaned;
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
    // Reduced blur & gradient for performance - solid surface improves recents preview
    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: surfaceLight, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _buildAlbumArt(surfaceLight),
                const SizedBox(width: 14),
                Expanded(child: _buildSongInfo(context)),
                _buildPlayingIndicator(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumArt(Color surfaceLight) {
    final artworkUrl = _resolvedArtworkUrl;

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progressColor = isDark
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;
    // Handle file:// URIs robustly, including legacy single-slash format
    if (artworkUrl.startsWith('file://') || artworkUrl.startsWith('file:/')) {
      final path = _filePathFromUrl(artworkUrl);
      if (path != null) {
        final file = File(path);
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('🎨 Failed to load local album art: $error path=$path');
            // Fallback to network iTunes fetch placeholder; trigger async refetch?
            return _buildArtPlaceholder(surfaceLight);
          },
        );
      }
    }
    // content:// cannot be loaded directly - show placeholder and rely on iTunes fallback
    if (artworkUrl.startsWith('content://')) {
      return _buildArtPlaceholder(surfaceLight);
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
    final rawSource = widget.song.source?.trim() ?? '';
    final displaySource = rawSource.isEmpty ? 'Media Player' : rawSource;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.song.title,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: sourceColor.withValues(alpha: isDark ? 0.15 : 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: sourceColor.withValues(alpha: 0.3),
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
    // Static indicator - no repeating animation to avoid recents lag
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Icon(Icons.equalizer_rounded, color: Colors.white, size: 18),
      ),
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
