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
      icon: const Icon(Icons.rate_review_outlined),
      title: const Text('Rate FlashLyrics'),
      content: const Text(
        'Share your experience on Google Play. Your feedback helps improve FlashLyrics.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, ReviewChoice.never),
          child: const Text('Never'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, ReviewChoice.later),
          child: const Text('Ask me later'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ReviewChoice.now),
          child: const Text('Leave a review now'),
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
