# MVP Android v0.1

**Statut : prototype. Compilé, testé en JVM, validé hors téléphone sur les composants isolables. Jamais exécuté sur un téléphone à la date d'écriture.** Les points non vérifiés sont listés en section 5.

## 1. Principe

L'application ne s'appuie sur aucun entraînement et aucun jeu de données : elle assemble des composants existants. Tout le traitement est local, la permission Internet n'est pas déclarée (le système interdit donc tout accès réseau à l'application).

Trois passes sur la vidéo choisie :

1. **Analyse.** Décodage image par image (MediaExtractor + MediaCodec, sortie mémoire), détection de visages avec YuNet (`face_detection_yunet_2023mar.onnx`, MIT) exécuté par OpenCV 4.14 (`FaceDetectorYN`). Chaque boîte devient une ellipse centrée, de demi-axes largeur × 1,6 / 2 et hauteur × 1,6 / 2. Chaque détection est propagée aux 5 images voisines avant et après (union des ellipses), pour couvrir les images où le détecteur décroche.
2. **Export.** Media3 Transformer 1.11.1 ré-encode la vidéo avec un effet OpenGL maison (`MaskEffect`) qui noircit les ellipses (noir opaque, bord lissé sur 1 à 2 pixels). Débit vidéo repris de la source (borné à 2 à 80 Mb/s), son conservé (copié sans ré-encodage quand Media3 le permet), métadonnées de la source non recopiées (GPS compris). La vidéo HDR est convertie en SDR.
3. **Contrôle.** Relecture du fichier produit (une image sur n, 600 au plus) avec un seuil de détection strict (0,6). Si un visage reste détectable, l'écran de fin le signale. Ce contrôle repère une erreur du traitement (masques décalés, mal placés ou absents). Il ne voit pas un visage que le détecteur n'a déjà pas trouvé dans la vidéo d'origine.

Le fichier est enregistré dans `Movies/blurr/<nom>_blurr.mp4`.

## 2. Installation

Prérequis : Android 10 ou plus (API 29), processeur ARM 64 bits (arm64-v8a). Le fichier fait 26 Mo.

1. Copier `android/dist/blurr-0.1-debug.apk` sur le téléphone (câble USB, stockage cloud ou messagerie). Ce dossier est ignoré par git : après un clonage du dépôt, l'APK est absent et se recompile (section 4).
2. Ouvrir le fichier sur le téléphone et autoriser l'installation depuis cette source quand Android le demande.
3. Play Protect peut afficher un avertissement : l'APK est signé avec une clé de débogage et n'est pas publié sur un magasin. Choisir « Installer quand même ».

Autre voie, depuis un ordinateur avec `adb` : `adb install -r android/dist/blurr-0.1-debug.apk`.

## 3. Utilisation

1. « Choisir une vidéo » (sélecteur Android), ou partager une vidéo vers blurr depuis la galerie.
2. Régler si besoin la précision de l'analyse (960, 1280 ou 1920 pixels sur le grand côté) et la sensibilité (seuil de score 0,6, 0,4 ou 0,25 ; défaut 0,4). Une sensibilité plus haute manque moins de visages et masque davantage de faux positifs.
3. « Masquer les visages ». Laisser l'application au premier plan, écran allumé : le traitement s'interrompt si Android suspend l'application.
4. En fin de traitement : ouvrir ou partager le résultat. **Regarder la vidéo en entier avant toute diffusion.**
5. En cas de problème : « Copier le journal (diagnostic) » en bas de l'écran, puis coller le texte dans un message. Le journal contient le modèle de téléphone, la version d'Android, les caractéristiques techniques de la vidéo, le nom du fichier produit et les étapes du traitement. Il ne contient ni coordonnées GPS ni image.

## 4. Compilation

Prérequis : JDK 17 ou plus, SDK Android avec la plateforme 36. Créer `android/local.properties` avec la ligne `sdk.dir=<chemin du SDK>` (fichier ignoré par git), puis :

```
cd android
./gradlew assembleDebug        # Windows : gradlew.bat assembleDebug
./gradlew testDebugUnitTest
```

L'APK est produit dans `android/app/build/outputs/apk/debug/app-debug.apk`. Premier lancement : téléchargement de Gradle, du plugin Android, de Media3 et d'OpenCV (environ 1,5 Go de cache Gradle après la première compilation). Les dépôts sont `google()` et `mavenCentral()`. Si Maven Central répond par une erreur 429 (limite de débit), ajouter `blurrMavenMirror=true` dans `~/.gradle/gradle.properties` pour utiliser le miroir de Maven Central opéré par Google (voir `android/settings.gradle.kts`).

Sous Linux ou macOS, le bit exécutable de `gradlew` peut manquer après un passage par Windows : `git update-index --chmod=+x android/gradlew`.

## 5. État de vérification

