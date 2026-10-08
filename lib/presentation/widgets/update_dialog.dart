import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key});
  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  late final Future<Map<Object?, Object?>?> _check =
      const MethodChannel('com.lyricx/media')
          .invokeMapMethod<Object?, Object?>('checkForUpdates')
          .timeout(const Duration(seconds: 10));
  bool _opening = false;
  String? _storeError;

  Future<void> _openStore() async {
    setState(() {
      _opening = true;
      _storeError = null;
    });
    try {
      final opened = await launchUrl(
        Uri.parse(
          'https://play.google.com/store/apps/details?id=music.flashlyrics.app',
        ),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('No browser');
    } catch (_) {
      if (mounted)
        setState(
          () => _storeError = 'Could not open Google Play. Please try again.',
        );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('App updates'),
    content: FutureBuilder<Map<Object?, Object?>?>(
      future: _check,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Checking Google Play…'),
            ],
          );
        }
        final data = snapshot.data;
        final message = snapshot.hasError || data?['available'] is! bool
            ? 'Could not check for updates. Open Google Play to check manually.'
            : data!['available'] == true
            ? 'An update is available on Google Play.'
            : 'No update is available for this device on Google Play.';
        return Text(_storeError ?? message);
      },
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      TextButton(
        onPressed: _opening ? null : _openStore,
        child: const Text('Open Google Play'),
      ),
    ],
  );
}
