import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/device_profile.dart';
import '../../services/media_detection_service.dart';

/// Whether the tour opens by itself on first install and after each update.
/// Off by default so screens can be built in tests; main() turns it on.
final appTourAutoShowProvider = Provider<bool>((ref) => false);

/// Stores the version of the app the tour was last shown for.
const String appTourSeenKey = 'app_tour_seen_version';

/// True on a fresh install and after every update of the app.
bool shouldShowAppTour(SharedPreferences prefs) =>
    prefs.getString(appTourSeenKey) != AppConstants.appVersion;

Future<void> markAppTourSeen(SharedPreferences prefs) =>
    prefs.setString(appTourSeenKey, AppConstants.appVersion);

class _TourPage {
  const _TourPage({
    required this.icon,
    required this.title,
    required this.body,
    this.bullets = const [],
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<(IconData, String)> bullets;
  final _TourAction? action;
}

enum _TourActionKind { notificationAccess }

class _TourAction {
  const _TourAction(this.label, this.kind);
  final String label;
  final _TourActionKind kind;
}

List<_TourPage> _pagesFor({required bool tv}) => [
  const _TourPage(
    icon: Icons.graphic_eq,
    title: 'Welcome to FlashLyrics',
    body:
        'Play a song in Spotify, YouTube Music or any other music app and '
        'FlashLyrics finds the words and follows along. This quick tour shows '
        'where everything is.',
  ),
  _TourPage(
    icon: Icons.notifications_active_rounded,
    title: 'Connect your music player',
    body:
        'FlashLyrics reads the song title and artist from your player\'s '
        'notification. Allow notification access once and it works with '
        'every player.',
    bullets: [
      (
        Icons.touch_app_rounded,
        tv
            ? 'Listening → Connect music player'
            : 'Listening tab → Connect music player',
      ),
      (Icons.tune, 'You can change this later in Settings → Permissions'),
    ],
    action: const _TourAction(
      'Allow notification access',
      _TourActionKind.notificationAccess,
    ),
  ),
  _TourPage(
    icon: Icons.graphic_eq,
    title: 'The Listening screen',
    body:
        'This is home. The current song and its lyrics appear here, scrolling '
        'in time with the music.',
    bullets: [
      (
        Icons.touch_app_rounded,
        tv
            ? 'Use the Pointer to click a line and jump there'
            : 'Tap a line to jump to that moment in the song',
      ),
      (
        Icons.ios_share_rounded,
        tv
            ? 'Hold OK on a line (pointer) to pick lines and share them'
            : 'Long-press a line to pick lines and share them as a picture',
      ),
      (
        Icons.timer_outlined,
        'Lyrics a little early or late? Adjust the sync offset',
      ),
    ],
  ),
  _TourPage(
    icon: Icons.fullscreen_rounded,
    title: 'Full player mode',
    body:
        'Tap the full-screen icon at the top right of the Listening screen '
        'when lyrics are showing. You get big, distraction-free lyrics.',
    bullets: [
      (Icons.fullscreen_rounded, 'Top right of the Listening screen'),
      (Icons.text_increase_rounded, 'Make the text bigger or smaller'),
      (Icons.arrow_back_rounded, 'Back leaves full screen'),
    ],
  ),
  if (!tv)
    const _TourPage(
      icon: Icons.picture_in_picture_alt_rounded,
      title: 'Lyrics over other apps',
      body:
          'Keep reading lyrics while you use your music app. While a song is '
          'playing, swipe down from the top of the screen to open the '
          'notification panel.',
      bullets: [
        (Icons.keyboard_arrow_down_rounded, 'Swipe down for notifications'),
        (Icons.music_note_rounded, 'Expand the FlashLyrics notification'),
        (Icons.open_in_new_rounded, 'Tap Float to show floating lyrics'),
        (
          Icons.layers_rounded,
          'Android asks to allow "Display over other apps" the first time',
        ),
      ],
    ),
  const _TourPage(
    icon: Icons.search,
    title: 'Search and Library',
    body:
        'Look up lyrics for any song from the Search tab. Lyrics you save are '
        'kept in the Library so they work offline.',
    bullets: [
      (Icons.search, 'Search: find lyrics from many sources'),
      (Icons.library_music_outlined, 'Library: saved and imported lyrics'),
      (Icons.upload_file_rounded, 'Import your own .lrc or text lyrics'),
    ],
  ),
  _TourPage(
    icon: Icons.tune,
    title: 'Settings',
    body: 'Make FlashLyrics yours.',
    bullets: [
      (
        Icons.sort_rounded,
        'Lyrics sources: reorder LRCLIB, KuGou, BetterLyrics, NetEase and more',
      ),
      (Icons.palette_outlined, 'Theme and accent colour, text size'),
      (Icons.music_note_rounded, 'Karaoke-style highlighting'),
      (Icons.replay_rounded, 'Replay this tour any time from Settings'),
    ],
  ),
  if (tv)
    const _TourPage(
      icon: Icons.mouse_rounded,
      title: 'Using a TV remote',
      body:
          'The arrow buttons move between items and OK selects. For things '
          'that cannot be selected, like lyric lines, turn on the Pointer.',
      bullets: [
        (Icons.mouse_outlined, 'Pointer button in the side menu, or press Menu'),
        (Icons.open_with_rounded, 'Arrows move the pointer, OK clicks'),
        (Icons.swap_vert_rounded, 'Push against the top or bottom edge to scroll'),
        (Icons.arrow_back_rounded, 'Back turns the pointer off'),
      ],
    ),
];

/// The first-run / what's-new walkthrough.
class AppTourScreen extends ConsumerStatefulWidget {
  const AppTourScreen({super.key});

  static Route<void> route() => MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => const AppTourScreen(),
  );

  @override
  ConsumerState<AppTourScreen> createState() => _AppTourScreenState();
}

class _AppTourScreenState extends ConsumerState<AppTourScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int page) => _controller.animateToPage(
    page,
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOut,
  );

  Future<void> _runAction(_TourAction action) async {
    switch (action.kind) {
      case _TourActionKind.notificationAccess:
        await MediaDetectionService.requestNotificationAccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tv = ref.watch(isTelevisionProvider);
    final pages = _pagesFor(tv: tv);
    final last = _index == pages.length - 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return PopScope(
      // Back steps to the previous page; on the first page it leaves the tour.
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index > 0) _go(_index - 1);
      },
      child: Scaffold(
        backgroundColor: isDark
            ? AppTheme.backgroundColor
            : AppTheme.lightBackground,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Skip'),
                      ),
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: pages.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (context, i) => _PageView(
                        page: pages[i],
                        onAction: _runAction,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < pages.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _index ? 22 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _index
                                ? theme.colorScheme.primary
                                : theme.colorScheme.primary.withValues(
                                    alpha: 0.25,
                                  ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                    child: Row(
                      children: [
                        if (_index > 0)
                          OutlinedButton(
                            onPressed: () => _go(_index - 1),
                            child: const Text('Back'),
                          ),
                        const Spacer(),
                        FilledButton(
                          autofocus: true,
                          onPressed: () {
                            if (last) {
                              Navigator.of(context).pop();
                            } else {
                              _go(_index + 1);
                            }
                          },
                          child: Text(last ? 'Get started' : 'Next'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageView extends StatelessWidget {
  const _PageView({required this.page, required this.onAction});

  final _TourPage page;
  final Future<void> Function(_TourAction) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(page.icon, size: 36, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 24),
          Text(page.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(
            page.body,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 18),
          for (final (icon, text) in page.bullets)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          if (page.action != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => onAction(page.action!),
              icon: const Icon(Icons.arrow_forward),
              label: Text(page.action!.label),
            ),
          ],
        ],
      ),
    );
  }
}

/// Opens the tour and remembers it was seen for this version.
Future<void> showAppTour(BuildContext context, SharedPreferences prefs) async {
  await markAppTourSeen(prefs);
  if (!context.mounted) return;
  await Navigator.of(context).push(AppTourScreen.route());
}
