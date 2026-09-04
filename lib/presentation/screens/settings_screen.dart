import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../services/media_detection_service.dart';
import '../providers/settings_provider.dart';
import '../providers/media_provider.dart';
import '../providers/providers.dart';
import 'licenses_screen.dart';

/// Settings screen with modern glassmorphism UI
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final hasPermission = ref.watch(hasNotificationAccessProvider);
    final hasOverlayPermission = ref.watch(hasOverlayPermissionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: false,
      backgroundColor: isDark ? AppTheme.backgroundColor : AppTheme.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.backgroundColor : AppTheme.lightBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Settings',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : AppTheme.lightTextPrimary,
          ),
        ),
      ),
      body: Container(
        color: isDark ? AppTheme.backgroundColor : AppTheme.lightBackground,
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
                    child: Column(
                      children: [
                        _buildPermissionTile(context, hasPermission),
                        _buildDivider(context),
                        _buildOverlayPermissionTile(context, hasOverlayPermission),
                      ],
                    ),
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
                        _buildDivider(context),
                        _buildSwitchTile(
                          context,
                          icon: Icons.picture_in_picture_alt_rounded,
                          title: 'Floating Lyrics',
                          subtitle: 'Show lyrics over other apps (needs overlay permission)',
                          value: settings.floatingLyricsEnabled,
                          onChanged: (value) async {
                            if (value) {
                              final hasOverlay = await MediaDetectionService.checkOverlayPermission();
                              if (!hasOverlay) {
                                if (context.mounted) {
                                  final ok = await _showOverlayRationale(context);
                                  if (!ok) return;
                                }
                                await MediaDetectionService.requestOverlayPermission();
                                // re-check after returning
                                await Future.delayed(const Duration(seconds: 1));
                                final nowHas = await MediaDetectionService.checkOverlayPermission();
                                if (!nowHas) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Overlay permission is required for floating lyrics')));
                                  }
                                  return;
                                }
                                ref.invalidate(hasOverlayPermissionProvider);
                              }
                            }
                            ref.read(settingsProvider.notifier).setFloatingLyricsEnabled(value);
                            if (value && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Floating lyrics enabled. Use the button on Home to show overlay.')));
                            }
                          },
                        ),
                        _buildDivider(context),
                        _buildSwitchTile(
                          context,
                          icon: Icons.touch_app_rounded,
                          title: 'Overlay Tap-to-Seek',
                          subtitle: settings.floatingLyricsEnabled
                              ? 'Tap a line in floating window to seek • also enables scrolling'
                              : 'Enable Floating Lyrics first',
                          value: settings.floatingOverlaySeekEnabled,
                          onChanged: settings.floatingLyricsEnabled
                              ? (value) {
                                  ref.read(settingsProvider.notifier).setFloatingOverlaySeekEnabled(value);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value ? 'Tap-to-seek + scrolling enabled in overlay' : 'Overlay tap-to-seek disabled')));
                                  }
                                }
                              : null,
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
                        _buildDivider(context),
                        _buildTapTile(
                          context,
                          icon: Icons.timer_outlined,
                          title: 'Lyrics Sync Offset',
                          subtitle: _getSyncOffsetLabel(
                            settings.lyricsSyncOffset,
                          ),
                          onTap: () =>
                              _showSyncOffsetDialog(context, ref, settings),
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
                title: 'STORAGE',
                delay: 280,
                children: [
                  _buildGlassCard(
                    context,
                    child: _buildStorageSection(context, ref),
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
                    child: Consumer(
                      builder: (context, ref, _) {
                        final isListening = ref.watch(mediaNotifierProvider.select((s) => s.isListening));
                        return _buildStatusTile(context, isListening);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildSection(
                context,
                title: 'SUPPORT & ADS',
                delay: 350,
                children: [
                  _buildGlassCard(
                    context,
                    child: Column(
                      children: [
                        _buildBuyMeACoffeeTile(context),
                        _buildDivider(context),
                        _buildSwitchTile(
                          context,
                          icon: Icons.ad_units_rounded,
                          title: 'Show Ads',
                          subtitle: 'Display banner ads to support development',
                          value: settings.enableAds,
                          onChanged: (value) {
                            ref
                                .read(settingsProvider.notifier)
                                .setEnableAds(value);
                          },
                        ),
                        if (settings.enableAds) ...[
                          _buildDivider(context),
                          _buildSwitchTile(
                            context,
                            icon: Icons.developer_mode_rounded,
                            title: 'Sample Test Ads',
                            subtitle:
                                'Display Google test banner (recommended until AdMob account is approved)',
                            value: settings.useTestAds,
                            onChanged: (value) {
                              ref
                                  .read(settingsProvider.notifier)
                                  .setUseTestAds(value);
                            },
                          ),
                        ],
                      ],
                    ),
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
                          subtitle: 'v${AppConstants.appVersion}',
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

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: surfaceLight, width: 1),
      ),
      child: child,
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

  Widget _buildOverlayPermissionTile(
    BuildContext context,
    AsyncValue<bool> hasPermission,
  ) {
    return hasPermission.when(
      data: (granted) => _buildTapTile(
        context,
        icon: Icons.picture_in_picture_alt_rounded,
        title: 'Display over other apps',
        subtitle: granted ? 'Granted — floating lyrics enabled' : 'Required for floating lyrics overlay',
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: (granted ? AppTheme.successColor : Colors.orange).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: (granted ? AppTheme.successColor : Colors.orange).withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(granted ? Icons.check_circle_rounded : Icons.warning_rounded, size: 16, color: granted ? AppTheme.successColor : Colors.orange),
              const SizedBox(width: 6),
              Text(granted ? 'Active' : 'Grant', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: granted ? AppTheme.successColor : Colors.orange)),
            ],
          ),
        ),
        onTap: () async {
          await MediaDetectionService.requestOverlayPermission();
        },
      ),
      loading: () => _buildTapTile(
        context,
        icon: Icons.layers_rounded,
        title: 'Floating overlay',
        subtitle: 'Checking...',
        trailing: const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => _buildTapTile(
        context,
        icon: Icons.layers_rounded,
        title: 'Floating overlay',
        subtitle: 'Error checking status',
        trailing: const Icon(Icons.error_rounded, color: AppTheme.errorColor),
      ),
    );
  }

  Future<bool> _showOverlayRationale(BuildContext context) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Allow overlay?'),
        content: const Text('FlashLyrics needs "Display over other apps" to show lyrics in a floating window while you use Spotify, YouTube Music, etc. You will be taken to system settings.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Allow')),
        ],
      ),
    );
    return res == true;
  }

  Widget _buildBuyMeACoffeeTile(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const bmcYellow = Color(0xFFFFDD00);
    const bmcBlack = Color(0xFF000000);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          final uri = Uri.parse('https://buymeacoffee.com/avaneeshinamdar');
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (e) {
            debugPrint('Could not launch BuyMeACoffee: $e');
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: bmcYellow,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: bmcYellow.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.coffee_rounded,
                  color: bmcBlack,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Buy Me a Coffee',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Support development & future features',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: bmcYellow.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: bmcYellow.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Support',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark ? bmcYellow : const Color(0xFFB8860B),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 13,
                      color: isDark ? bmcYellow : const Color(0xFFB8860B),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }



  Widget _buildStatusTile(BuildContext context, bool isActive) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? AppTheme.textPrimary
        : AppTheme.lightTextPrimary;
    final textSecondary = isDark
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;
    final textHint = isDark ? AppTheme.textHint : AppTheme.lightTextHint;

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

  Widget _buildStorageSection(BuildContext context, WidgetRef ref) {
    final local = ref.watch(lyricsLocalDataSourceProvider);
    final cachedAsync = ref.watch(cachedLyricsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final textHint = isDark ? AppTheme.textHint : AppTheme.lightTextHint;

    final count = local.getCacheCount();
    final size = local.getCacheSizeFormatted();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppTheme.primaryColor.withValues(alpha: 0.2), AppTheme.primaryColor.withValues(alpha: 0.1)]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.storage_rounded, color: AppTheme.primaryLight, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cached Lyrics', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary)),
                    Text('$count songs • $size', style: TextStyle(fontSize: 13, color: textSecondary)),
                  ],
                ),
              ),
              cachedAsync.maybeWhen(
                data: (list) => Text('${list.length}', style: TextStyle(color: textHint, fontWeight: FontWeight.w600)),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                  label: const Text('Clear Cache'),
                  style: OutlinedButton.styleFrom(foregroundColor: count == 0 ? textHint : AppTheme.errorColor),
                  onPressed: count == 0
                      ? null
                      : () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Clear cached lyrics?'),
                              content: Text('Delete all $count cached songs ($size)? This cannot be undone.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                FilledButton(
                                  style: FilledButton.styleFrom(backgroundColor: AppTheme.errorColor),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Clear All'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true) return;
                          await local.clearAllCache();
                          ref.invalidate(cachedLyricsProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cache cleared')));
                          }
                        },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Refresh'),
                  onPressed: () => ref.invalidate(cachedLyricsProvider),
                ),
              ),
            ],
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
    required ValueChanged<bool>? onChanged,
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
                                  content: Row(
                                    children: [
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        color: AppTheme.successColor,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Settings reset to defaults',
                                        style: TextStyle(color: textPrimary),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: isDark
                                      ? AppTheme.surfaceLight
                                      : AppTheme.lightSurfaceLight,
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

  String _getSyncOffsetLabel(int offset) {
    if (offset == 0) return 'Default';
    final seconds = offset ~/ 1000;
    final ms = offset % 1000;
    if (offset > 0) {
      return '+${seconds}s ${ms}ms';
    }
    return '${seconds}s ${ms}ms';
  }

  void _showSyncOffsetDialog(
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
    final textSecondary = isDark
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;
    final textHint = isDark ? AppTheme.textHint : AppTheme.lightTextHint;

    int selectedOffset = settings.lyricsSyncOffset;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
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
                    Icon(
                      Icons.timer_outlined,
                      color: AppTheme.primaryLight,
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Lyrics Sync Offset',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Adjust if lyrics appear too early or late',
                      style: TextStyle(fontSize: 13, color: textSecondary),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _getSyncOffsetLabel(selectedOffset),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryLight,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            setState(() => selectedOffset -= 100);
                          },
                          icon: Icon(
                            Icons.remove_circle_outline,
                            color: textSecondary,
                          ),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: AppTheme.primaryColor,
                              inactiveTrackColor: surfaceLight,
                              thumbColor: AppTheme.primaryLight,
                            ),
                            child: Slider(
                              value: selectedOffset.toDouble(),
                              min: -3000,
                              max: 3000,
                              divisions: 60,
                              onChanged: (value) {
                                setState(() => selectedOffset = value.round());
                              },
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() => selectedOffset += 100);
                          },
                          icon: Icon(
                            Icons.add_circle_outline,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Cancel',
                              style: TextStyle(color: textSecondary),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              ref
                                  .read(settingsProvider.notifier)
                                  .setLyricsSyncOffset(selectedOffset);
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Apply'),
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
      ),
    );
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? AppTheme.textPrimary
        : AppTheme.lightTextPrimary;
    final textSecondary = isDark
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;

    // Show loading dialog
    bool dialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceColor : AppTheme.lightSurface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Checking for updates...',
                style: TextStyle(color: textPrimary),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final response = await http
          .get(
            Uri.parse(
              'https://api.github.com/repos/Avaneesh-Inamdar/FlashLyrics/releases/latest',
            ),
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(const Duration(seconds: 10));

      if (!context.mounted) return;
      Navigator.pop(context); // Close loading dialog
      dialogOpen = false;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latestVersion =
            (data['tag_name'] as String?)?.replaceFirst('v', '') ?? 'Unknown';
        final releaseUrl =
            data['html_url'] as String? ??
            'https://github.com/Avaneesh-Inamdar/FlashLyrics/releases';
        final releaseNotes = data['body'] as String? ?? '';

        final currentVersion = AppConstants.appVersion;
        final isUpdateAvailable =
            _compareVersions(latestVersion, currentVersion) > 0;

        if (isUpdateAvailable) {
          _showUpdateAvailableDialog(
            context,
            latestVersion,
            releaseUrl,
            releaseNotes,
            isDark,
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.successColor,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text('You\'re on the latest version ($currentVersion)'),
                ],
              ),
              backgroundColor: isDark
                  ? AppTheme.surfaceLight
                  : AppTheme.lightSurfaceLight,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      } else {
        throw Exception('Failed to check for updates');
      }
    } catch (e) {
      if (!context.mounted) return;
      if (dialogOpen) {
        Navigator.pop(context); // Close loading dialog if still showing
        dialogOpen = false;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.error_outline,
                color: AppTheme.errorColor,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('Failed to check for updates: $e')),
            ],
          ),
          backgroundColor: isDark
              ? AppTheme.surfaceLight
              : AppTheme.lightSurfaceLight,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  /// Normalize a version string to always have 3 parts (major.minor.patch).
  /// Handles formats like '1.01' (-> '1.0.1'), '1.0.1', 'v1.01', etc.
  List<int> _normalizeVersion(String version) {
    // Strip leading 'v' if present
    final cleaned = version
        .replaceFirst(RegExp(r'^v', caseSensitive: false), '')
        .trim();
    final parts = cleaned.split('.');

    if (parts.length >= 3) {
      // Already has 3+ parts, parse directly
      return List.generate(
        3,
        (i) => i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0,
      );
    }

    if (parts.length == 2) {
      final major = int.tryParse(parts[0]) ?? 0;
      final rest = parts[1];
      // If second part has leading zero and length > 1 (e.g. '01'), treat as minor.patch
      if (rest.length >= 2 && rest.startsWith('0')) {
        // '1.01' -> major=1, minor=0, patch=1
        final minor = int.tryParse(rest.substring(0, 1)) ?? 0;
        final patch = int.tryParse(rest.substring(1)) ?? 0;
        return [major, minor, patch];
      }
      // Normal 2-part version like '1.2'
      final minor = int.tryParse(rest) ?? 0;
      return [major, minor, 0];
    }

    // Single number
    return [int.tryParse(cleaned) ?? 0, 0, 0];
  }

  int _compareVersions(String v1, String v2) {
    final parts1 = _normalizeVersion(v1);
    final parts2 = _normalizeVersion(v2);

    for (var i = 0; i < 3; i++) {
      if (parts1[i] > parts2[i]) return 1;
      if (parts1[i] < parts2[i]) return -1;
    }
    return 0;
  }

  void _showUpdateAvailableDialog(
    BuildContext context,
    String latestVersion,
    String releaseUrl,
    String releaseNotes,
    bool isDark,
  ) {
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
                  color: AppTheme.successColor.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      color: AppTheme.successColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Update Available!',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Version $latestVersion is available',
                    style: TextStyle(fontSize: 14, color: textSecondary),
                  ),
                  if (releaseNotes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 150),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: surfaceLight.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          releaseNotes,
                          style: TextStyle(
                            fontSize: 12,
                            color: textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Later',
                            style: TextStyle(color: textSecondary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final uri = Uri.parse(releaseUrl);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                            if (context.mounted) Navigator.pop(context);
                          },
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('Download'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.successColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
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
