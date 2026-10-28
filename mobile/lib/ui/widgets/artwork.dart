import 'package:flutter/material.dart';

import '../theme.dart';

class Artwork extends StatelessWidget {
  const Artwork(this.url, {super.key, this.size = 48, this.radius = 6});
  final String url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: StarColors.surfaceHigh,
      child: Icon(Icons.music_note_rounded, size: size * 0.4, color: StarColors.textDim),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? placeholder
          : Image.network(url, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => placeholder),
    );
  }
}

String formatDuration(Duration d) {
  if (d <= Duration.zero) return '';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

String titles(int n) => n == 1 ? '1 titre' : '$n titres';
