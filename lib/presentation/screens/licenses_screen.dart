import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class LicensesScreen extends StatelessWidget {
  const LicensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Open Source Licenses')),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.backgroundGradient : AppTheme.lightBackgroundGradient,
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            ListTile(title: Text('Flutter'), subtitle: Text('BSD 3-Clause')),
            ListTile(title: Text('Riverpod'), subtitle: Text('MIT')),
            ListTile(title: Text('Dio'), subtitle: Text('MIT')),
            ListTile(title: Text('share_plus'), subtitle: Text('BSD 3-Clause')),
            ListTile(title: Text('google_fonts'), subtitle: Text('Apache 2.0')),
            ListTile(title: Text('flutter_animate'), subtitle: Text('MIT')),
          ],
        ),
      ),
    );
  }
}
