# Floutage de visages sur vidéo : la meilleure solution pour un APK Android libre

Date : 9 octobre 2026
Contraintes : pas d'usage commercial, chaîne 100 % libre, réutilisation maximale de modules fonctionnels existants.
Conséquence : les licences copyleft (GPL, AGPL) sont acceptables, mais toute brique propriétaire est exclue, en particulier Google ML Kit, que la plupart des apps « face blur » Android utilisent.

Toutes les versions et licences ci-dessous ont été vérifiées le 9 octobre 2026 (API GitHub, Google Maven, Maven Central, F-Droid, code source).

---

## 1. Verdict

**Application Kotlin native, assemblée à partir de deux modules libres et maintenus :**

| Rôle | Module réutilisé | Licence | Version | Ce qu'il apporte déjà |
|---|---|---|---|---|
| Détection de visages | MediaPipe Tasks Vision, Face Detector, plus l'exemple officiel `mediapipe-samples/examples/face_detector/android` | Apache-2.0 (code et modèles BlazeFace) | tasks-vision 1.1.0 (06/10/2026) | Mode VIDEO avec `detectForVideo`, délégué CPU ou GPU, lecture d'un fichier vidéo via `MediaMetadataRetriever`, affichage des boîtes |
| Décodage, rendu des masques, encodage, audio | Jetpack Media3 Transformer et Effect | Apache-2.0 | 1.11.1 (10/09/2026) | Codecs matériels, sortie MP4 H.264 ou H.265, copie de l'audio sans réencodage, effets GL par image, `CanvasOverlay.onDraw(canvas, timestamp)` et `ByteBufferGlEffect` pour un traitement CPU par image |

Le code à écrire se limite au suivi temporel, à la persistance des masques, au shader de mosaïque ou de flou, et à l'interface. Montée en gamme possible sans changer d'architecture : OpenCV 5.0.0 Android (YuNet, Apache-2.0) ou ONNX Runtime Android 1.31.0 (CenterFace, MIT) comme détecteurs « mode foule ».

---

## 2. Candidats évalués

| Piste | Constat vérifié | Verdict |
|---|---|---|
| **Forker ObscuraCam** (Guardian Project, GPL-3.0, 349 stars) | Seule app Android libre qui floute photos et vidéos. Mais dernière version F-Droid 5.0.0-RC-1 du 14/06/2022, dernier commit 10/2024, targetSdk 30, détection via l'API historique `android.media.FaceDetector` (visages de face seulement, 1 analyse toutes les 300 ms sur vidéo), rendu via GPUVideo-android (MIT) et un binaire ffmpeg lancé en shell. | Non comme base technique. Oui comme source d'inspiration pour l'interface de revue (timeline, régions manuelles, trails). |
| **DefaceIT Android** | Aucune licence, dépend de Google ML Kit (propriétaire). | Exclu. |
| **mrousavy/FaceBlurApp** (179 stars) | Aucune licence, React Native + ML Kit. | Exclu. |
| **Autres dépôts GitHub « android face blur »** | 0 à 4 stars, sans licence, abandonnés depuis 2016 à 2019. | Exclus. |
| **F-Droid** | Aucune app répondant à « blur face », « anonym », « censor », « pixelate » hormis ObscuraCam. | Rien à réutiliser. |
| **Chaquopy (MIT) + deface en Python** | opencv-python-headless et scikit-image existent dans le dépôt Chaquopy, donc deface tournerait avec `--backend opencv`. Mais imageio-ffmpeg ne fournit pas de binaire ffmpeg pour Android ARM, l'audio serait perdu et le traitement Python image par image est lent sur téléphone. | Prototype uniquement. |
| **Flutter + plugin Ultralytics** (AGPL-3.0) | Fournit l'inférence YOLO, pas la chaîne vidéo, et il faudrait un modèle visage tiers (GPL-3.0). | Non : plus de code natif à écrire qu'avec Media3 directement. |
| **FFmpegKit** | Projet retiré, dépôt archivé le 02/07/2026. La continuation ffmpeg-kit-next (LGPL-3.0) est distribuée en source seulement, donc à compiler soi-même. | À éviter : Media3 couvre le besoin avec les codecs matériels. |
| **Kotlin natif + MediaPipe + Media3** | Deux projets Apache-2.0 maintenus par Google, exemples officiels Apache-2.0 réutilisables tels quels, publiables sur F-Droid. | **Retenu.** |

