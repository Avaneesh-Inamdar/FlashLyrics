import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lyricx/presentation/widgets/notification_tip.dart';
import 'package:lyricx/presentation/widgets/update_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final status in [true, false, null]) {
    testWidgets('Play update check handles $status', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('com.lyricx/media'), (
            _,
          ) async {
            if (status == null) throw PlatformException(code: 'offline');
            return {'available': status, 'versionCode': 12};
          });
      await tester.pumpWidget(const MaterialApp(home: UpdateDialog()));
      await tester.pumpAndSettle();
      expect(
        find.text(
          status == null
              ? 'Could not check for updates. Open Google Play to check manually.'
              : status
              ? 'An update is available on Google Play.'
              : 'No update is available for this device on Google Play.',
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    'Float tip is shown once after acknowledgement and can be reopened',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      late BuildContext host;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              host = context;
              return const Scaffold();
            },
          ),
        ),
      );
      final first = showNotificationTip(host, prefs);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Expand the FlashLyrics notification'),
        findsOneWidget,
      );
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      await first;
      await showNotificationTip(host, prefs);
      await tester.pumpAndSettle();
      expect(find.text('Lyrics over your music'), findsNothing);
      final reopened = showNotificationTip(host, prefs, always: true);
      await tester.pumpAndSettle();
      expect(find.text('Lyrics over your music'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      await reopened;
    },
  );
}
