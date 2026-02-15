import 'dart:async';

/// Debounce utility for delaying function calls
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({required this.delay});

  /// Run the action after the delay, canceling any previous pending call
  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  /// Cancel any pending action
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Check if there's a pending action
  bool get isPending => _timer?.isActive ?? false;

  /// Dispose the debouncer
  void dispose() {
    cancel();
  }
}

/// Throttle utility for rate-limiting function calls
class Throttler {
  final Duration interval;
  DateTime? _lastRun;
  Timer? _pendingTimer;

  Throttler({required this.interval});

  /// Run the action immediately if interval has passed, otherwise schedule
  void run(void Function() action) {
    final now = DateTime.now();

    if (_lastRun == null || now.difference(_lastRun!) >= interval) {
      _lastRun = now;
      action();
    } else {
      // Schedule to run after remaining time
      _pendingTimer?.cancel();
      final remaining = interval - now.difference(_lastRun!);
      _pendingTimer = Timer(remaining, () {
        _lastRun = DateTime.now();
        action();
      });
    }
  }

  /// Cancel any pending action
  void cancel() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
  }

  void dispose() {
    cancel();
  }
}

/// String utilities
extension StringExtensions on String {
  /// Capitalize first letter
  String get capitalize {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }

  /// Title case (capitalize each word)
  String get titleCase {
    if (isEmpty) return this;
    return split(' ').map((word) => word.capitalize).join(' ');
  }

  /// Remove extra whitespace
  String get normalizeWhitespace {
    return replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Check if string is a valid URL
  bool get isValidUrl {
    return Uri.tryParse(this)?.hasAbsolutePath ?? false;
  }

  /// Truncate with ellipsis
  String truncate(int maxLength, {String suffix = '...'}) {
    if (length <= maxLength) return this;
    return '${substring(0, maxLength - suffix.length)}$suffix';
  }
}

/// Duration utilities
extension DurationExtensions on Duration {
  /// Format as mm:ss
  String get formatted {
    final minutes = inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// Format as hh:mm:ss if >= 1 hour
  String get formattedLong {
    if (inHours > 0) {
      final hours = inHours.toString().padLeft(2, '0');
      final minutes = inMinutes.remainder(60).toString().padLeft(2, '0');
      final seconds = inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return formatted;
  }
}

/// List utilities
extension ListExtensions<T> on List<T> {
  /// Get element at index or null if out of bounds
  T? getOrNull(int index) {
    if (index < 0 || index >= length) return null;
    return this[index];
  }

  /// Get first element matching predicate or null
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