---

## 3. Détecteur : quel modèle sur téléphone

| Modèle | Licence | Entrée | Portée | Vitesse publiée | Usage dans l'app |
|---|---|---|---|---|---|
| BlazeFace short-range (MediaPipe) | Apache-2.0 (model card) | 128 x 128 | moins de 2 m, selfies | 2,9 ms CPU sur Pixel 6 (pipeline complet) | Mode « caméra frontale » |
| BlazeFace full-range (MediaPipe) | Apache-2.0 | 128 x 128 | scènes caméra arrière | non publié | **Mode par défaut** |
| YuNet (OpenCV 5.0.0 Android, Maven Central) | Apache-2.0 | variable | bon sur petits visages | 17 fps en 720p sur 2 vCPU x86 (mesuré sur le Codespace) | Mode « foule » |
| CenterFace (ONNX Runtime Android 1.31.0) | MIT | variable | meilleur recall WIDER FACE hard | plus lent que YuNet | Mode « qualité », identique au pipeline desktop `blurr` |

Limite connue de BlazeFace : l'entrée 128 x 128 fait rater les visages lointains dans une foule. Parade intégrée au plan : inférence par tuiles (découper l'image en 2 x 2 ou 3 x 3 et détecter dans chaque tuile), puis fusion des boîtes. Sinon basculer sur YuNet.

---

## 4. Architecture retenue : deux passes

```
vidéo (galerie, SAF)
   │
   ▼  Passe 1 : analyse (Kotlin, coroutines)
MediaMetadataRetriever ou décodage MediaCodec en résolution réduite (largeur 640 à 960)
   │
   ▼
MediaPipe FaceDetector (RunningMode.VIDEO, délégué GPU si dispo)   ← module réutilisé
   │
   ▼
Suivi IoU + persistance N images + marge 1,3 (code maison, portage de la logique desktop)
   │
   ▼
timeline des masques : JSON { t_ms, [ { id, cx, cy, rx, ry } ] }   ← même format que le pipeline desktop
   │
   ▼  (optionnel) écran de revue : timeline, ajout de régions manuelles, aperçu
   │
   ▼  Passe 2 : rendu (Media3 Transformer)                          ← module réutilisé
EditedMediaItem + Effects(videoEffects = [ MaskEffect(timeline) ])
   MVP      : CanvasOverlay.onDraw(canvas, presentationTimeUs) → ellipses opaques
   Version 2: BaseGlShaderProgram maison → mosaïque ou flou limité aux ellipses (uniformes par image)
   │
   ▼
MP4 H.264 (ou H.265), audio copié sans réencodage, écrit via MediaStore dans Movies/blurr
   │
   ▼
Passe de contrôle : relancer le détecteur sur la sortie, compter les visages résiduels, bloquer l'export si > 0
```

Pourquoi deux passes plutôt qu'un seul `ByteBufferGlEffect` :

- la détection peut tourner plus lentement que l'encodeur matériel sans bloquer le pipeline ;
- l'utilisateur peut vérifier et corriger avant le rendu (ajouter une région, prolonger un masque) ;
- la timeline JSON est réutilisable par le pipeline desktop `blurr`, et inversement.

`ByteBufferGlEffect` reste l'option « une passe » pour un mode rapide sans revue.

---

## 5. Plan de mise en place

