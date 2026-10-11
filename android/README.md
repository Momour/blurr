# blurr : application Android (MVP v0.1)

Floute les visages d'une vidéo, hors ligne. Détection YuNet (OpenCV), export Media3, aucune permission Internet.

**Statut : prototype.** Compilé et testé en JVM (29 tests), validé hors téléphone sur les composants isolables, mais jamais exécuté sur un téléphone à la date de la version 0.1. Regarder la vidéo produite en entier avant toute diffusion.

## Installer l'APK

Fichier : [apk/blurr-0.1-debug.apk](apk/blurr-0.1-debug.apk) (26 Mo, SHA-256 `01b7fa69ce5a1c4c33bd61fc69598d01509fd7a577dec5958b4ab84bb9df35be`). Prérequis : Android 10 ou plus, processeur ARM 64 bits.

1. Télécharger le fichier sur le téléphone en ouvrant `https://github.com/Momour/blurr/raw/main/android/apk/blurr-0.1-debug.apk` dans son navigateur.
2. Ouvrir le fichier téléchargé et autoriser l'installation depuis cette source quand Android le demande.
3. Si Play Protect affiche un avertissement (clé de débogage, application hors magasin), choisir « Installer quand même ».

L'APK est signé avec la clé de débogage publique `debug.keystore` du dépôt : ne pas le présenter comme une version de production.

## Utilisation

« Choisir une vidéo » (ou partager une vidéo vers blurr depuis la galerie), régler si besoin la précision et la sensibilité, puis « Masquer les visages ». Garder l'application au premier plan, écran allumé. Le résultat est enregistré dans `Movies/blurr/<nom>_blurr.mp4`. En cas de problème : « Copier le journal (diagnostic) » en bas de l'écran (le journal ne contient ni GPS ni image).

## Limites

- Aucun détecteur ne trouve 100 % des visages (profils, petits visages, flous, nuit). Un visage non détecté sur plus de 5 images consécutives apparaît à l'image.
- Seuls les visages sont masqués : la voix (conservée telle quelle), les plaques et les écrans restent identifiables.
- Vidéos HDR converties en SDR. Traitement au premier plan uniquement.
- Les textes de licence des composants tiers ne sont pas embarqués dans l'APK. Inventaire des dépendances : [../THIRD_PARTY.md](../THIRD_PARTY.md).

## Compilation

Compilation rapide (JDK 17 ou plus, SDK Android 36, `local.properties` avec `sdk.dir=...`) :

```
./gradlew assembleDebug testDebugUnitTest
```

APK produit : `app/build/outputs/apk/debug/app-debug.apk`.

Sources principales : `app/src/main/java/app/blurr/` (`MainActivity` interface, `Analyzer` et `FrameSources` analyse, `MaskPlan` et `MaskEffect` masquage, `Exporter` export, `Verifier` contrôle du résultat).
