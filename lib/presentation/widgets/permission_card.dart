import 'package:flutter/material.dart';

/// Explains media detection with readable surfaces in both themes.
class PermissionCard extends StatelessWidget {
  final VoidCallback onRequestPermission;
  final VoidCallback onCheckAgain;

  const PermissionCard({
    super.key,
    required this.onRequestPermission,
    required this.onCheckAgain,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.graphic_eq, size: 36, color: theme.colorScheme.primary),
          const SizedBox(height: 24),
          Text(
            'Your music.\nThe words behind it.',
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          Text(
            'Play a song in your music app. FlashLyrics will find the words and follow along.',
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(),
          ),
          Text(
            'CONNECT YOUR MUSIC',
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.6),
          ),
          const SizedBox(height: 10),
          Text(
            'Allow notification access to detect the song title and artist from Spotify, YouTube Music, and other players.',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onRequestPermission,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Connect music player'),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: onCheckAgain,
              child: const Text(
                'Already connected? Check again',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You can also search for lyrics without connecting a player.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
