import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/search.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/track_actions.dart';

const appVersion = '1.0.0';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _scopeLabels = {
    SearchScope.all: 'Toutes les plateformes',
    SearchScope.ytmusic: 'YouTube Music',
    SearchScope.youtube: 'YouTube',
    SearchScope.soundcloud: 'SoundCloud',
  };

  Future<void> _import(BuildContext context) async {
    final app = AppScope.of(context);
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
    if (file == null) return;
    try {
      final bytes = await file.xFile.readAsBytes();
      final added = app.library.importPcPlaylists(utf8.decode(bytes));
      if (context.mounted) showMessage(context, '$added titres importés');
    } catch (_) {
      if (context.mounted) showMessage(context, 'Fichier non reconnu');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = AppScope.of(context).library;
    const dim = TextStyle(color: StarColors.textDim, fontSize: 13);
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: lib,
        builder: (context, _) => ListView(
          children: [
            const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text('Réglages', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700))),
            const ListTile(
              title: Text('Recherche par défaut'),
              subtitle: Text('Où cherche la barre de recherche. « Toutes les plateformes » cherche sur YouTube Music, YouTube et SoundCloud en même temps.', style: dim),
            ),
            RadioGroup<SearchScope>(
              groupValue: lib.searchScope,
              onChanged: (v) => v == null ? null : lib.setSearchScope(v),
              child: Column(children: [
                for (final s in SearchScope.values) RadioListTile<SearchScope>(value: s, title: Text(_scopeLabels[s]!), dense: true),
              ]),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('Importer les playlists du PC'),
              subtitle: const Text('Sur PC : Réglages → Storage → « Export all playlists », puis envoie le fichier .json sur ton iPhone (AirDrop, iCloud Drive…).', style: dim),
              onTap: () => _import(context),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Effacer l\'historique'),
              onTap: () {
                lib.clearHistory();
                showMessage(context, 'Historique effacé');
              },
            ),
            const Divider(),
            const ListTile(
              leading: Icon(Icons.graphic_eq_rounded),
              title: Text('Égaliseur'),
              subtitle: Text('Pas encore disponible sur iPhone : iOS ne donne pas accès au son du lecteur à l\'égaliseur utilisé sur PC.', style: dim),
            ),
            const ListTile(
              leading: Icon(Icons.info_outline_rounded),
              title: Text('StarMusic pour iPhone $appVersion'),
              subtitle: Text('Sans pub · YouTube Music, YouTube et SoundCloud. Si YouTube refuse un titre, il est joué depuis SoundCloud.', style: dim),
            ),
          ],
        ),
      ),
    );
  }
}
