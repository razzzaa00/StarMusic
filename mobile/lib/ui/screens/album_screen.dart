import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../services/albums.dart';
import '../../services/stream_resolver.dart' show normalize;
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/track_actions.dart';

class AlbumScreen extends StatefulWidget {
  const AlbumScreen({super.key, required this.album});
  final Album album;

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  List<AlbumTrack>? _songs;
  final Map<int, Track?> _playable = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = AppScope.of(context);
    final songs = await app.albums.tracks(widget.album).catchError((_) => <AlbumTrack>[]);
    if (!mounted) return;
    setState(() => _songs = songs);
    var next = 0;
    Future<void> worker() async {
      while (next < songs.length && mounted) {
        final i = next++;
        final t = await _match(songs[i]);
        if (mounted) setState(() => _playable[i] = t);
      }
    }

    await Future.wait(List.generate(4, (_) => worker()));
  }

  /// Finds a playable version of an album song, preferring YouTube Music, then YouTube, then SoundCloud.
  Future<Track?> _match(AlbumTrack song) async {
    final app = AppScope.of(context);
    final q = '${song.artist} ${song.title}';
    final want = normalize(song.title);
    for (final source in [MusicSource.ytmusic, MusicSource.youtube, MusicSource.soundcloud]) {
      final results = await app.search.searchOne(source, q).catchError((_) => <Track>[]);
      for (final t in results.take(5)) {
        final title = normalize(t.title);
        final closeLength = song.duration == Duration.zero || t.duration == Duration.zero || (t.duration - song.duration).inSeconds.abs() <= 15;
        if (title.contains(want) && closeLength) {
          return Track(
            id: t.id,
            title: song.title,
            artist: song.artist,
            album: widget.album.title,
            duration: t.duration,
            thumbnail: widget.album.artwork.isEmpty ? t.thumbnail : widget.album.artwork,
            url: t.url,
            source: t.source,
          );
        }
      }
    }
    return null;
  }

  List<Track> get _queue => [for (var i = 0; i < (_songs?.length ?? 0); i++) if (_playable[i] != null) _playable[i]!];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final a = widget.album;
    final songs = _songs;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        children: [
          Center(child: Artwork(a.artwork, size: 220, radius: 10)),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(children: [
              Text(a.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              GestureDetector(onTap: () => searchFor(context, a.artist), child: Text(a.artist, style: const TextStyle(color: StarColors.accent, fontSize: 15))),
              const SizedBox(height: 4),
              Text([if (a.year.isNotEmpty) 'Album · ${a.year}', if (songs != null) titles(songs.length)].join(' · '), style: const TextStyle(color: StarColors.textDim)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _queue.isEmpty ? null : () => app.player.playQueue(_queue, 0),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Lire l\'album'),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          if (songs == null) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          if (songs != null && songs.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Morceaux indisponibles', style: TextStyle(color: StarColors.textDim)))),
          for (var i = 0; i < (songs?.length ?? 0); i++)
            ListTile(
              leading: SizedBox(width: 24, child: Text('${songs![i].number}', textAlign: TextAlign.center, style: const TextStyle(color: StarColors.textDim))),
              title: Text(songs[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: songs[i].artist != a.artist ? Text(songs[i].artist, style: const TextStyle(color: StarColors.textDim)) : null,
              trailing: !_playable.containsKey(i)
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : _playable[i] == null
                      ? const Icon(Icons.block_rounded, size: 18, color: StarColors.textDim)
                      : Text(formatDuration(songs[i].duration), style: const TextStyle(color: StarColors.textDim, fontSize: 12)),
              onTap: _playable[i] == null
                  ? null
                  : () {
                      final q = _queue;
                      app.player.playQueue(q, q.indexOf(_playable[i]!));
                    },
              onLongPress: _playable[i] == null ? null : () => showTrackMenu(context, _playable[i]!),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
