# StarMusic mobile

App Flutter pour iPhone et Android, avec les mêmes sources que la version PC : YouTube Music, YouTube et SoundCloud, sans pub ni compte.

## Installer

Télécharge le fichier de la dernière [release](https://github.com/razzzaa00/StarMusic/releases/latest) :

- **Android** : `starmusic-X.Y.Z-android.apk`. Ouvre-le sur le téléphone et autorise l'installation depuis cette source.
- **iPhone** : `starmusic-X.Y.Z-ios.ipa`. Sur un PC, installe [Sideloadly](https://sideloadly.io), branche l'iPhone, glisse le `.ipa` et connecte-toi avec ton identifiant Apple. Sur l'iPhone, active ensuite **Réglages → Confidentialité et sécurité → Mode développeur**, puis fais confiance au profil dans **Réglages → Général → VPN et gestion de l'appareil**. Avec un identifiant Apple gratuit, il faut refaire l'installation tous les 7 jours.

## Développer

```bash
cd mobile
flutter pub get
flutter run                                          # sur un téléphone ou un émulateur
flutter test                                         # tests rapides
flutter test --run-skipped -t live                   # tests réseau
flutter test --run-skipped -t golden --update-goldens  # captures d'écran dans test/goldens
```

Le workflow « Mobile » construit l'APK et l'IPA à chaque pull request qui touche `mobile/`, et les ajoute à chaque release.

L'APK est signé avec `android/app/sideload.jks`, une clé faite pour l'installation à la main (pas pour un store) : elle permet d'installer chaque version par-dessus la précédente.
