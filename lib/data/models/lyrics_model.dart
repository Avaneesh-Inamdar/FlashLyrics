import '../../domain/entities/lyrics.dart';

/// Lyrics data model for JSON serialization
class LyricsModel extends Lyrics {
  /// Optional metadata for search results
  final String? artistName;
  final String? trackName;
  final String? albumName;
  final String? sourceUrl;
  final String? artworkUrl;
  final bool isUserProvided;

  /// Verified by an automatic metadata match or an explicit local import.
  final bool isMatchVerified;

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
    this.sourceUrl,
    this.artworkUrl,
    this.isUserProvided = false,
    this.isMatchVerified = false,
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
      sourceUrl: json['sourceUrl'] as String?,
      artworkUrl: json['artworkUrl'] as String?,
      isUserProvided: json['isUserProvided'] as bool? ?? false,
      isMatchVerified: json['isMatchVerified'] as bool? ?? false,
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
      'sourceUrl': sourceUrl,
      'artworkUrl': artworkUrl,
      'isUserProvided': isUserProvided,
      'isMatchVerified': isMatchVerified,
    };
  }

  @override
  LyricsModel copyWith({
    String? id,
    String? songId,
    String? plainLyrics,
    String? lrcLyrics,
    bool? isSynced,
    String? source,
    DateTime? fetchedAt,
    String? artistName,
    String? trackName,
    String? albumName,
    String? sourceUrl,
    String? artworkUrl,
    bool? isMatchVerified,
    bool? isUserProvided,
  }) => LyricsModel(
    id: id ?? this.id,
    songId: songId ?? this.songId,
    plainLyrics: plainLyrics ?? this.plainLyrics,
    lrcLyrics: lrcLyrics ?? this.lrcLyrics,
    isSynced: isSynced ?? this.isSynced,
    source: source ?? this.source,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    artistName: artistName ?? this.artistName,
    trackName: trackName ?? this.trackName,
    albumName: albumName ?? this.albumName,
    sourceUrl: sourceUrl ?? this.sourceUrl,
    artworkUrl: artworkUrl ?? this.artworkUrl,
    isMatchVerified: isMatchVerified ?? this.isMatchVerified,
    isUserProvided: isUserProvided ?? this.isUserProvided,
  );

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
      isMatchVerified: false,
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