### Phase 1 : squelette à partir de l'exemple officiel (semaine 1)

1. Créer `android/` dans le dépôt `blurr` à partir de `mediapipe-samples/examples/face_detector/android` (Apache-2.0, minSdk 24, compileSdk 34, à monter en 35).
2. Remplacer `tasks-vision:1.0.0` par `1.1.0`. Committer les modèles `.tflite` dans `assets/` au lieu du téléchargement Gradle, pour une compilation reproductible (exigence F-Droid).
3. Garder `FaceDetectorHelper.detectVideoFile` et le mode galerie. Supprimer le mode caméra en direct dans un premier temps.
4. Sortie : liste des détections par horodatage, affichée sur la vidéo.

Critère : une vidéo choisie dans la galerie affiche ses boîtes de visages sur toute sa durée.

### Phase 2 : suivi, persistance et premier rendu (semaine 2)

1. Porter en Kotlin la logique de suivi du pipeline desktop : association IoU entre images consécutives, maintien d'une piste perdue pendant `hold` images (défaut 15) avec dilatation de 5 % par image, lissage sur 3 images, marge 1,3, masque elliptique.
2. Écrire la timeline JSON.
3. Ajouter `media3-transformer`, `media3-effect`, `media3-common` 1.11.1. Implémenter `MaskOverlay : CanvasOverlay` qui dessine les ellipses opaques de la timeline à chaque `presentationTimeUs`.
4. Exporter via `Transformer` vers un fichier `MediaStore` dans `Movies/blurr`, avec H.264 et audio conservé. Afficher la progression et permettre l'annulation.

Critère : premier MP4 anonymisé lisible, audio présent, durée identique à l'entrée.

### Phase 3 : mosaïque, flou, réglages (semaine 3)

1. Implémenter `MaskShaderProgram : BaseGlShaderProgram` avec un fragment shader qui pixelise ou floute uniquement à l'intérieur des ellipses passées en uniformes (jusqu'à 32 par image, au-delà repli sur le masque opaque).
2. Écran de réglages : détecteur, seuil (défaut 0,3 pour créer une piste, 0,15 pour la maintenir), marge, `hold`, mode de masquage, résolution d'analyse, délégué CPU ou GPU.
3. Traitement en arrière-plan avec `WorkManager` et service au premier plan, pour les vidéos longues.
4. Mesurer sur 3 téléphones (entrée, milieu, haut de gamme) : durée de traitement par minute de vidéo 1080p.

Critère : 1 minute de 1080p traitée en moins de 3 minutes sur un téléphone milieu de gamme (objectif à confirmer par mesure).

### Phase 4 : qualité et contrôle (semaine 4)

1. Mode « foule » : inférence par tuiles avec BlazeFace, puis YuNet via `org.opencv:opencv:5.0.0` (classe `FaceDetectorYN`, modèle `face_detection_yunet_2023mar.onnx`, 230 Ko).
2. Passe de contrôle : relancer le détecteur sur la sortie à seuil bas, afficher le nombre de visages résiduels et les horodatages, proposer d'ajouter des régions manuelles puis de relancer le rendu.
3. Vérifier que la sortie ne contient aucune métadonnée de l'entrée (GPS, date, modèle d'appareil) ; Transformer écrit un MP4 neuf, mais le point doit être testé.
4. Écran de revue inspiré d'ObscuraCam : timeline avec vignettes, régions manuelles, prolongation d'un masque.

### Phase 5 : publication libre (semaine 5)

