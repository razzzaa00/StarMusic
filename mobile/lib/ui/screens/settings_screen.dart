import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/search.dart';
import '../../services/updates.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/track_actions.dart';

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
              subtitle: const Text('Sur PC : Réglages → Storage → « Export all playlists », puis envoie le fichier .json sur ton téléphone (AirDrop, iCloud Drive, Google Drive…).', style: dim),
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
            const _EqualizerSection(),
            const Divider(),
            FutureBuilder<String>(
              future: AppScope.of(context).updates.installedVersion(),
              builder: (context, v) => ListTile(
                leading: const Icon(Icons.system_update_rounded),
                title: Text('StarMusic ${v.data ?? ''}'.trim()),
                subtitle: const Text('Touche pour vérifier les mises à jour.', style: dim),
                onTap: () => checkForUpdate(context, quiet: false),
              ),
            ),
            const ListTile(
              leading: Icon(Icons.info_outline_rounded),
              title: Text('À propos'),
              subtitle: Text('Sans pub · YouTube Music, YouTube et SoundCloud. Si YouTube refuse un titre, il est joué depuis SoundCloud.', style: dim),
            ),
          ],
        ),
      ),
    );
  }
}

class _EqualizerSection extends StatelessWidget {
  const _EqualizerSection();

  static String _hz(int hz) => hz >= 1000 ? '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)}k' : '$hz';

  @override
  Widget build(BuildContext context) {
    const dim = TextStyle(color: StarColors.textDim, fontSize: 13);
    final eq = AppScope.of(context).player.equalizer;
    if (eq == null || !eq.available) {
      return const ListTile(
        leading: Icon(Icons.graphic_eq_rounded),
        title: Text('Égaliseur'),
        subtitle: Text('Pas disponible sur iPhone : iOS ne laisse pas les apps modifier le son d\'un flux en ligne.', style: dim),
      );
    }
    return ListenableBuilder(
      listenable: eq,
      builder: (context, _) {
        final p = eq.parameters;
        return Column(children: [
          SwitchListTile(
            secondary: const Icon(Icons.graphic_eq_rounded),
            title: const Text('Égaliseur'),
            subtitle: p == null ? const Text('Lance un titre pour régler les bandes.', style: dim) : null,
            value: eq.enabled,
            onChanged: eq.setEnabled,
          ),
          if (p != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(children: [
                for (var i = 0; i < p.bands.length; i++)
                  Row(children: [
                    SizedBox(width: 48, child: Text(_hz((p.bands[i].centerFrequency).round()), style: dim, textAlign: TextAlign.right)),
                    Expanded(
                      child: Slider(
                        value: p.bands[i].gain.clamp(p.minDecibels, p.maxDecibels),
                        min: p.minDecibels,
                        max: p.maxDecibels,
                        onChanged: eq.enabled ? (v) => eq.setGain(i, v) : null,
                      ),
                    ),
                    SizedBox(width: 52, child: Text('${p.bands[i].gain >= 0 ? '+' : ''}${p.bands[i].gain.toStringAsFixed(1)} dB', style: dim)),
                  ]),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: eq.enabled ? eq.reset : null, child: const Text('Remettre à zéro')),
                ),
              ]),
            ),
        ]);
      },
    );
  }
}

/// Shows a banner when a newer release exists. [quiet] skips the "up to date" and error messages.
Future<void> checkForUpdate(BuildContext context, {bool quiet = true}) async {
  final updates = AppScope.of(context).updates;
  AppUpdate? update;
  try {
    update = await updates.check();
  } catch (_) {
    if (!quiet && context.mounted) showMessage(context, 'Impossible de vérifier, réessaie plus tard');
    return;
  }
  if (!context.mounted) return;
  if (update == null) {
    if (!quiet) showMessage(context, 'StarMusic est à jour');
    return;
  }
  final found = update;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showMaterialBanner(MaterialBanner(
    backgroundColor: StarColors.surfaceHigh,
    leading: const Icon(Icons.system_update_rounded, color: StarColors.accent),
    content: Text(found.downloadUrl != null
        ? 'StarMusic ${found.version} est disponible. Télécharge-le puis ouvre le fichier pour l\'installer par-dessus.'
        : 'StarMusic ${found.version} est disponible. Réinstalle le nouveau fichier .ipa avec Sideloadly (ou rafraîchis-le dans SideStore).'),
    actions: [
      TextButton(onPressed: messenger.hideCurrentMaterialBanner, child: const Text('Plus tard')),
      TextButton(
        onPressed: () {
          messenger.hideCurrentMaterialBanner();
          launchUrl(found.downloadUrl ?? found.pageUrl, mode: LaunchMode.externalApplication);
        },
        child: Text(found.downloadUrl != null ? 'Télécharger' : 'Voir'),
      ),
    ],
  ));
}
