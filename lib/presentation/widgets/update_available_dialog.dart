import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/update_check_service.dart';

const String playStoreUrl =
    'https://play.google.com/store/apps/details?id=music.flashlyrics.app';

/// Checks Google Play once and, if a newer version is out, tells the user
/// to download it from the Play Store. Does nothing when no update is
/// available or Play cannot tell (sideloaded build, offline, ...).
///
/// Returns true when the notice was shown.
Future<bool> maybeShowUpdateNotice(
  BuildContext context, {
  UpdateCheckService? service,
  Future<bool> Function(Uri url)? openUrl,
}) async {
  final status = await (service ?? UpdateCheckService()).check();
  if (status != UpdateStatus.available || !context.mounted) return false;
  await showDialog<void>(
    context: context,
    builder: (_) => UpdateAvailableDialog(openUrl: openUrl),
  );
  return true;
}

class UpdateAvailableDialog extends StatelessWidget {
  const UpdateAvailableDialog({super.key, this.openUrl});

  final Future<bool> Function(Uri url)? openUrl;

  Future<void> _download(BuildContext context) async {
    final open =
        openUrl ??
        (Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);
    try {
      await open(Uri.parse(playStoreUrl));
    } catch (_) {}
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.system_update_rounded),
    title: const Text('New version available'),
    content: const Text(
      'A new version of FlashLyrics is available. '
      'Please download it from the Play Store.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Later'),
      ),
      FilledButton(
        autofocus: true,
        onPressed: () => _download(context),
        child: const Text('Open Play Store'),
      ),
    ],
  );
}
