import 'package:flutter/material.dart';
import '../models/drama_models.dart';
import '../theme/app_theme.dart';

class DramaCard extends StatelessWidget {
  final DramaItem drama;
  final VoidCallback onTap;

  const DramaCard({
    super.key,
    required this.drama,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppTheme.cardBorder,
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poster Image
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  drama.coverUrl.isNotEmpty
                      ? Image.network(
                          drama.coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildPlaceholder(),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              color: AppTheme.bgElevated,
                              child: const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.cyanAccent,
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                      : _buildPlaceholder(),

                  // Bottom subtle gradient
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.85),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),

                  // Episode count badge
                  if (drama.episodeCount > 0)
                    Positioned(
                      top: 5,
                      right: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: AppTheme.cyanAccent.withOpacity(0.6),
                            width: 0.6,
                          ),
                        ),
                        child: Text(
                          '${drama.episodeCount} ភាគ',
                          style: const TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.cyanAccent,
                          ),
                        ),
                      ),
                    ),

                  // Quality Tag (No website name shown on card)
                  Positioned(
                    top: 5,
                    left: 5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Full HD',
                        style: TextStyle(
                          fontSize: 7.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.cyanAccent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Title & Info
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    drama.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Builder(
                    builder: (context) {
                      final cleanTags = drama.tags.where((t) {
                        final lower = t.toLowerCase();
                        return !lower.contains('8movie') &&
                            !lower.contains('reelsdizim') &&
                            !lower.contains('mydrama') &&
                            !lower.contains('bmp4') &&
                            !lower.contains('beeplaylet');
                      }).toList();

                      if (cleanTags.isNotEmpty) {
                        return Text(
                          cleanTags.take(2).join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9,
                            color: AppTheme.textSecondary,
                          ),
                        );
                      }
                      return const Text(
                        'ចុចដើម្បីទាញយក',
                        style: TextStyle(
                          fontSize: 9,
                          color: AppTheme.cyanAccent,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppTheme.bgElevated,
      child: Center(
        child: Text(
          drama.platform.emojiFallback,
          style: const TextStyle(fontSize: 38),
        ),
      ),
    );
  }
}
