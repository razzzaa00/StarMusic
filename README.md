# StarMusic

Lecteur de musique **sans pub**, léger et gratuit, pour **Windows, Linux et macOS**.

StarMusic est un fork de [Riff](https://github.com/rootscripts/riff) (licence MIT, par rootless / rootscripts).

## Fonctionnalités

- **Streaming sans pub** depuis **YouTube Music, YouTube et SoundCloud**, sans compte.
- **Fichiers locaux** : FLAC, WAV, MP3, OGG, M4A, avec lecture des tags et des pochettes.
- **Import de playlists** depuis **Spotify, Apple Music, YouTube Music et SoundCloud** : colle le lien d'une playlist publique et elle devient une playlist StarMusic.
- **Equalizer 10 bandes**, vitesse, pitch, reverb, distorsion et normalisation du volume.
- **Playlists, favoris, albums**, file d'attente, lecture aléatoire et répétition.
- **Paroles synchronisées** (karaoké, fichiers LRC, traduction).
- **Téléchargement hors-ligne** en MP3, FLAC, Opus ou WAV.
- **Réglages complets** : thèmes, couleurs, polices, visualiseurs, CSS personnalisé, plugins, Discord Rich Presence.
- Pas de télémétrie : tout est stocké en local.

## Installer

Les installateurs sont publiés sur la page [Releases](https://github.com/razzzaa00/starmusic/releases).

Pour publier une nouvelle version, pousse un tag `vX.Y.Z` (par exemple `git tag v1.0.0 && git push origin v1.0.0`). Le workflow GitHub Actions construit l'installateur Windows (`.exe`), Linux (`.AppImage`) et macOS (`.dmg`) et les met dans la release.

StarMusic a besoin de **yt-dlp** et **ffmpeg** pour le streaming et les téléchargements. Au premier lancement, l'app propose de les installer. Sinon, mets-les dans le dossier `bin/` ou dans le `PATH` (sur macOS : `brew install yt-dlp ffmpeg`).

### macOS

L'app n'est pas signée. Après l'avoir glissée dans `Applications`, fais clic droit sur `StarMusic.app`, puis **Ouvrir**. Si macOS dit que l'app est endommagée :

```bash
xattr -cr /Applications/StarMusic.app
```

## Lancer depuis le code

Il faut Node.js 18 ou plus récent.

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

Pas encore de version mobile. C'est la prochaine étape prévue.

## Avertissement

StarMusic est destiné à un usage personnel. Chaque utilisateur est responsable du respect des conditions d'utilisation des plateformes tierces et du droit d'auteur.

## Licence

[MIT](LICENSE). Le code d'origine reste © rootscripts (Riff).
