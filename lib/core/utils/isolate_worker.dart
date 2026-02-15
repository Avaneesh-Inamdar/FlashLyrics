import 'package:flutter/foundation.dart';

/// Isolate worker for CPU-intensive tasks
class IsolateWorker {
  /// Run a function in an isolate
  /// Uses Flutter's compute() which is optimized for the platform
  static Future<R> run<P, R>(ComputeCallback<P, R> callback, P message) async {
    return compute(callback, message);
  }

  /// Run multiple tasks in parallel using isolates
  static Future<List<R>> runParallel<P, R>(
    ComputeCallback<P, R> callback,
    List<P> messages,
  ) async {
    return Future.wait(messages.map((m) => compute(callback, m)));
  }

  /// Parse JSON in isolate
  static Future<Map<String, dynamic>> parseJson(String json) async {
    return compute(_parseJsonSync, json);
  }

  static Map<String, dynamic> _parseJsonSync(String json) {
    // ignore: avoid_dynamic_calls
    return Map<String, dynamic>.from((jsonDecode(json) as Map));
  }
}

// JSON decode function for isolate
dynamic jsonDecode(String source) {
  return const JsonDecoder().convert(source);
}

/// JSON decoder that works in isolates
class JsonDecoder {
  const JsonDecoder();

  dynamic convert(String input) {
    return _parseValue(input, 0).$1;
  }

  (dynamic, int) _parseValue(String input, int pos) {
    pos = _skipWhitespace(input, pos);
    if (pos >= input.length) throw const FormatException('Unexpected end');

    switch (input[pos]) {
      case '{':
        return _parseObject(input, pos);
      case '[':
        return _parseArray(input, pos);
      case '"':
        return _parseString(input, pos);
      case 't':
      case 'f':
        return _parseBool(input, pos);
      case 'n':
        return _parseNull(input, pos);
      default:
        return _parseNumber(input, pos);
    }
  }

  int _skipWhitespace(String input, int pos) {
    while (pos < input.length && ' \t\n\r'.contains(input[pos])) {
      pos++;
    }
    return pos;
  }

  (Map<String, dynamic>, int) _parseObject(String input, int pos) {
    pos++; // skip '{'
    final map = <String, dynamic>{};

    pos = _skipWhitespace(input, pos);
    if (pos < input.length && input[pos] == '}') {
      return (map, pos + 1);
    }

    while (true) {
      pos = _skipWhitespace(input, pos);
      final (key, newPos) = _parseString(input, pos);
      pos = _skipWhitespace(input, newPos);
      if (input[pos] != ':') throw FormatException('Expected ":" at $pos');
      pos++;
      final (value, valuePos) = _parseValue(input, pos);
      map[key] = value;
      pos = _skipWhitespace(input, valuePos);
      if (input[pos] == '}') return (map, pos + 1);
      if (input[pos] != ',')
        throw FormatException('Expected "," or "}" at $pos');
      pos++;
    }
  }

  (List<dynamic>, int) _parseArray(String input, int pos) {
    pos++; // skip '['
    final list = <dynamic>[];

    pos = _skipWhitespace(input, pos);
    if (pos < input.length && input[pos] == ']') {
      return (list, pos + 1);
    }

    while (true) {
      final (value, newPos) = _parseValue(input, pos);
      list.add(value);
      pos = _skipWhitespace(input, newPos);
      if (input[pos] == ']') return (list, pos + 1);
      if (input[pos] != ',')
        throw FormatException('Expected "," or "]" at $pos');
      pos++;
    }
  }

  (String, int) _parseString(String input, int pos) {
    pos++; // skip opening quote
    final buffer = StringBuffer();

    while (pos < input.length) {
      final char = input[pos];
      if (char == '"') return (buffer.toString(), pos + 1);
      if (char == '\\') {
        pos++;
        if (pos >= input.length) throw const FormatException('Unexpected end');
        switch (input[pos]) {
          case '"':
          case '\\':
          case '/':
            buffer.write(input[pos]);
            break;
          case 'n':
            buffer.write('\n');
            break;
          case 'r':
            buffer.write('\r');
            break;
          case 't':
            buffer.write('\t');
            break;
          case 'u':
            if (pos + 4 >= input.length)
              throw const FormatException('Invalid unicode');
            final hex = input.substring(pos + 1, pos + 5);
            buffer.writeCharCode(int.parse(hex, radix: 16));
            pos += 4;
            break;
        }
      } else {
        buffer.write(char);
      }
      pos++;
    }
    throw const FormatException('Unterminated string');
  }

  (num, int) _parseNumber(String input, int pos) {
    final start = pos;
    if (input[pos] == '-') pos++;

    while (pos < input.length && '0123456789'.contains(input[pos])) {
      pos++;
    }

    if (pos < input.length && input[pos] == '.') {
      pos++;
      while (pos < input.length && '0123456789'.contains(input[pos])) {
        pos++;
      }
    }

    if (pos < input.length && 'eE'.contains(input[pos])) {
      pos++;
      if (pos < input.length && '+-'.contains(input[pos])) pos++;
      while (pos < input.length && '0123456789'.contains(input[pos])) {
        pos++;
      }
    }

    final numStr = input.substring(start, pos);
    if (numStr.contains('.') || numStr.contains('e') || numStr.contains('E')) {
      return (double.parse(numStr), pos);
    }
    return (int.parse(numStr), pos);
  }

  (bool, int) _parseBool(String input, int pos) {
    if (input.substring(pos).startsWith('true')) {
      return (true, pos + 4);
    }
    if (input.substring(pos).startsWith('false')) {
      return (false, pos + 5);
    }
    throw FormatException('Invalid boolean at $pos');
  }

  (dynamic, int) _parseNull(String input, int pos) {
    if (input.substring(pos).startsWith('null')) {
      return (null, pos + 4);
    }
    throw FormatException('Invalid null at $pos');
  }
}
