import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../services/media_detection_service.dart';
import '../providers/settings_provider.dart';
import '../providers/media_provider.dart';
import 'licenses_screen.dart';

/// Settings screen with modern glassmorphism UI
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final mediaState = ref.watch(mediaNotifierProvider);
    final hasPermission = ref.watch(hasNotificationAccessProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Theme-aware background gradient
    final backgroundGradient = isDark
        ? AppTheme.backgroundGradient
        : AppTheme.lightBackgroundGradient;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: ShaderMask(
          shaderCallback: (bounds) =>
              AppTheme.primaryGradient.createShader(bounds),
          child: const Text(
            'Settings',
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: backgroundGradient),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            children: [
              _buildSection(
                context,
                title: 'PERMISSIONS',
                delay: 0,
                children: [
                  _buildGlassCard(
                    context,
                    child: _buildPermissionTile(context, hasPermission),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildSection(
                context,
                title: 'GENERAL',
                delay: 100,
                children: [
                  _buildGlassCard(
                    context,
                    child: Column(
                      children: [
                        _buildSwitchTile(
                          context,
                          icon: Icons.autorenew_rounded,
                          title: 'Auto-refresh',
                          subtitle: 'Detect song changes automatically',
                          value: settings.autoRefresh,
                          onChanged: (value) {
                            ref
                                .read(settingsProvider.notifier)
                                .setAutoRefresh(value);
                          },
                        ),
                        _buildDivider(context),
                        _buildSwitchTile(
                          context,
                          icon: Icons.sync_rounded,
                          title: 'Synced Lyrics',
                          subtitle: 'Show synchronized lyrics when available',
                          value: settings.showSyncedLyrics,
                          onChanged: (value) {
                            ref
                                .read(settingsProvider.notifier)
                                .setShowSyncedLyrics(value);
                          },
                        ),
                        _buildDivider(context),
                        _buildSwitchTile(
                          context,
                          icon: Icons.light_mode_rounded,
                          title: 'Keep Screen On',
                          subtitle:
                              'Prevent screen from turning off while viewing lyrics',
                          value: settings.keepScreenOn,
                          onChanged: (value) {
                            ref
                                .read(settingsProvider.notifier)
                                .setKeepScreenOn(value);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildSection(
                context,
                title: 'DISPLAY',
                delay: 200,
                children: [
                  _buildGlassCard(
                    context,
                    child: Column(
                      children: [
                        _buildTapTile(
                          context,
                          icon: Icons.palette_rounded,
                          title: 'Theme',
                          subtitle: settings.themeModeLabel,
                          onTap: () =>
                              _showThemeModeDialog(context, ref, settings),
                        ),
                        _buildDivider(context),
                        _buildTapTile(
                          context,
                          icon: Icons.brush_rounded,
                          title: 'Accent Color',
                          subtitle: settings.accentColorLabel,
                          onTap: () =>
                              _showAccentColorDialog(context, ref, settings),
                        ),
                        _buildDivider(context),
                        _buildTapTile(
                          context,
                          icon: Icons.text_fields_rounded,
                          title: 'Font Size',
                          subtitle: settings.fontSizeLabel,
                          onTap: () =>
                              _showFontSizeDialog(context, ref, settings),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildSection(
                context,
                title: 'LYRICS PROVIDERS',
                delay: 250,
                children: [
                  _buildGlassCard(
                    context,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text(
                            'Drag to reorder priority',
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? AppTheme.textHint
                                  : AppTheme.lightTextHint,
                            ),
                          ),
                        ),
                        ...List.generate(settings.providerPriority.length, (
                          index,
                        ) {
                          final provider = settings.providerPriority[index];
                          final displayName =
                              AppSettings.providerNames[provider] ?? provider;
                          return _buildProviderTile(
                            context,
                            ref,
                            index: index,
                            provider: provider,
                            displayName: displayName,
                            isFirst: index == 0,
                            isLast:
                                index == settings.providerPriority.length - 1,
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildSection(
                context,
                title: 'STATUS',
                delay: 300,
                children: [
                  _buildGlassCard(
                    context,
                    child: _buildStatusTile(context, mediaState),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildSection(
                context,
                title: 'ABOUT',
                delay: 400,
                children: [
                  _buildGlassCard(
                    context,
                    child: Column(
                      children: [
                        _buildTapTile(
                          context,
                          icon: Icons.info_outline_rounded,
                          title: 'App Version',
                          subtitle: AppConstants.appVersion,
                        ),
                        _buildDivider(context),
                        _buildTapTile(
                          context,
                          icon: Icons.gavel_rounded,
                          title: 'Open Source Licenses',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const LicensesScreen(),
                            ),
                          ),
                        ),
                        _buildDivider(context),
                        _buildTapTile(
                          context,
                          icon: Icons.restore_rounded,
                          title: 'Reset Settings',
                          subtitle: 'Restore default settings',
                          isDestructive: true,
                          onTap: () => _showResetConfirmation(context, ref),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required int delay,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryLight,
              letterSpacing: 1.2,
            ),
          ),
        ),
        ...children,
      ],
    ).animate().fadeIn(
      delay: Duration(milliseconds: delay),
      duration: 400.ms,
    );
  }

  Widget _buildGlassCard(BuildContext context, {required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.surfaceColor : AppTheme.lightSurface;
    final surfaceLight = isDark
        ? AppTheme.surfaceLight
        : AppTheme.lightSurfaceLight;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                surfaceColor.withValues(alpha: 0.7),
                surfaceLight.withValues(alpha: 0.5),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: surfaceLight.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Divider(
      height: 1,
      indent: 56,
      endIndent: 16,
      color: isDark ? const Color(0xFF2A2A3A) : const Color(0xFFE0E0E8),
    );
  }

  Widget _buildPermissionTile(
    BuildContext context,
    AsyncValue<bool> hasPermission,
  ) {
    return hasPermission.when(
      data: (granted) => _buildTapTile(
        context,
        icon: Icons.notifications_active_rounded,
        title: 'Notification Access',
        subtitle: granted ? 'Granted' : 'Required for music detection',
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: (granted ? AppTheme.successColor : Colors.orange).withValues(
              alpha: 0.15,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: (granted ? AppTheme.successColor : Colors.orange)
                  .withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                granted ? Icons.check_circle_rounded : Icons.warning_rounded,
                size: 16,
                color: granted ? AppTheme.successColor : Colors.orange,
              ),
              const SizedBox(width: 6),
              Text(
                granted ? 'Active' : 'Grant',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: granted ? AppTheme.successColor : Colors.orange,
                ),
              ),
            ],
          ),
        ),
        onTap: () async {
          await MediaDetectionService.requestNotificationAccess();
        },
      ),
      loading: () => _buildTapTile(
        context,
        icon: Icons.notifications_active_rounded,
        title: 'Notification Access',
        subtitle: 'Checking...',
        trailing: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, _) => _buildTapTile(
        context,
        icon: Icons.notifications_active_rounded,
        title: 'Notification Access',
        subtitle: 'Error checking status',
        trailing: const Icon(Icons.error_rounded, color: AppTheme.errorColor),
      ),
    );
  }

  Widget _buildStatusTile(BuildContext context, MediaState mediaState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? AppTheme.textPrimary
        : AppTheme.lightTextPrimary;
    final textSecondary = isDark
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;
    final textHint = isDark ? AppTheme.textHint : AppTheme.lightTextHint;
    final isActive = mediaState.isListening;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  (isActive ? AppTheme.successColor : textHint).withValues(
                    alpha: 0.2,
                  ),
                  (isActive ? AppTheme.successColor : textHint).withValues(
                    alpha: 0.1,
                  ),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.radio_button_on_rounded,
              color: isActive ? AppTheme.successColor : textHint,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Detection Status',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isActive ? 'Active — Listening for music' : 'Inactive',
                  style: TextStyle(fontSize: 13, color: textSecondary),
                ),
              ],
            ),
          ),
          Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: isActive ? AppTheme.successColor : textHint,
                  shape: BoxShape.circle,
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: AppTheme.successColor.withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
              )
              .animate(target: isActive ? 1 : 0, onPlay: (c) => c.repeat())
              .scale(
                begin: const Offset(1.0, 1.0),
                end: const Offset(1.3, 1.3),
                duration: 800.ms,
              )
              .then()
              .scale(
                begin: const Offset(1.3, 1.3),
                end: const Offset(1.0, 1.0),
                duration: 800.ms,
              ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? AppTheme.textPrimary
        : AppTheme.lightTextPrimary;
    final textSecondary = isDark
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryColor.withValues(alpha: 0.2),
                  AppTheme.primaryColor.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppTheme.primaryLight, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, color: textSecondary),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppTheme.primaryColor,
          ),
        ],
      ),
    );
  }

  Widget _buildTapTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? AppTheme.textPrimary
        : AppTheme.lightTextPrimary;
    final textSecondary = isDark
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;
    final textHint = isDark ? AppTheme.textHint : AppTheme.lightTextHint;
    final iconColor = isDestructive
        ? AppTheme.errorColor
        : AppTheme.primaryLight;
    final bgColor = isDestructive ? AppTheme.errorColor : AppTheme.primaryColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      bgColor.withValues(alpha: 0.2),
                      bgColor.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDestructive
                            ? AppTheme.errorColor
                            : textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 13, color: textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  (onTap != null
                      ? Icon(
                          Icons.chevron_right_rounded,
                          color: textHint,
                          size: 22,
                        )
                      : const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProviderTile(
    BuildContext context,
    WidgetRef ref, {
    required int index,
    required String provider,
    required String displayName,
    required bool isFirst,
    required bool isLast,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? AppTheme.textPrimary
        : AppTheme.lightTextPrimary;
    final textSecondary = isDark
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;
    final isSynced = provider == 'lrclib' || provider == 'textyl';

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryLight,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  if (isSynced)
                    Text(
                      'Supports synced lyrics',
                      style: TextStyle(fontSize: 11, color: textSecondary),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.arrow_upward_rounded,
                color: isFirst
                    ? textSecondary.withValues(alpha: 0.3)
                    : textSecondary,
                size: 20,
              ),
              onPressed: isFirst
                  ? null
                  : () {
                      ref.read(settingsProvider.notifier).moveProviderUp(index);
                    },
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: Icon(
                Icons.arrow_downward_rounded,
                color: isLast
                    ? textSecondary.withValues(alpha: 0.3)
                    : textSecondary,
                size: 20,
              ),
              onPressed: isLast
                  ? null
                  : () {
                      ref
                          .read(settingsProvider.notifier)
                          .moveProviderDown(index);
                    },
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  void _showFontSizeDialog(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.surfaceColor : AppTheme.lightSurface;
    final surfaceLight = isDark
        ? AppTheme.surfaceLight
        : AppTheme.lightSurfaceLight;
    final textPrimary = isDark
        ? AppTheme.textPrimary
        : AppTheme.lightTextPrimary;
    final textHint = isDark ? AppTheme.textHint : AppTheme.lightTextHint;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    surfaceColor.withValues(alpha: 0.9),
                    surfaceLight.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Font Size',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ...AppSettings.fontSizePresets.entries.map((entry) {
                    final isSelected = settings.fontSize == entry.value;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          ref
                              .read(settingsProvider.notifier)
                              .setFontSize(entry.value);
                          Navigator.pop(context);
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            gradient: isSelected
                                ? AppTheme.primaryGradient
                                : null,
                            color: isSelected
                                ? null
                                : surfaceLight.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.radio_button_on_rounded
                                    : Icons.radio_button_off_rounded,
                                color: isSelected ? Colors.white : textHint,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                entry.key,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? Colors.white
                                      : textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showThemeModeDialog(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.surfaceColor : AppTheme.lightSurface;
    final surfaceLight = isDark
        ? AppTheme.surfaceLight
        : AppTheme.lightSurfaceLight;
    final textPrimary = isDark
        ? AppTheme.textPrimary
        : AppTheme.lightTextPrimary;
    final textHint = isDark ? AppTheme.textHint : AppTheme.lightTextHint;

    final themeOptions = [
      (ThemeModeOption.auto, 'System', Icons.brightness_auto_rounded),
      (ThemeModeOption.light, 'Light', Icons.light_mode_rounded),
      (ThemeModeOption.dark, 'Dark', Icons.dark_mode_rounded),
    ];

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    surfaceColor.withValues(alpha: 0.9),
                    surfaceLight.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Theme',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ...themeOptions.map((option) {
                    final isSelected = settings.themeMode == option.$1;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          ref
                              .read(settingsProvider.notifier)
                              .setThemeMode(option.$1);
                          Navigator.pop(context);
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            gradient: isSelected
                                ? AppTheme.primaryGradient
                                : null,
                            color: isSelected
                                ? null
                                : surfaceLight.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                option.$3,
                                color: isSelected ? Colors.white : textHint,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  option.$2,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? Colors.white
                                        : textPrimary,
                                  ),
                                ),
                              ),
                              Icon(
                                isSelected
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                color: isSelected ? Colors.white : textHint,
                                size: 22,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showAccentColorDialog(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.surfaceColor : AppTheme.lightSurface;
    final surfaceLight = isDark
        ? AppTheme.surfaceLight
        : AppTheme.lightSurfaceLight;
    final textPrimary = isDark
        ? AppTheme.textPrimary
        : AppTheme.lightTextPrimary;
    final textHint = isDark ? AppTheme.textHint : AppTheme.lightTextHint;

    final accentOptions = AppSettings.accentColorNames.entries.toList();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    surfaceColor.withValues(alpha: 0.9),
                    surfaceLight.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Accent Color',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ...accentOptions.map((option) {
                    final key = option.key;
                    final label = option.value;
                    final palette = AppTheme.accentPalettes[key];
                    final isSelected = settings.accentColor == key;

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          ref
                              .read(settingsProvider.notifier)
                              .setAccentColor(key);
                          Navigator.pop(context);
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            gradient: isSelected
                                ? AppTheme.primaryGradient
                                : null,
                            color: isSelected
                                ? null
                                : surfaceLight.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color:
                                      palette?.primary ?? AppTheme.primaryColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    width: 1,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? Colors.white
                                        : textPrimary,
                                  ),
                                ),
                              ),
                              Icon(
                                isSelected
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                color: isSelected ? Colors.white : textHint,
                                size: 22,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showResetConfirmation(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppTheme.surfaceColor : AppTheme.lightSurface;
    final surfaceLight = isDark
        ? AppTheme.surfaceLight
        : AppTheme.lightSurfaceLight;
    final textPrimary = isDark
        ? AppTheme.textPrimary
        : AppTheme.lightTextPrimary;
    final textSecondary = isDark
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    surfaceColor.withValues(alpha: 0.9),
                    surfaceLight.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppTheme.errorColor.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.restore_rounded,
                      color: AppTheme.errorColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Reset Settings?',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'This will restore all settings to their default values.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: textSecondary),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: surfaceLight,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            onTap: () => Navigator.pop(context),
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Text(
                                'Cancel',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Material(
                          color: AppTheme.errorColor,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            onTap: () {
                              ref
                                  .read(settingsProvider.notifier)
                                  .resetToDefaults();
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        color: AppTheme.successColor,
                                        size: 20,
                                      ),
                                      SizedBox(width: 12),
                                      Text('Settings reset to defaults'),
                                    ],
                                  ),
                                  backgroundColor: AppTheme.surfaceLight,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Text(
                                'Reset',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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
