import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/track.dart';

const _paths = {
  MusicSource.ytmusic: 'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm-2-12.5v9l6-4.5-6-4.5z',
  MusicSource.youtube: 'M21.58 7.19c-.23-.86-.91-1.54-1.77-1.77C18.25 5 12 5 12 5s-6.25 0-7.81.42c-.86.23-1.54.91-1.77 1.77C2 8.75 2 12 2 12s0 3.25.42 4.81c.23.86.91 1.54 1.77 1.77C5.75 19 12 19 12 19s6.25 0 7.81-.42c.86-.23 1.54-.91 1.77-1.77C22 15.25 22 12 22 12s0-3.25-.42-4.81zM10 15V9l5.2 3L10 15z',
  MusicSource.soundcloud: 'M11.5 14.5c0 .28-.22.5-.5.5s-.5-.22-.5-.5v-4c0-.28.22-.5.5-.5s.5.22.5.5v4zm-2 0c0 .28-.22.5-.5.5s-.5-.22-.5-.5v-3c0-.28.22-.5.5-.5s.5.22.5.5v3zm-2 0c0 .28-.22.5-.5.5s-.5-.22-.5-.5v-2c0-.28.22-.5.5-.5s.5.22.5.5v2zm-2 0c0 .28-.22.5-.5.5s-.5-.22-.5-.5v-1c0-.28.22-.5.5-.5s.5.22.5.5v1zm14.5-.5c0 1.93-1.57 3.5-3.5 3.5H13V9.1c.7-.6 1.6-1.1 2.6-1.1 2.2 0 4.1 1.6 4.4 3.8.3-.2.7-.3 1-.3 1.4 0 2.5 1.1 2.5 2.5z',
};

const sourceNames = {
  MusicSource.ytmusic: 'YouTube Music',
  MusicSource.youtube: 'YouTube',
  MusicSource.soundcloud: 'SoundCloud',
};

Color sourceColor(MusicSource s) => s == MusicSource.soundcloud ? const Color(0xFFFF7A1A) : const Color(0xFFFF4040);

class PlatformIcon extends StatelessWidget {
  const PlatformIcon(this.source, {super.key, this.size = 14, this.color});
  final MusicSource source;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final hex = (color ?? sourceColor(source)).toARGB32().toRadixString(16).padLeft(8, '0').substring(2);
    return Semantics(
      label: sourceNames[source],
      child: SvgPicture.string(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#$hex" d="${_paths[source]}"/></svg>',
        width: size,
        height: size,
      ),
    );
  }
}
