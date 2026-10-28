import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../state/library.dart';
import '../app_scope.dart';
import '../screens/album_screen.dart';
import '../theme.dart';
import '../widgets/artwork.dart';

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
}

Future<void> openAlbumOf(BuildContext context, Track track) async {
  final app = AppScope.of(context);
  final artist = track.artists.isEmpty ? track.artist : track.artists.first;
  showMessage(context, 'Recherche de l\'album…');
  final album = await app.albums.find(track.album, artist).catchError((_) => null);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  if (album == null) {
    showMessage(context, 'Album introuvable');
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => AlbumScreen(album: album)));
}

void searchFor(BuildContext context, String query) {
  Navigator.of(context).popUntil((r) => r.isFirst);
  AppScope.of(context).searchRequest.value = query;
}

Future<void> showAddToPlaylist(BuildContext context, Track track) async {
  final app = AppScope.of(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => ListenableBuilder(
      listenable: app.library,
      builder: (ctx, _) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.add_rounded, color: StarColors.accent),
                title: const Text('Nouvelle playlist'),
                onTap: () async {
                  final name = await promptText(ctx, 'Nouvelle playlist', '');
                  if (name == null) return;
                  final p = app.library.createPlaylist(name);
                  app.library.addToPlaylist(p, track);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) showMessage(context, 'Ajouté à ${p.name}');
                },
              ),
              for (final Playlist p in app.library.playlists)
                ListTile(
                  leading: const Icon(Icons.queue_music_rounded),
                  title: Text(p.name),
                  subtitle: Text(titles(p.tracks.length), style: const TextStyle(color: StarColors.textDim)),
                  onTap: () {
                    final added = app.library.addToPlaylist(p, track);
                    Navigator.pop(ctx);
                    showMessage(context, added ? 'Ajouté à ${p.name}' : 'Déjà dans ${p.name}');
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<String?> promptText(BuildContext context, String title, String initial) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: StarColors.surface,
      title: Text(title),
      content: TextField(controller: controller, autofocus: true, textCapitalization: TextCapitalization.sentences, onSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('OK')),
      ],
    ),
  );
}

Future<void> showTrackMenu(BuildContext context, Track track, {Playlist? playlist}) async {
  final app = AppScope.of(context);
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(track.artist, style: const TextStyle(color: StarColors.textDim))),
          const Divider(),
          ListTile(
            leading: Icon(app.library.isFavorite(track) ? Icons.favorite_rounded : Icons.favorite_border_rounded),
            title: Text(app.library.isFavorite(track) ? 'Retirer des favoris' : 'Ajouter aux favoris'),
            onTap: () {
              app.library.toggleFavorite(track);
              Navigator.pop(ctx);
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add_rounded),
            title: const Text('Ajouter à une playlist'),
            onTap: () {
              Navigator.pop(ctx);
              showAddToPlaylist(context, track);
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_play_rounded),
            title: const Text('Lire ensuite'),
            onTap: () {
              app.player.playNext(track);
              Navigator.pop(ctx);
              showMessage(context, 'Sera lu ensuite');
            },
          ),
          ListTile(
            leading: const Icon(Icons.queue_rounded),
            title: const Text('Ajouter à la file d\'attente'),
            onTap: () {
              app.player.addToQueue(track);
              Navigator.pop(ctx);
              showMessage(context, 'Ajouté à la file d\'attente');
            },
          ),
          if (track.album.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.album_rounded),
              title: Text('Album : ${track.album}', maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.pop(ctx);
                openAlbumOf(context, track);
              },
            ),
          if (playlist != null)
            ListTile(
              leading: const Icon(Icons.remove_circle_outline_rounded),
              title: Text('Retirer de ${playlist.name}'),
              onTap: () {
                app.library.removeFromPlaylist(playlist, track);
                Navigator.pop(ctx);
              },
            ),
        ],
      ),
    ),
  );
}
