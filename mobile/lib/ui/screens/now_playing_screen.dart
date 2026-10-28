import 'package:flutter/material.dart';

import '../../services/lyrics.dart';
import '../../state/player.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/platform_icon.dart';
import '../widgets/track_actions.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  bool _showLyrics = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final player = app.player;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(tooltip: 'Paroles', icon: Icon(Icons.lyrics_outlined, color: _showLyrics ? StarColors.accent : null), onPressed: () => setState(() => _showLyrics = !_showLyrics)),
          IconButton(tooltip: 'File d\'attente', icon: const Icon(Icons.queue_music_rounded), onPressed: () => _showQueue(context, player)),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([player, app.library]),
          builder: (context, _) {
            final t = player.current;
            if (t == null) return const Center(child: Text('Rien en lecture', style: TextStyle(color: StarColors.textDim)));
            final fav = app.library.isFavorite(t);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(children: [
                Expanded(
                  child: _showLyrics
                      ? _LyricsView(key: ValueKey(t.key), load: () => app.lyrics.fetch(t), player: player)
                      : Center(child: LayoutBuilder(builder: (_, c) => Artwork(t.thumbnail, size: c.maxWidth.clamp(0, c.maxHeight), radius: 12))),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        for (final a in (t.artists.isEmpty ? [t.artist] : t.artists))
                          GestureDetector(onTap: () => searchFor(context, a), child: Text(a, style: const TextStyle(color: StarColors.textDim, fontSize: 15))),
                        if (t.album.isNotEmpty)
                          GestureDetector(onTap: () => openAlbumOf(context, t), child: Text('·  ${t.album}', style: const TextStyle(color: StarColors.textDim, fontSize: 15))),
                      ]),
                    ]),
                  ),
                  IconButton(icon: Icon(fav ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: fav ? StarColors.accent : null), onPressed: () => app.library.toggleFavorite(t)),
                  IconButton(icon: const Icon(Icons.playlist_add_rounded), onPressed: () => showAddToPlaylist(context, t)),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  PlatformIcon(player.substitute?.source ?? t.source, size: 13),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      player.error ?? (player.substitute != null ? 'Joué depuis SoundCloud (YouTube a refusé ce titre)' : sourceNames[t.source]!),
                      style: TextStyle(fontSize: 12, color: player.error != null ? Colors.redAccent : StarColors.textDim),
                    ),
                  ),
                ]),
                _Progress(player: player),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  IconButton(icon: Icon(Icons.shuffle_rounded, color: player.shuffle ? StarColors.accent : StarColors.textDim), onPressed: player.toggleShuffle),
                  IconButton(iconSize: 36, icon: const Icon(Icons.skip_previous_rounded), onPressed: player.previous),
                  _PlayButton(player: player, size: 64),
                  IconButton(iconSize: 36, icon: const Icon(Icons.skip_next_rounded), onPressed: player.next),
                  IconButton(
                    icon: Icon(player.repeat == RepeatSetting.one ? Icons.repeat_one_rounded : Icons.repeat_rounded, color: player.repeat == RepeatSetting.off ? StarColors.textDim : StarColors.accent),
                    onPressed: player.cycleRepeat,
                  ),
                ]),
                const SizedBox(height: 16),
              ]),
            );
          },
        ),
      ),
    );
  }

  void _showQueue(BuildContext context, PlayerController player) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.7,
        child: ListenableBuilder(
          listenable: player,
          builder: (ctx, _) => ListView.builder(
            itemCount: player.queue.length,
            itemBuilder: (ctx, i) {
              final t = player.queue[i];
              final isCurrent = i == player.index;
              return ListTile(
                leading: Artwork(t.thumbnail, size: 40),
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isCurrent ? StarColors.accent : null)),
                subtitle: Text(t.artist, maxLines: 1, style: const TextStyle(color: StarColors.textDim)),
                trailing: isCurrent ? const Icon(Icons.graphic_eq_rounded, color: StarColors.accent) : IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => player.removeFromQueue(i)),
                onTap: () => player.jumpTo(i),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatefulWidget {
  const _Progress({required this.player});
  final PlayerController player;

  @override
  State<_Progress> createState() => _ProgressState();
}

class _ProgressState extends State<_Progress> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final audio = widget.player.audio;
    return StreamBuilder<Duration>(
      stream: audio.positionStream,
      builder: (context, snap) {
        final total = audio.duration ?? widget.player.current?.duration ?? Duration.zero;
        final pos = snap.data ?? Duration.zero;
        final max = total.inMilliseconds.toDouble();
        final value = (_drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, max <= 0 ? 1.0 : max);
        return Column(children: [
          Slider(
            value: max <= 0 ? 0 : value,
            max: max <= 0 ? 1 : max,
            onChanged: max <= 0 ? null : (v) => setState(() => _drag = v),
            onChangeEnd: (v) {
              widget.player.seek(Duration(milliseconds: v.round()));
              setState(() => _drag = null);
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(formatDuration(Duration(milliseconds: value.round())).padLeft(4, '0'), style: const TextStyle(fontSize: 12, color: StarColors.textDim)),
              Text(formatDuration(total), style: const TextStyle(fontSize: 12, color: StarColors.textDim)),
            ]),
          ),
        ]);
      },
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.player, required this.size});
  final PlayerController player;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Material(
          color: StarColors.accent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: player.togglePlay,
            child: player.loading
                ? const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2.5, color: StarColors.onAccent))
                : Icon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: StarColors.onAccent, size: size * 0.55),
          ),
        ),
      );
}

class _LyricsView extends StatefulWidget {
  const _LyricsView({super.key, required this.load, required this.player});
  final Future<Lyrics> Function() load;
  final PlayerController player;

  @override
  State<_LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<_LyricsView> {
  final _scroll = ScrollController();
  late final Future<Lyrics> _lyrics = widget.load();
  int _active = -1;
  static const _lineHeight = 56.0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Lyrics>(
        future: _lyrics,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final l = snap.data!;
          if (l.isEmpty) return const Center(child: Text('Pas de paroles pour ce titre', style: TextStyle(color: StarColors.textDim)));
          if (l.synced.isEmpty) return SingleChildScrollView(child: Text(l.plain, style: const TextStyle(fontSize: 18, height: 1.6)));
          return StreamBuilder<Duration>(
            stream: widget.player.audio.positionStream,
            builder: (context, pos) {
              final p = pos.data ?? Duration.zero;
              var active = -1;
              for (var i = 0; i < l.synced.length && l.synced[i].time <= p; i++) {
                active = i;
              }
              if (active != _active) {
                _active = active;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!_scroll.hasClients || active < 0) return;
                  final target = (active * _lineHeight - _scroll.position.viewportDimension / 3).clamp(0.0, _scroll.position.maxScrollExtent);
                  _scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                });
              }
              return ListView.builder(
                controller: _scroll,
                itemExtent: _lineHeight,
                itemCount: l.synced.length,
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => widget.player.seek(l.synced[i].time),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l.synced[i].text.isEmpty ? '♪' : l.synced[i].text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: i == active ? StarColors.text : StarColors.textDim.withValues(alpha: 0.6)),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
}
