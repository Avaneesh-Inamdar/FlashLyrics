import '../../domain/entities/song.dart';

/// Song data model for JSON serialization
class SongModel extends Song {
  const SongModel({
    required super.id,
    required super.title,
    required super.artist,
    super.album,
    super.artworkUrl,
    super.duration,
    super.source,
  });

  /// Create from JSON
  factory SongModel.fromJson(Map<String, dynamic> json) {
    return SongModel(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String?,
      artworkUrl: json['artworkUrl'] as String?,
      duration: json['duration'] != null
          ? Duration(milliseconds: json['duration'] as int)
          : null,
      source: json['source'] as String?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'artworkUrl': artworkUrl,
      'duration': duration?.inMilliseconds,
      'source': source,
    };
  }

  /// Create from domain entity
  factory SongModel.fromEntity(Song song) {
    return SongModel(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      artworkUrl: song.artworkUrl,
      duration: song.duration,
      source: song.source,
    );
  }
}
