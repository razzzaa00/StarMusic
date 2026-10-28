import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../state/library.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/track_actions.dart';
import '../widgets/track_tile.dart';

/// Favorites, history or a playlist: anything that is a list of tracks stored in the library.
class TrackListScreen extends StatelessWidget {
  const TrackListScreen({super.key, required this.title, required this.tracks, this.playlist, this.onClear});
  final String title;
  final List<Track> Function() tracks;
  final Playlist? playlist;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: app.library,
      builder: (context, _) {
        final list = tracks();
        final pl = playlist;
        return Scaffold(
          appBar: AppBar(
            title: Text(pl?.name ?? title),
            actions: [
              if (pl != null)
                PopupMenuButton<String>(
                  color: StarColors.surface,
                  onSelected: (v) async {
                    if (v == 'rename') {
                      final name = await promptText(context, 'Renommer', pl.name);
                      if (name != null) app.library.renamePlaylist(pl, name);
                    } else if (v == 'delete') {
                      app.library.deletePlaylist(pl);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Renommer')),
                    PopupMenuItem(value: 'delete', child: Text('Supprimer la playlist')),
                  ],
                ),
              if (onClear != null && list.isNotEmpty) TextButton(onPressed: onClear, child: const Text('Effacer')),
            ],
          ),
          body: list.isEmpty
              ? const Center(child: Text('Rien ici pour l\'instant', style: TextStyle(color: StarColors.textDim)))
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Row(children: [
                      Text(titles(list.length), style: const TextStyle(color: StarColors.textDim)),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Aléatoire',
                        icon: const Icon(Icons.shuffle_rounded),
                        onPressed: () {
                          if (!app.player.shuffle) app.player.toggleShuffle();
                          app.player.playQueue(list, (DateTime.now().millisecond) % list.length);
                        },
                      ),
                      const SizedBox(width: 4),
                      FilledButton.icon(
                        onPressed: () {
                          if (app.player.shuffle) app.player.toggleShuffle();
                          app.player.playQueue(list, 0);
                        },
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Lire'),
                      ),
                    ]),
                  ),
                  Expanded(
                    child: pl == null
                        ? ListView.builder(
                            itemCount: list.length,
                            itemBuilder: (_, i) => TrackTile(track: list[i], onTap: () => app.player.playQueue(list, i)),
                          )
                        : ReorderableListView.builder(
                            itemCount: list.length,
                            onReorderItem: (a, b) => app.library.reorderPlaylist(pl, a, b),
                            itemBuilder: (_, i) => TrackTile(key: ValueKey(list[i].key), track: list[i], playlist: pl, onTap: () => app.player.playQueue(list, i)),
                          ),
                  ),
                ]),
        );
      },
    );
  }
}
