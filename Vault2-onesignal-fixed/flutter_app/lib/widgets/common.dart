import 'dart:io';

import 'package:flutter/material.dart';

import '../models/doc_category.dart';
import '../models/doc_item.dart';
import '../utils/formatters.dart';
import '../utils/masking.dart';
import 'brand.dart';

/// Staggered fade+slide entry used across lists.
class AnimatedEntry extends StatelessWidget {
  const AnimatedEntry({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + (index.clamp(0, 8) * 45)),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}

class CategoryCard extends StatelessWidget {
  const CategoryCard({
    super.key,
    required this.category,
    required this.count,
    required this.onTap,
    this.onLongPress,
  });

  final DocCategory category;
  final int count;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CategoryEmblem(
                categoryId: category.id,
                fallbackColor: category.colorValue,
                size: 48,
              ),
              const SizedBox(height: 14),
              Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 2),
              Text(
                count == 1 ? '1 document' : '$count documents',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DocumentTile extends StatelessWidget {
  const DocumentTile({
    super.key,
    required this.doc,
    required this.onTap,
    this.masked = true,
  });

  final DocItem doc;
  final bool masked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = daysUntil(doc.expiryDate);
    final warn = days != null && days <= 30;
    final number = doc.documentNumber.isEmpty
        ? null
        : (masked
            ? Masking.forCategory(doc.categoryId, doc.documentNumber)
            : doc.documentNumber);

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _Thumb(doc: doc),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15.5),
                    ),
                    if (number != null) ...[
                      const SizedBox(height: 3),
                      Text(number,
                          style: TextStyle(
                              fontFeatures: const [],
                              letterSpacing: 0.6,
                              color: scheme.onSurfaceVariant,
                              fontSize: 13)),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          warn ? Icons.warning_amber_rounded : Icons.event_available,
                          size: 14,
                          color: warn ? scheme.error : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          expiryLabel(doc.expiryDate),
                          style: TextStyle(
                            fontSize: 12,
                            color: warn ? scheme.error : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (doc.favorite)
                Icon(Icons.star_rounded, size: 20, color: scheme.tertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.doc});
  final DocItem doc;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = doc.primaryPath;
    final showImage = path != null && !doc.isPdf && File(path).existsSync();

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 58,
        width: 58,
        child: showImage
            ? Image.file(File(path), fit: BoxFit.cover)
            : (doc.isPdf
                ? Container(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(Icons.picture_as_pdf_rounded,
                        color: scheme.onSurfaceVariant),
                  )
                : CategoryEmblem(categoryId: doc.categoryId, size: 58)),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.subtitle, this.icon});
  final String title;
  final String subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? Icons.folder_open_rounded,
                size: 46, color: scheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5)),
          ],
        ),
      ),
    );
  }
}
