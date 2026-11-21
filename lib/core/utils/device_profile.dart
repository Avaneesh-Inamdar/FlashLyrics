import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/update_check_service.dart';

/// What kind of screen the app is running on.
enum FormFactor { phone, tablet, tv }

/// True when the app runs on an Android TV / Google TV device.
/// Overridden in main() with the value reported by the platform.
final isTelevisionProvider = Provider<bool>((ref) => false);

/// Lets tests replace the Google Play update check.
final updateCheckServiceProvider = Provider<UpdateCheckService>(
  (ref) => UpdateCheckService(),
);

class DeviceProfile {
  DeviceProfile._();

  static const MethodChannel _channel = MethodChannel('com.lyricx/media');

  /// Width (dp) from which the side navigation rail replaces the bottom bar.
  static const double railBreakpoint = 720;

  /// Width (dp) from which the Listening screen splits into two panes.
  static const double twoPaneBreakpoint = 900;

  /// Widest a single column of content gets before it is centred.
  static const double maxContentWidth = 900;

  /// Asks the platform whether this is a TV. Phones and tablets, or any
  /// failure, answer false.
  static Future<bool> detectTelevision() async {
    try {
      return await _channel.invokeMethod<bool>('isTelevision') ?? false;
    } catch (_) {
      return false;
    }
  }

  static FormFactor formFactor(Size size, {required bool isTv}) {
    if (isTv) return FormFactor.tv;
    return math.min(size.width, size.height) >= 600
        ? FormFactor.tablet
        : FormFactor.phone;
  }

  /// Orientations the app may use: phones stay in portrait, tablets and TVs
  /// rotate freely (TVs are always landscape in practice).
  static List<DeviceOrientation> orientationsFor(FormFactor f) =>
      f == FormFactor.phone
      ? const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
      : const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ];

  static bool useRail(double width) => width >= railBreakpoint;
  static bool useTwoPane(double width) => width >= twoPaneBreakpoint;
}

/// Centres [child] and limits it to [maxWidth] so lists and forms do not
/// stretch across a tablet or TV screen.
class AdaptiveWidth extends StatelessWidget {
  const AdaptiveWidth({
    super.key,
    required this.child,
    this.maxWidth = DeviceProfile.maxContentWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
