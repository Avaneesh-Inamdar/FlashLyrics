/// Shared cache identity. Preserve combining marks used by many languages.
String songKey(String artist, String title) =>
    '${artist.trim()}_${title.trim()}'
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}_]+', unicode: true), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
