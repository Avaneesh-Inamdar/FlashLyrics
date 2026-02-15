import 'package:equatable/equatable.dart';

/// Song entity representing a track
class Song extends Equatable {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? artworkUrl;
  final Duration? duration;
  final String? source; // Spotify, YouTube Music, Apple Music, etc.

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.artworkUrl,
    this.duration,
    this.source,
  });

  @override
  List<Object?> get props => [
    id,
    title,
    artist,
    album,
    artworkUrl,
    duration,
    source,
  ];

  Song copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? artworkUrl,
    Duration? duration,
    String? source,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      duration: duration ?? this.duration,
      source: source ?? this.source,
    );
  }
}
