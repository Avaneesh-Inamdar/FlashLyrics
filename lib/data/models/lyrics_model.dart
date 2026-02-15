import '../../domain/entities/lyrics.dart';

/// Lyrics data model for JSON serialization
class LyricsModel extends Lyrics {
  /// Optional metadata for search results
  final String? artistName;
  final String? trackName;
  final String? albumName;

  const LyricsModel({
    required super.id,
    required super.songId,
    required super.plainLyrics,
    super.lrcLyrics,
    required super.isSynced,
    required super.source,
    required super.fetchedAt,
    this.artistName,
    this.trackName,
    this.albumName,
  });

  /// Create from JSON
  factory LyricsModel.fromJson(Map<String, dynamic> json) {
    return LyricsModel(
      id: json['id'] as String? ?? '',
      songId: json['songId'] as String? ?? '',
      plainLyrics: json['plainLyrics'] as String? ?? '',
      lrcLyrics: json['lrcLyrics'] as String?,
      isSynced: json['isSynced'] as bool? ?? false,
      source: json['source'] as String? ?? 'unknown',
      fetchedAt: json['fetchedAt'] != null
          ? DateTime.parse(json['fetchedAt'] as String)
          : DateTime.now(),
      artistName: json['artistName'] as String?,
      trackName: json['trackName'] as String?,
      albumName: json['albumName'] as String?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'songId': songId,
      'plainLyrics': plainLyrics,
      'lrcLyrics': lrcLyrics,
      'isSynced': isSynced,
      'source': source,
      'fetchedAt': fetchedAt.toIso8601String(),
      'artistName': artistName,
      'trackName': trackName,
      'albumName': albumName,
    };
  }

  /// Create from domain entity
  factory LyricsModel.fromEntity(Lyrics lyrics) {
    return LyricsModel(
      id: lyrics.id,
      songId: lyrics.songId,
      plainLyrics: lyrics.plainLyrics,
      lrcLyrics: lyrics.lrcLyrics,
      isSynced: lyrics.isSynced,
      source: lyrics.source,
      fetchedAt: lyrics.fetchedAt,
    );
  }

  /// Create from lyrics.ovh API response
  factory LyricsModel.fromApiResponse(
    String songId,
    Map<String, dynamic> json,
    String source,
  ) {
    return LyricsModel(
      id: '${songId}_${DateTime.now().millisecondsSinceEpoch}',
      songId: songId,
      plainLyrics: json['lyrics'] as String? ?? '',
      lrcLyrics: null,
      isSynced: false,
      source: source,
      fetchedAt: DateTime.now(),
    );
  }
}
