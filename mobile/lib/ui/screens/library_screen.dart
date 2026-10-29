import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/track_actions.dart';
import 'track_list_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final lib = app.library;
    void open(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: lib,
        builder: (context, _) => ListView(
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text('Bibliothèque', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700))),
            ListTile(
              leading: const _Square(icon: Icons.favorite_rounded),
              title: const Text('Favoris'),
              subtitle: Text(titles(lib.favorites.length), style: const TextStyle(color: StarColors.textDim)),
              onTap: () => open(TrackListScreen(title: 'Favoris', tracks: () => lib.favorites)),
            ),
            ListTile(
              leading: const _Square(icon: Icons.history_rounded),
              title: const Text('Historique'),
              subtitle: Text(titles(lib.history.length), style: const TextStyle(color: StarColors.textDim)),
              onTap: () => open(TrackListScreen(title: 'Historique', tracks: () => lib.history, onClear: lib.clearHistory)),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(children: [
                const Text('Playlists', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.link_rounded),
                  tooltip: 'Importer depuis un lien',
                  onPressed: () => importFromLink(context),
                ),
                IconButton(
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Nouvelle playlist',
                  onPressed: () async {
                    final name = await promptText(context, 'Nouvelle playlist', '');
                    if (name != null) lib.createPlaylist(name);
                  },
                ),
              ]),
            ),
            if (lib.playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aucune playlist. Crée-en une, colle le lien d\'une playlist Spotify, YouTube ou SoundCloud (bouton lien), ou importe celles du PC depuis les Réglages.', style: TextStyle(color: StarColors.textDim)),
              ),
            for (final p in lib.playlists)
              ListTile(
                leading: p.tracks.isEmpty ? const _Square(icon: Icons.queue_music_rounded) : Artwork(p.tracks.first.thumbnail, size: 48),
                title: Text(p.name),
                subtitle: Text(titles(p.tracks.length), style: const TextStyle(color: StarColors.textDim)),
                onTap: () => open(TrackListScreen(title: p.name, tracks: () => p.tracks, playlist: p)),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

Future<void> importFromLink(BuildContext context) async {
  final app = AppScope.of(context);
  final link = await promptText(context, 'Lien d\'une playlist Spotify, YouTube ou SoundCloud', '');
  if (link == null || link.trim().isEmpty || !context.mounted) return;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      backgroundColor: StarColors.surface,
      content: Row(children: [SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 16), Text('Import en cours…')]),
    ),
  );
  try {
    final imported = await app.importer.load(link);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    if (imported.tracks.isEmpty) {
      showMessage(context, 'Aucun titre lisible dans cette playlist');
      return;
    }
    app.library.importPlaylist(imported.name, imported.tracks);
    showMessage(context, '« ${imported.name} » importée : ${titles(imported.tracks.length)}');
  } on FormatException {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    showMessage(context, 'Lien non reconnu, ou playlist privée');
  } catch (_) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    showMessage(context, 'Import impossible, vérifie ta connexion');
  }
}

class _Square extends StatelessWidget {
  const _Square({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: StarColors.surfaceHigh, borderRadius: BorderRadius.circular(6)),
        child: Icon(icon, color: StarColors.accent),
      );
}
