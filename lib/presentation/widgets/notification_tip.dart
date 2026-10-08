import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> showNotificationTip(
  BuildContext context,
  SharedPreferences prefs, {
  bool always = false,
}) async {
  const key = 'notification_float_tip_seen_v1';
  if (!always && prefs.getBool(key) == true) return;
  if (!context.mounted) return;
  final acknowledged = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.picture_in_picture_alt_rounded),
      title: const Text('Lyrics over your music'),
      content: const Text(
        'While a song is playing, swipe down from the top of your screen. '
        'Expand the FlashLyrics notification, then tap Float to show lyrics over other apps.\n\n'
        'Android may ask you to allow “Display over other apps” the first time.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
  if (acknowledged == true) await prefs.setBool(key, true);
}
