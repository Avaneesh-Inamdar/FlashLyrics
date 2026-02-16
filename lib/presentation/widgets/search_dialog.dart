import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_theme.dart';
import '../providers/lyrics_provider.dart';

/// Beautiful dialog for manual lyrics search
class SearchDialog extends ConsumerStatefulWidget {
  const SearchDialog({super.key});

  @override
  ConsumerState<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends ConsumerState<SearchDialog> {
  final _artistController = TextEditingController();
  final _titleController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

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
      child:
          ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 400),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          surfaceColor.withValues(alpha: 0.9),
                          surfaceLight.withValues(alpha: 0.8),
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
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildHeader(textPrimary, textSecondary),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                            child: Column(
                              children: [
                                _buildTextField(
                                  controller: _artistController,
                                  label: 'Artist',
                                  hint: 'Enter artist name',
                                  icon: Icons.person_rounded,
                                  delay: 100,
                                  surfaceLight: surfaceLight,
                                  textPrimary: textPrimary,
                                  textSecondary: textSecondary,
                                  textHint: textHint,
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  controller: _titleController,
                                  label: 'Song Title',
                                  hint: 'Enter song title',
                                  icon: Icons.music_note_rounded,
                                  delay: 200,
                                  onSubmitted: (_) => _search(),
                                  surfaceLight: surfaceLight,
                                  textPrimary: textPrimary,
                                  textSecondary: textSecondary,
                                  textHint: textHint,
                                ),
                                const SizedBox(height: 28),
                                _buildActions(),
                              ],
                            ),
                          ),
                        ],
                      ),
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
              Icons.search_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Search Lyrics',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Find lyrics by artist and song title',
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
    required int delay,
    required Color surfaceLight,
    required Color textPrimary,
    required Color textSecondary,
    required Color textHint,
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
              borderSide: BorderSide(color: AppTheme.primaryColor, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: AppTheme.errorColor,
                width: 1.5,
              ),
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
            if (value == null || value.isEmpty) {
              return 'This field is required';
            }
            return null;
          },
          textInputAction: onSubmitted != null
              ? TextInputAction.search
              : TextInputAction.next,
          onFieldSubmitted: onSubmitted,
        )
        .animate()
        .fadeIn(delay: Duration(milliseconds: delay))
        .slideX(begin: 0.05, end: 0);
  }

  Widget _buildActions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceLight = isDark
        ? AppTheme.surfaceLight
        : AppTheme.lightSurfaceLight;
    final textSecondary = isDark
        ? AppTheme.textSecondary
        : AppTheme.lightTextSecondary;
    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: surfaceLight.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isLoading ? null : () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'Cancel',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Container(
            decoration: BoxDecoration(
              gradient: _isLoading ? null : AppTheme.primaryGradient,
              color: _isLoading ? surfaceLight : null,
              borderRadius: BorderRadius.circular(14),
              boxShadow: _isLoading
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
                onTap: _isLoading ? null : _search,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: _isLoading
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
                            Icon(
                              Icons.search_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Search',
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
          ),
        ),
      ],
    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1, end: 0);
  }

  Future<void> _search() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await ref
          .read(lyricsNotifierProvider.notifier)
          .searchLyrics(
            _artistController.text.trim(),
            _titleController.text.trim(),
          );

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: AppTheme.errorColor,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('Error: ${e.toString()}')),
              ],
            ),
            backgroundColor: AppTheme.surfaceLight,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
