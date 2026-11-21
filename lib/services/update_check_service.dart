import 'package:flutter/services.dart';

/// Result of asking Google Play whether a newer FlashLyrics is available.
enum UpdateStatus { available, upToDate, unknown }

/// Asks Google Play (through the native in-app-update API) whether a newer
/// version is published. It never downloads or installs anything: the app
/// only tells the user to update from Google Play.
class UpdateCheckService {
  UpdateCheckService({
    Future<Map<Object?, Object?>?> Function()? query,
    this.timeout = const Duration(seconds: 10),
  }) : _query = query ?? _nativeQuery;

  static const MethodChannel _channel = MethodChannel('com.lyricx/media');

  static Future<Map<Object?, Object?>?> _nativeQuery() =>
      _channel.invokeMapMethod<Object?, Object?>('checkForUpdates');

  final Future<Map<Object?, Object?>?> Function() _query;
  final Duration timeout;

  /// Play only answers for installs from Google Play. Sideloaded builds,
  /// emulators without Play and offline devices come back as [unknown].
  Future<UpdateStatus> check() async {
    try {
      final data = await _query().timeout(timeout);
      final available = data?['available'];
      if (available is! bool) return UpdateStatus.unknown;
      return available ? UpdateStatus.available : UpdateStatus.upToDate;
    } catch (_) {
      return UpdateStatus.unknown;
    }
  }
}