1. Licence de l'app : GPL-3.0-or-later (compatible avec les dépendances Apache-2.0 et MIT ; cohérent avec « full libre »).
2. Compilation reproductible : pas de téléchargement au build, versions figées, modèles dans le dépôt.
3. Métadonnées fastlane (`metadata/fr-FR`), captures, changelog ; signature avec clé dédiée ; APK publié dans les releases GitHub, puis soumission à F-Droid via `fdroiddata`.
4. Point de vigilance F-Droid : `tasks-vision` est un AAR précompilé publié par Google à partir d'un dépôt Apache-2.0. F-Droid accepte en général les bibliothèques libres de Google Maven (c'est le cas d'AndroidX), mais la revue d'inclusion peut demander justification. Le plan B serait de compiler MediaPipe depuis les sources avec Bazel, ou de passer sur OpenCV et YuNet, tous deux sans ce risque.

---

## 6. Licences de la chaîne complète

| Composant | Licence | Compatible « full libre » |
|---|---|---|
| App `blurr` Android | GPL-3.0-or-later (proposé) | Oui |
| MediaPipe Tasks Vision + modèles BlazeFace | Apache-2.0 | Oui |
| Exemple `mediapipe-samples` | Apache-2.0 | Oui, à créditer |
| Jetpack Media3 Transformer et Effect | Apache-2.0 | Oui |
| AndroidX, Jetpack Compose, Kotlin coroutines | Apache-2.0 | Oui |
| OpenCV 5.0.0 Android (option) | Apache-2.0 | Oui |
| ONNX Runtime Android 1.31.0 + CenterFace (option) | MIT + MIT | Oui |
| Google ML Kit | Propriétaire | **Non, exclu** |
| FFmpegKit 6.0.LTS (binaire encore sur Maven Central) | LGPL-3.0, projet retiré | Possible mais inutile ici |

---

## 7. Risques et parades

| Risque | Parade |
|---|---|
| BlazeFace rate les petits visages en foule | Tuilage, puis YuNet ou CenterFace en mode foule ; passe de contrôle sur la sortie |
| Décalage entre horodatages d'analyse et de rendu | Analyser à partir des mêmes `presentationTimeUs` que Transformer (décodage MediaCodec plutôt que `getFrameAtTime`, qui arrondit à l'image clé la plus proche selon l'option choisie) ; interpoler les masques entre deux analyses |
| Vidéos à fréquence variable ou rotation dans les métadonnées | Media3 gère la rotation ; tester explicitement les vidéos 60 fps et VFR |
| Mémoire sur 4K | Analyse en résolution réduite, rendu GL sans copie CPU |
| Refus F-Droid sur l'AAR MediaPipe | Plan B OpenCV + YuNet, 100 % compilé depuis Maven Central ou sources |
| `ByteBufferGlEffect` et une partie de l'API Effect sont marquées instables | Épingler la version 1.11.1 et couvrir le rendu par un test instrumenté |

---

## 8. Sources

- https://developers.google.com/edge/mediapipe/solutions/vision/face_detector (modèles, options) et .../android (mode VIDEO)
- https://github.com/google-ai-edge/mediapipe-samples/tree/main/examples/face_detector/android (Apache-2.0, minSdk 24)
- Model card BlazeFace short-range : « Licensed under Apache License, Version 2.0 », portée inférieure à 2 m
- https://developer.android.com/media/media3/transformer/getting-started (dépendances 1.11.1, sortie MP4)
- https://github.com/androidx/media/tree/release/libraries/effect/src/main/java/androidx/media3/effect (`BitmapOverlay.getBitmap(long)`, `CanvasOverlay.onDraw(Canvas, long)`, `ByteBufferGlEffect`, `GaussianBlur`, `BaseGlShaderProgram`)
- https://github.com/guardianproject/ObscuraCam et https://f-droid.org/en/packages/org.witness.sscphase1/
- https://github.com/arthenica/ffmpeg-kit (archivé le 02/07/2026) et https://github.com/arthenica/ffmpeg-kit-next
- https://chaquo.com/pypi-13.1/ (paquets disponibles)
- Google Maven : tasks-vision 1.1.0, media3-transformer 1.11.1, litert 2.3.0 ; Maven Central : org.opencv:opencv 5.0.0, onnxruntime-android 1.31.0
