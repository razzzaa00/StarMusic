import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../state/library.dart';
import '../app_scope.dart';
import '../theme.dart';
import 'artwork.dart';
import 'platform_icon.dart';
import 'track_actions.dart';

class TrackTile extends StatelessWidget {
  const TrackTile({super.key, required this.track, required this.onTap, this.playlist, this.showArtwork = true});
  final Track track;
  final VoidCallback onTap;
  final Playlist? playlist;
  final bool showArtwork;

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final isCurrent = player.current == track;
        final dim = const TextStyle(color: StarColors.textDim, fontSize: 13);
        final link = dim.copyWith(decoration: TextDecoration.none);
        final artists = track.artists.isEmpty ? [track.artist] : track.artists;
        return InkWell(
          onTap: onTap,
          onLongPress: () => showTrackMenu(context, track, playlist: playlist),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                if (showArtwork) ...[Artwork(track.thumbnail), const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        PlatformIcon(track.source),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: isCurrent ? StarColors.accent : StarColors.text),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 3),
                      Text.rich(
                        TextSpan(children: [
                          for (var i = 0; i < artists.length; i++) ...[
                            if (i > 0) TextSpan(text: ', ', style: dim),
                            TextSpan(text: artists[i], style: link, recognizer: TapGestureRecognizer()..onTap = () => searchFor(context, artists[i])),
                          ],
                          if (track.album.isNotEmpty) ...[
                            TextSpan(text: '  ·  ', style: dim),
                            TextSpan(text: track.album, style: link, recognizer: TapGestureRecognizer()..onTap = () => openAlbumOf(context, track)),
                          ],
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(formatDuration(track.duration), style: dim.copyWith(fontSize: 12)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.more_horiz_rounded, color: StarColors.textDim),
                  onPressed: () => showTrackMenu(context, track, playlist: playlist),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