| Élément | Statut | Détail |
|---|---|---|
| Compilation, signature APK | Vérifié | AGP 8.13.2, Kotlin 2.3.21, signature APK v2 vérifiée avec `apksigner` |
| Permissions | Vérifié | Pas d'`INTERNET`. `ACCESS_NETWORK_STATE` et `WAKE_LOCK` sont ajoutées par Media3 |
| Tests unitaires JVM | Vérifié | 29 sur 29 (plan de masques, empaquetage YUV, rotation, débit, noms de fichiers) |
| Lint Android | Vérifié | 0 erreur, 19 avertissements (textes non traduisibles, versions de dépendances) |
| Bibliothèques natives | Vérifié | Segments ELF alignés sur 16 Ko, arm64-v8a seul |
| Modèle YuNet avec OpenCV 4.14.0 | Vérifié hors téléphone | Fichier exact de l'APK (SHA-256 `8f2383e4…2552fa4`). Visage détecté à toutes les tailles testées (de 120 à 600 pixels, formats paysage, portrait et dimensions non multiples de 32), score 0,88 à 0,94, aucune détection sur fond uni ni bruit |
| Masque : shader et placement | Vérifié hors téléphone | Mêmes sources de shader que l'APK, compilées avec Mesa (OpenGL ES) : le visage est entièrement couvert au bon endroit, sans inversion verticale, sous les conventions de textures de Media3 lues dans son code source |
| Décodage MediaCodec en mémoire, rotation portrait, horodatages | **Non vérifié** | Dépend du décodeur du téléphone. Un repli (MediaMetadataRetriever) et un garde-fou de rotation sont codés |
| Export Media3 avec l'effet, HDR vers SDR | **Non vérifié** | Une seconde tentative avec un mode HDR de secours est codée |
| Interface | **Non vérifié** | |
| Vitesse sur téléphone | **Non mesurée** | Sur le processeur x86 de compilation, YuNet prend 30 à 150 ms par image à 960 à 1280 pixels, valeur non représentative |
| Rappel de détection (visages manqués) | **Non mesuré** | Le jeu de test de l'étape 1 n'a pas été utilisé |

## 6. Limites et risques connus

- **Aucun détecteur ne trouve 100 % des visages.** Risque accru : profils marqués, visages très petits, flous, partiellement cachés, de nuit, avec masque ou lunettes opaques. Pas de suivi temporel : un visage non détecté sur plus de 5 images consécutives apparaît à l'image.
- **Seuls les visages sont masqués.** Voix (le son est conservé tel quel), plaques, écrans, tatouages, vêtements et contexte restent identifiables.
- **Traitement au premier plan uniquement** (pas de service d'arrière-plan en v0.1).
- **Espace disque** : environ deux fois la taille du fichier de sortie (fichier temporaire, puis copie dans la galerie). L'application refuse de démarrer si l'espace est manifestement insuffisant.
- **Clé de signature de débogage** versionnée dans `android/debug.keystore` : elle permet les mises à jour entre machines, mais n'importe qui peut signer un APK avec la même clé. À remplacer par une clé privée avant toute diffusion.
- **Vidéos HDR** : converties en SDR. Si la conversion standard échoue, la méthode de secours donne des couleurs ternes.
- **Horodatages** : les masques sont appliqués par correspondance de temps entre l'analyse et l'export, avec un calage sur la première image. Un fichier dont le début est rogné par une liste d'édition peut décaler les masques. Le contrôle automatique et la note « images analysées contre exportées » sont là pour le signaler.
- **Licences** : l'APK n'embarque ni les textes de licence ni l'avis de copyright du modèle YuNet (MIT). Les composants natifs internes d'OpenCV (libjpeg-turbo, libpng, libwebp, etc.) sont repérés mais leurs licences ne sont pas inventoriées (voir [THIRD_PARTY.md](../THIRD_PARTY.md)). À traiter avant toute diffusion publique.

## 7. Décisions

| Réf. | Décision |
|---|---|
| M1 | Aucun entraînement ni jeu de données : détecteur pré-entraîné YuNet (MIT), exécuté par OpenCV (Apache-2.0). |
| M2 | Pas de FFmpeg dans l'application : Media3 (Apache-2.0) fournit décodage, effet GL, encodage et mux. |
| M3 | Masque noir opaque en ellipse × 1,6 plutôt qu'un flou : un flou léger est parfois réversible. |
| M4 | Marge temporelle de 5 images de chaque côté de chaque détection. |
| M5 | Aucune permission Internet. |
| M6 | Métadonnées de la vidéo source non recopiées dans la sortie (position GPS comprise). |

## 8. Suite possible

Mesurer le rappel et la vitesse sur le jeu de test de l'étape 1, ajouter un suivi temporel pour réduire les trous de détection, passer le traitement dans un service de premier plan, remplacer la clé de signature, ajouter un écran « Licences », ajouter une option de flou, traiter plusieurs vidéos à la suite.
