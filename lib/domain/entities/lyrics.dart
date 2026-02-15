import 'package:equatable/equatable.dart';

/// Lyrics entity representing song lyrics
class Lyrics extends Equatable {
  final String id;
  final String songId;
  final String plainLyrics;
  final String? lrcLyrics; // Synchronized lyrics in LRC format
  final bool isSynced;
  final String source; // API source where lyrics were fetched from
  final DateTime fetchedAt;

  const Lyrics({
    required this.id,
    required this.songId,
    required this.plainLyrics,
    this.lrcLyrics,
    required this.isSynced,
    required this.source,
    required this.fetchedAt,
  });

  @override
  List<Object?> get props => [
    id,
    songId,
    plainLyrics,
    lrcLyrics,
    isSynced,
    source,
    fetchedAt,
  ];

  /// Get lyrics as list of lines
  List<String> get lines =>
      plainLyrics.split('\n').where((line) => line.trim().isNotEmpty).toList();

  Lyrics copyWith({
    String? id,
    String? songId,
    String? plainLyrics,
    String? lrcLyrics,
    bool? isSynced,
    String? source,
    DateTime? fetchedAt,
  }) {
    return Lyrics(
      id: id ?? this.id,
      songId: songId ?? this.songId,
      plainLyrics: plainLyrics ?? this.plainLyrics,
      lrcLyrics: lrcLyrics ?? this.lrcLyrics,
      isSynced: isSynced ?? this.isSynced,
      source: source ?? this.source,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }
}
