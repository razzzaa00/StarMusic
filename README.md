# StarMusic

Lecteur de musique **sans pub**, léger et gratuit, pour **Windows, Linux et macOS**.

StarMusic est un fork de [Riff](https://github.com/rootscripts/riff) (licence MIT, par rootless / rootscripts).

## Fonctionnalités

- **Streaming sans pub** depuis **YouTube Music, YouTube et SoundCloud**, sans compte.
- **Fichiers locaux** : FLAC, WAV, MP3, OGG, M4A, avec lecture des tags et des pochettes.
- **Import de playlists** depuis **Spotify, Apple Music, YouTube Music et SoundCloud** : colle le lien d'une playlist publique et elle devient une playlist StarMusic.
- **Equalizer 10 bandes**, vitesse, pitch, reverb, distorsion et normalisation du volume.
- **Playlists, favoris, albums**, file d'attente, lecture aléatoire et répétition, tri par date d'ajout, titre, artiste ou durée.
- **Paroles synchronisées** (karaoké, fichiers LRC, traduction).
- **Téléchargement hors-ligne** en MP3, FLAC, Opus ou WAV.
- **Réglages complets** : thèmes, couleurs, polices, visualiseurs, CSS personnalisé, plugins, Discord Rich Presence.
- **Interface minimale** : noir uni, une seule couleur d'accent, animations courtes en fondu (respecte le réglage « réduire les animations » du système).
- Pas de télémétrie : tout est stocké en local.

## Installer

Les installateurs sont publiés sur la page [Releases](https://github.com/razzzaa00/starmusic/releases).

Pour publier une nouvelle version : sur GitHub, **Releases → Draft a new release**, crée un tag `vX.Y.Z` (par exemple `v1.0.1`) et publie. On peut aussi pousser le tag en ligne de commande (`git tag v1.0.1 && git push origin v1.0.1`). Le workflow « Release » construit alors l'installateur Windows (`.exe`), Linux (`.AppImage`) et macOS (`.dmg`), ainsi que les apps Android (`.apk`) et iPhone (`.ipa`), et les ajoute à la release. S'il ne démarre pas tout seul : onglet **Actions → Release → Run workflow**, en choisissant le tag dans la liste.

StarMusic a besoin de **yt-dlp** et **ffmpeg** pour le streaming et les téléchargements. Au premier lancement, l'app propose de les installer. Sinon, mets-les dans le dossier `bin/` ou dans le `PATH` (sur macOS : `brew install yt-dlp ffmpeg`).

### macOS

L'app n'est pas signée. Après l'avoir glissée dans `Applications`, fais clic droit sur `StarMusic.app`, puis **Ouvrir**. Si macOS dit que l'app est endommagée :

```bash
xattr -cr /Applications/StarMusic.app
```

## Lancer depuis le code

Il faut Node.js 18 ou plus récent. L'app tourne sur Electron 45.

```bash
git clone https://github.com/razzzaa00/starmusic.git
cd starmusic
npm install
npm start        # version de dev
npm run dist     # construire l'installateur pour ton système
npm test         # tests
```

## Où sont stockées les données

- Windows : `%LOCALAPPDATA%\StarMusic`
- macOS : `~/Library/Application Support/StarMusic`
- Linux : `~/.cache/starmusic` (données) et `~/.config/starmusic` (config)

## Mobile (iPhone / Android)

L'app mobile est dans [`mobile/`](mobile/README.md) (Flutter). Chaque release contient :

- `starmusic-X.Y.Z-android.apk` : ouvre-le sur le téléphone et autorise l'installation d'apps inconnues. Les versions suivantes s'installent par-dessus sans perdre la bibliothèque.
- `starmusic-X.Y.Z-ios.ipa` : à installer avec [Sideloadly](https://sideloadly.io) depuis un PC, ou avec SideStore (source : `https://github.com/razzzaa00/StarMusic/releases/latest/download/altstore-source.json`). Étapes détaillées dans le [guide mobile](mobile/README.md#iphone).

Recherche sur YouTube Music, YouTube et SoundCloud, import de playlists Spotify, YouTube et SoundCloud par lien, albums, paroles synchronisées, favoris, playlists, file d'attente, lecture en arrière-plan avec les commandes de l'écran verrouillé, égaliseur (Android). Les playlists du PC s'importent depuis les réglages (fichier exporté par « Export all playlists »).

## Avertissement

StarMusic est destiné à un usage personnel. Chaque utilisateur est responsable du respect des conditions d'utilisation des plateformes tierces et du droit d'auteur.

## Licence

[MIT](LICENSE). Le code d'origine reste © rootscripts (Riff).
