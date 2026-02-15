/// Base class for all app exceptions
abstract class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  const AppException({required this.message, this.code, this.originalError});

  @override
  String toString() => 'AppException: $message (code: $code)';
}

/// Network related exceptions
class NetworkException extends AppException {
  const NetworkException({
    required super.message,
    super.code,
    super.originalError,
  });
}

/// Server exceptions
class ServerException extends AppException {
  final int? statusCode;

  const ServerException({
    required super.message,
    this.statusCode,
    super.code,
    super.originalError,
  });
}

/// Cache exceptions
class CacheException extends AppException {
  const CacheException({
    required super.message,
    super.code,
    super.originalError,
  });
}

/// Lyrics not found exception
class LyricsNotFoundException extends AppException {
  const LyricsNotFoundException({
    super.message = 'Lyrics not found for this song',
    super.code,
    super.originalError,
  });
}

/// Permission denied exception
class PermissionDeniedException extends AppException {
  const PermissionDeniedException({
    required super.message,
    super.code,
    super.originalError,
  });
}

/// Media detection exception
class MediaDetectionException extends AppException {
  const MediaDetectionException({
    required super.message,
    super.code,
    super.originalError,
  });
}
