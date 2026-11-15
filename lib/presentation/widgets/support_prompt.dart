import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/support_prompt_service.dart';
import '../providers/providers.dart';

enum SupportChoice { never, later, ok }

/// Asks the user to support the free app by turning ads on (or, when ads are
/// already on, by watching a short ad). "OK" opens Settings and highlights
/// the matching option.
Future<void> showSupportPrompt(BuildContext context, WidgetRef ref) async {
  final service = ref.read(supportPromptServiceProvider);
  final adsOn = ref.read(settingsProvider).enableAds;
  final choice = await showDialog<SupportChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        Icons.volunteer_activism_rounded,
        size: 36,
        color: Theme.of(ctx).colorScheme.primary,
      ),
      title: const Text('FlashLyrics is free'),
      content: Text(
        adsOn
            ? 'FlashLyrics is free and supported by ads. If you enjoy it, please consider watching a short ad to support development.'
            : 'FlashLyrics is free and supported by ads. Please turn ads on or watch a short ad to help keep it free and updated.',
      ),
      actionsOverflowDirection: VerticalDirection.up,
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, SupportChoice.never),
          child: const Text('No thanks'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, SupportChoice.later),
          child: const Text('Remind me later'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, SupportChoice.ok),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  switch (choice) {
    case SupportChoice.never:
      await service.never();
    case SupportChoice.ok:
      await service.snooze();
      ref.read(tabIndexProvider.notifier).setIndex(3);
      ref.read(settingsHighlightProvider.notifier).state = adsOn
          ? SupportHighlight.watchAd
          : SupportHighlight.adsToggle;
    case SupportChoice.later:
    case null:
      await service.snooze();
  }
}
