import 'package:flutter/material.dart';
import '../../services/review_service.dart';

enum ReviewChoice { later, never, now }

Future<void> showReviewPrompt(
  BuildContext context,
  ReviewService service,
) async {
  if (!service.shouldPrompt || !context.mounted) return;
  service.markShown();
  final choice = await showDialog<ReviewChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.star_rate_rounded, size: 40, color: Color(0xFFFFC107)),
      title: const Text('Enjoying FlashLyrics?'),
      content: const Text(
        'If FlashLyrics helps you sing along, please take a moment to rate it on Google Play. It really helps the app grow.',
      ),
      actionsOverflowDirection: VerticalDirection.up,
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, ReviewChoice.never),
          child: const Text("Don't remind me again"),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, ReviewChoice.later),
          child: const Text('Remind me later'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, ReviewChoice.now),
          icon: const Icon(Icons.shop_rounded, size: 18),
          label: const Text('Rate on Google Play'),
        ),
      ],
    ),
  );
  if (choice == ReviewChoice.never) {
    await service.never();
    return;
  }
  if (choice != ReviewChoice.now) {
    await service.later();
    return;
  }
  if (await service.openReviewPage()) {
    await service.never();
  } else {
    await service.later();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Google Play. Try again from Settings.'),
        ),
      );
    }
  }
}
