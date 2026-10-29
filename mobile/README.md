# StarMusic mobile

App Flutter pour iPhone et Android, avec les mêmes sources que la version PC : YouTube Music, YouTube et SoundCloud, sans pub ni compte.

## Installer

Télécharge le fichier de la dernière [release](https://github.com/razzzaa00/StarMusic/releases/latest) :

- **Android** : `starmusic-X.Y.Z-android.apk`. Ouvre-le sur le téléphone et autorise l'installation depuis cette source.
- **iPhone** : voir ci-dessous.

### iPhone

Apple ne laisse installer une app hors App Store qu'en la signant avec ton identifiant Apple. Avec un identifiant gratuit, la signature dure 7 jours. Deux façons de faire :

**Option 1 : Sideloadly (le plus simple, depuis un PC)**
1. Sur le PC, installe [iTunes](https://www.apple.com/itunes/) (version du site Apple, pas celle du Microsoft Store) et [Sideloadly](https://sideloadly.io).
2. Télécharge `starmusic-X.Y.Z-ios.ipa` depuis la release.
3. Branche l'iPhone en USB, déverrouille-le et touche « Se fier à cet ordinateur ».
4. Dans Sideloadly : glisse le `.ipa`, mets ton identifiant Apple, clique sur **Start**, puis tape ton mot de passe Apple.
5. Sur l'iPhone : **Réglages → Confidentialité et sécurité → Mode développeur** → activer, puis redémarrer.
6. **Réglages → Général → VPN et gestion de l'appareil** → touche ton identifiant Apple → **Faire confiance**.
7. Tous les 7 jours, refais l'étape 4 (Sideloadly peut le faire tout seul si le PC et l'iPhone sont sur le même Wi-Fi : option « Auto refresh »).

**Option 2 : SideStore (sans PC après la première installation)**
1. Installe [SideStore](https://sidestore.io) en suivant leur guide (il faut un PC une seule fois).
2. Dans SideStore : **Sources → +** et colle `https://github.com/razzzaa00/StarMusic/releases/latest/download/altstore-source.json`.
3. Installe StarMusic depuis cette source. SideStore renouvelle la signature et propose les mises à jour directement sur l'iPhone.

L'app prévient quand une nouvelle version sort (et sur Android, le bouton télécharge directement le nouvel APK).

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
