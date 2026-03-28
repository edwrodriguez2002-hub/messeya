import 'dart:io';

import 'package:flutter/material.dart';

class FullscreenImagePage extends StatelessWidget {
  const FullscreenImagePage({
    super.key,
    this.imageUrl,
    this.imageFile,
    this.heroTag,
    this.caption = '',
  });

  final String? imageUrl;
  final File? imageFile;
  final String? heroTag;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final image = imageFile != null
        ? Image.file(
            imageFile!,
            fit: BoxFit.contain,
          )
        : Image.network(
            imageUrl ?? '',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(
                Icons.broken_image_outlined,
                size: 72,
                color: Colors.white70,
              ),
            ),
          );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.5,
              child: heroTag == null
                  ? image
                  : Hero(
                      tag: heroTag!,
                      child: image,
                    ),
            ),
          ),
          if (caption.trim().isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Text(
                    caption,
                    style: const TextStyle(
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
