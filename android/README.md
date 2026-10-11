# blurr : application Android (v0.2)

Floute les visages d'une vidéo, hors ligne. Détection YuNet (OpenCV), suivi temporel des détections, flou ou masque noir rendu par OpenGL dans Media3, aucune permission Internet.

**Statut : prototype.** Compilé et testé en JVM (46 tests), rendu validé hors téléphone (shaders exécutés avec Mesa), mais jamais exécuté sur un téléphone par l'auteur de ces modifications. Regarder la vidéo produite en entier avant toute diffusion.

## Nouveautés de la v0.2

- **Flou** à la place des ellipses noires (réglage « Rendu » ; le masque noir reste disponible, c'est la protection la plus sûre).
- **Moins de faux masques** : les détections sont suivies d'une image à l'autre. Une zone n'est masquée que si l'une de ses détections atteint un score de confirmation ; les détections isolées de score moyen sont écartées. À l'intérieur d'une piste confirmée, les trous de détection (jusqu'à 0,3 s) sont comblés par interpolation.
- **Contrôle du résultat** : ne signale plus que les visages détectables hors des zones masquées (un visage flouté peut rester détectable comme tache).

## Installer l'APK

Fichier : [apk/blurr-0.2-debug.apk](apk/blurr-0.2-debug.apk) (26 Mo, SHA-256 `9334546b4d124668c7f2490932659212685169aa2160c1d95c818585fc9120c7`). Prérequis : Android 10 ou plus, processeur ARM 64 bits. Même clé de signature que la v0.1 : l'installation se fait par-dessus.

1. Télécharger le fichier sur le téléphone en ouvrant `https://github.com/Momour/blurr/raw/main/android/apk/blurr-0.2-debug.apk` dans son navigateur (ou le copier par câble USB, stockage cloud, messagerie).
2. Ouvrir le fichier et autoriser l'installation depuis cette source quand Android le demande.
3. Si Play Protect affiche un avertissement (clé de débogage, application hors magasin), choisir « Installer quand même ».

L'APK est signé avec la clé de débogage publique `debug.keystore` du dépôt : ne pas le présenter comme une version de production.

## Utilisation

« Choisir une vidéo » (ou partager une vidéo vers blurr depuis la galerie), puis régler :

- **Précision de l'analyse** : 960, 1280 ou 1920 px sur le grand côté.
- **Sensibilité** : Normale (moins de faux masques, les visages de moins de ~20 px peuvent rester visibles), Élevée (défaut), Maximale (moins de visages manqués, davantage de faux masques).
- **Rendu** : Flou (défaut) ou Masque noir.

« Masquer les visages », garder l'application au premier plan, écran allumé. Le résultat est enregistré dans `Movies/blurr/<nom>_blurr.mp4`. En cas de problème : « Copier le journal (diagnostic) » en bas de l'écran (le journal ne contient ni GPS ni image).

## Limites

- Aucun détecteur ne trouve 100 % des visages (profils, petits visages, flous, nuit). Un visage jamais confirmé n'est pas masqué.
- Le flou protège moins que le masque noir : un visage familier peut rester reconnaissable à très basse résolution (silhouette, coiffure, contexte).
- Les seuils de sensibilité ont été choisis sur une seule vidéo de test, pas sur le jeu de test de l'étape 1.
- Seuls les visages sont traités : la voix (conservée telle quelle), les plaques et les écrans restent identifiables.
- Vidéos HDR converties en SDR. Traitement au premier plan uniquement.
- Les textes de licence des composants tiers ne sont pas embarqués dans l'APK. Inventaire des dépendances : [../THIRD_PARTY.md](../THIRD_PARTY.md).

## Compilation

Compilation rapide (JDK 17 ou plus, SDK Android 36, `local.properties` avec `sdk.dir=...`) :

```
./gradlew assembleDebug testDebugUnitTest
```

APK produit : `app/build/outputs/apk/debug/app-debug.apk`.

Sources principales : `app/src/main/java/app/blurr/` (`MainActivity` interface, `Analyzer` et `FrameSources` analyse, `MaskPlan` suivi et plan de masquage, `MaskEffect` et `BlurGeometry` rendu, `Exporter` export, `Verifier` contrôle du résultat).
