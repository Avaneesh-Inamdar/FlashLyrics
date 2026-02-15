import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/lyrics_model.dart';
import '../providers/providers.dart';
import '../providers/settings_provider.dart';

/// Advanced dialog for searching lyrics across all APIs
class MultiApiSearchDialog extends ConsumerStatefulWidget {
  const MultiApiSearchDialog({super.key});

  @override
  ConsumerState<MultiApiSearchDialog> createState() =>
      _MultiApiSearchDialogState();
}

class _MultiApiSearchDialogState extends ConsumerState<MultiApiSearchDialog> {
  final _artistController = TextEditingController();
  final _titleController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSearching = false;
  Map<String, LyricsModel?>? _searchResults;

  @override
  void dispose() {
    _artistController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child:
          ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    constraints: const BoxConstraints(
                      maxWidth: 450,
                      maxHeight: 600,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          surfaceColor.withValues(alpha: 0.95),
                          surfaceLight.withValues(alpha: 0.9),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: AppTheme.primaryColor.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildHeader(textPrimary, textSecondary),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildTextField(
                                    controller: _artistController,
                                    label: 'Artist',
                                    hint: 'Enter artist name',
                                    icon: Icons.person_rounded,
                                    textHint: textHint,
                                    textPrimary: textPrimary,
                                    textSecondary: textSecondary,
                                    surfaceLight: surfaceLight,
                                  ),
                                  const SizedBox(height: 16),
                                  _buildTextField(
                                    controller: _titleController,
                                    label: 'Song Title',
                                    hint: 'Enter song title',
                                    icon: Icons.music_note_rounded,
                                    textHint: textHint,
                                    textPrimary: textPrimary,
                                    textSecondary: textSecondary,
                                    surfaceLight: surfaceLight,
                                    onSubmitted: (_) => _searchAllApis(),
                                  ),
                                  const SizedBox(height: 20),
                                  _buildSearchButton(
                                    surfaceLight,
                                    textSecondary,
                                  ),
                                  if (_searchResults != null) ...[
                                    const SizedBox(height: 24),
                                    _buildResultsSection(
                                      textPrimary,
                                      textSecondary,
                                      textHint,
                                      surfaceLight,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .animate()
              .fadeIn(duration: 200.ms)
              .scale(begin: const Offset(0.95, 0.95)),
    );
  }

  Widget _buildHeader(Color textPrimary, Color textSecondary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor.withValues(alpha: 0.15),
            AppTheme.primaryColor.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.travel_explore_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Search All APIs',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Search across all lyrics providers',
            style: TextStyle(fontSize: 14, color: textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color textHint,
    required Color textPrimary,
    required Color textSecondary,
    required Color surfaceLight,
    Function(String)? onSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: textHint, size: 22),
        filled: true,
        fillColor: surfaceLight.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: surfaceLight, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.errorColor, width: 1.5),
        ),
        labelStyle: TextStyle(color: textSecondary),
        hintStyle: TextStyle(color: textHint),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
      ),
      style: TextStyle(color: textPrimary, fontSize: 16),
      validator: (value) {
        if (value == null || value.isEmpty) return 'Required';
        return null;
      },
      textInputAction: onSubmitted != null
          ? TextInputAction.search
          : TextInputAction.next,
      onFieldSubmitted: onSubmitted,
    );
  }

  Widget _buildSearchButton(Color surfaceLight, Color textSecondary) {
    return Container(
      decoration: BoxDecoration(
        gradient: _isSearching ? null : AppTheme.primaryGradient,
        color: _isSearching ? surfaceLight : null,
        borderRadius: BorderRadius.circular(14),
        boxShadow: _isSearching
            ? null
            : [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isSearching ? null : _searchAllApis,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: _isSearching
                ? Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(textSecondary),
                      ),
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_rounded, color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Search All Providers',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsSection(
    Color textPrimary,
    Color textSecondary,
    Color textHint,
    Color surfaceLight,
  ) {
    final results = _searchResults!;
    final hasResults = results.values.any((r) => r != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.playlist_add_check_rounded,
              color: AppTheme.primaryLight,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Results',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (!hasResults)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: surfaceLight.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.sentiment_dissatisfied_rounded,
                  color: textHint,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No lyrics found from any provider',
                    style: TextStyle(color: textSecondary, fontSize: 14),
                  ),
                ),
              ],
            ),
          )
        else
          ...results.entries.map((entry) {
            final provider = entry.key;
            final lyrics = entry.value;
            final displayName = AppSettings.providerNames[provider] ?? provider;

            return _buildResultCard(
              provider: provider,
              displayName: displayName,
              lyrics: lyrics,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
              textHint: textHint,
              surfaceLight: surfaceLight,
            );
          }),
      ],
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildResultCard({
    required String provider,
    required String displayName,
    required LyricsModel? lyrics,
    required Color textPrimary,
    required Color textSecondary,
    required Color textHint,
    required Color surfaceLight,
  }) {
    final hasLyrics = lyrics != null && lyrics.plainLyrics.isNotEmpty;
    final hasSynced = lyrics?.isSynced ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: surfaceLight.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasLyrics
              ? AppTheme.successColor.withValues(alpha: 0.3)
              : surfaceLight,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: hasLyrics ? () => _selectLyrics(lyrics) : null,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: hasLyrics
                        ? AppTheme.successColor.withValues(alpha: 0.15)
                        : surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    hasLyrics
                        ? Icons.check_circle_rounded
                        : Icons.close_rounded,
                    color: hasLyrics ? AppTheme.successColor : textHint,
                    size: 20,
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
                      const SizedBox(height: 2),
                      Text(
                        hasLyrics
                            ? hasSynced
                                  ? 'Synced lyrics available'
                                  : 'Plain lyrics available'
                            : 'Not found',
                        style: TextStyle(
                          fontSize: 12,
                          color: hasLyrics ? AppTheme.successColor : textHint,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasLyrics)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Use',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _searchAllApis() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSearching = true;
      _searchResults = null;
    });

    try {
      final datasource = ref.read(lyricsRemoteDataSourceProvider);
      final results = await datasource.searchAllProviders(
        _artistController.text.trim(),
        _titleController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search failed: ${e.toString()}'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  void _selectLyrics(LyricsModel lyrics) {
    // Return the selected lyrics to the caller
    Navigator.pop(context, lyrics);
  }
}
