# Plan détaillé : application Android `blurr` de floutage de visages sur vidéo

| | |
|---|---|
| Version du plan | 1.0, 9 octobre 2026 |
| Statut | Proposé, en attente des décisions ouvertes de la section 12 |
| Documents liés | [analyse-audit-et-plan.md](analyse-audit-et-plan.md) (audit des outils, pipeline desktop), [android-apk.md](android-apk.md) (comparatif des pistes Android) |
| Contraintes | Usage non commercial, chaîne 100 % libre, réutilisation maximale de modules existants |

---

## 1. Contexte et objectifs

`blurr` doit permettre à une personne de choisir une vidéo sur son téléphone Android et d'obtenir une copie où tous les visages sont masqués, sans envoyer la moindre donnée hors de l'appareil.

Objectifs mesurables de la version 1 :

| Objectif | Cible | Comment on le mesure |
|---|---|---|
| Aucune fuite d'identité | 0 image où un visage annoté est couvert à moins de 90 % | Corpus annoté + passe de contrôle automatique (section 8) |
| Rappel par image | ≥ 0,98 sur le corpus | Script d'évaluation |
| Temps de traitement | 1 minute de 1080p en moins de 3 minutes sur un téléphone milieu de gamme | Mesure sur 3 appareils (phase 3) |
| Respect de la vie privée | Aucune permission réseau, aucune télémétrie, aucune métadonnée source dans la sortie | Manifeste sans `INTERNET`, test de métadonnées |
| Chaîne libre | 100 % des dépendances sous licence libre, build reproductible | Rapport de licences en CI, soumission F-Droid |

---

## 2. Périmètre

Inclus dans la version 1 :

- Sélection d'une vidéo locale (galerie, sélecteur de fichiers), formats lus par ExoPlayer (MP4, MOV, MKV, WebM).
- Détection automatique des visages sur toute la durée, suivi temporel, persistance des masques.
- Masques opaque, mosaïque et flou, forme elliptique, marge réglable.
- Rendu avec codecs matériels, audio conservé, sortie MP4 dans `Movies/blurr`.
- Passe de contrôle qui recompte les visages sur la sortie.
- Interface en français et en anglais.

Exclus de la version 1 (voir backlog, section 11) : plaques d'immatriculation, altération de la voix, traitement en direct depuis la caméra, édition manuelle avancée, traitement par lot.

---

## 3. Journal des décisions

Chaque décision est numérotée pour pouvoir être citée dans les commits et les issues.

| ID | Décision | Alternatives écartées | Justification | Statut |
|---|---|---|---|---|
| D01 | Application Android native en Kotlin, interface Jetpack Compose | Flutter + plugin Ultralytics, React Native, Chaquopy + deface, PWA | Les deux modules qui font le travail (MediaPipe, Media3) sont des bibliothèques Android natives ; tout autre cadre ajoute une couche sans retirer de code natif. Chaquopy n'a pas de binaire ffmpeg Android et perd l'audio. | Adoptée |
| D02 | Détecteur par défaut : MediaPipe Face Detector, modèle BlazeFace full-range (1,08 Mo), short-range (230 Ko) proposé pour les selfies | Google ML Kit, android.media.FaceDetector, YOLO-face | ML Kit est propriétaire. L'API système ne détecte que les visages de face. YOLO-face est GPL et plus lourd sans gain prouvé sur téléphone. MediaPipe est Apache-2.0, modèles inclus, maintenu, 2,9 ms par image sur Pixel 6 en short-range. | Adoptée |
| D03 | Mode « foule » optionnel avec YuNet via OpenCV 5.0.0 Android (Apache-2.0), puis CenterFace via ONNX Runtime Android 1.31.0 (MIT) | Se limiter à BlazeFace | BlazeFace travaille en 128 x 128 et rate les visages lointains. YuNet a mesuré 17 fps en 720p sur 2 vCPU x86 avec 19 visages par image. CenterFace est le modèle du pipeline desktop, ce qui donne une parité de résultats. | Adoptée, livrée en phase 4 |
| D04 | Chaîne vidéo : Jetpack Media3 Transformer et Effect 1.11.1 | FFmpegKit (retiré et archivé le 02/07/2026), MediaCodec manuel, GPUVideo-android (utilisé par ObscuraCam) | Codecs matériels, sortie MP4, audio copié sans réencodage, effets GL par image avec horodatage, maintenu par Google sous Apache-2.0. | Adoptée |
| D05 | Architecture en deux passes : analyse qui produit une timeline de masques, puis rendu | Une seule passe avec `ByteBufferGlEffect` | Permet la revue avant rendu, découple la vitesse de détection de celle de l'encodeur, et la timeline est réutilisable par le pipeline desktop. `ByteBufferGlEffect` reste une option « mode rapide ». | Adoptée |
| D06 | Timeline de masques en JSON avec coordonnées normalisées (0 à 1), format partagé avec le pipeline desktop | Format binaire, format propre à Android | Indépendant de la résolution, lisible, diffable, testable avec des fichiers de référence. | Adoptée |
| D07 | Paramètres par défaut : masque elliptique, marge 1,3, seuil de création de piste 0,3, seuil de maintien 0,15, persistance 15 images, dilatation 5 % par image perdue, lissage sur 3 images | Seuil unique, boîte rectangulaire sans marge | Reprend les valeurs éprouvées de deface (marge 1,3) et la logique de double seuil des trackers de type ByteTrack. | Adoptée, à ajuster avec le corpus |
| D08 | Rendu MVP par `CanvasOverlay` (masque opaque), puis shader maison `BaseGlShaderProgram` pour mosaïque et flou | Flouter toute l'image avec `GaussianBlur` puis recomposer | L'overlay ne touche pas aux pixels sous-jacents, donc le flou exige un shader. Le MVP opaque livre une première version utile en une semaine. | Adoptée |
| D09 | Modèles embarqués dans `assets/`, aucun téléchargement au build ni à l'exécution | Script `download_models.gradle` de l'exemple MediaPipe | Build reproductible, exigence F-Droid, fonctionnement hors ligne garanti. | Adoptée |
| D10 | Aucune permission `INTERNET`, aucune télémétrie, aucun service tiers | Rapport de plantage en ligne, analytics | L'application traite des données personnelles ; l'absence de réseau est la garantie la plus simple à auditer. | Adoptée |
| D11 | Passe de contrôle obligatoire : le détecteur est relancé sur la vidéo produite ; tout visage résiduel est signalé et bloque l'export automatique | Faire confiance à la première passe | Une seule image non masquée suffit à identifier quelqu'un ; le double contrôle est la parade la moins coûteuse. | Adoptée |
| D12 | Licence de l'application : GPL-3.0-or-later | Apache-2.0, MIT | Copyleft cohérent avec « full libre », compatible avec les dépendances Apache-2.0 et MIT, même licence qu'ObscuraCam dont l'interface sert d'inspiration. | Adoptée |
| D13 | minSdk 24 (Android 7.0), targetSdk 35, compileSdk 35 | minSdk 21 | minSdk 24 est celui de l'exemple MediaPipe ; targetSdk 35 est requis pour les publications récentes. | Adoptée |
| D14 | Publication : APK signé dans les releases GitHub, puis F-Droid ; Google Play exclu de la version 1 | Google Play | Pas d'usage commercial, pas de compte développeur payant, F-Droid vérifie la liberté de la chaîne. | Adoptée |
| D15 | Outils écartés définitivement : DefaceIT (sans licence, ML Kit), FaceBlurApp (sans licence, ML Kit), blurfacefree (vitrine commerciale), understand-ai/anonymizer (archivé), FFmpegKit (retiré) | | Voir [android-apk.md](android-apk.md) et [analyse-audit-et-plan.md](analyse-audit-et-plan.md). | Adoptée |
| D16 | Côté desktop, deface sert d'outil de transition et de référence de non-régression | | Voir [analyse-audit-et-plan.md](analyse-audit-et-plan.md), section 5. | Adoptée |

---

## 4. Architecture cible

### 4.1 Vue d'ensemble

```
Sélection vidéo (SAF, MediaStore)
        │
        ▼
┌───────────────────────── Passe 1 : analyse ─────────────────────────┐
│ Décodage MediaCodec en résolution réduite (largeur 960 par défaut)  │
│        │                                                            │
│        ▼                                                            │
│ Détecteur (interface FaceDetector) : MediaPipe BlazeFace par défaut │
│        │                                                            │
│        ▼                                                            │
│ Tracker : association IoU, double seuil, persistance, lissage       │
│        │                                                            │
│        ▼                                                            │
│ Timeline JSON (pistes, images clés, origine det / hold / manual)    │
└─────────────────────────────────────────────────────────────────────┘
        │
        ▼
Écran de revue (optionnel) : aperçu, prolongation d'un masque, région manuelle
        │
        ▼
┌───────────────────────── Passe 2 : rendu ───────────────────────────┐
│ Media3 Transformer : EditedMediaItem + Effects([MaskEffect])        │
│   MVP : OverlayEffect(CanvasOverlay) → ellipses opaques             │
│   V2  : MaskShaderProgram → mosaïque ou flou dans les ellipses      │
│ Sortie MP4 H.264, audio copié, écriture MediaStore Movies/blurr     │
└─────────────────────────────────────────────────────────────────────┘
        │
        ▼
Passe de contrôle : détecteur relancé sur la sortie → rapport, blocage si résidu
```

### 4.2 Modules Kotlin

| Module | Responsabilité | Dépendances |
|---|---|---|
| `core/detect` | Interface `FaceDetector { fun detect(frame: Bitmap, tMs: Long): List<Detection> }`, implémentations `MediaPipeDetector`, `YuNetDetector` (phase 4), `TiledDetector` (découpe en tuiles) | tasks-vision, opencv |
| `core/track` | `Tracker` : IoU, double seuil, persistance, lissage ; produit des `Track` | aucune |
| `core/timeline` | Modèle `Timeline`, sérialisation JSON (kotlinx.serialization), interpolation entre images clés | kotlinx-serialization |
| `core/render` | `MaskOverlay : CanvasOverlay`, `MaskShaderProgram : BaseGlShaderProgram`, `Renderer` qui pilote Transformer | media3-transformer, media3-effect |
| `core/verify` | Relance le détecteur sur la sortie, produit un `VerificationReport` | core/detect |
| `app` | Compose : sélection, progression, réglages, revue, résultat ; `WorkManager` pour le traitement en arrière-plan | androidx |

### 4.3 Format de la timeline

```json
{
  "version": 1,
  "source": { "sha256": "…", "width": 1920, "height": 1080, "fps": 29.97, "duration_ms": 61234 },
  "params": {
    "detector": "blazeface_full_range", "analysis_width": 960,
    "thresh_new": 0.3, "thresh_keep": 0.15, "hold_frames": 15,
    "mask_scale": 1.3, "mode": "mosaic"
  },
  "tracks": [
    { "id": 1, "keyframes": [
        { "t_ms": 0,  "cx": 0.42, "cy": 0.31, "rx": 0.05, "ry": 0.07, "src": "det" },
        { "t_ms": 33, "cx": 0.43, "cy": 0.31, "rx": 0.05, "ry": 0.07, "src": "hold" }
    ] }
  ]
}
```

Règles : coordonnées normalisées par la largeur et la hauteur de la source ; `rx` et `ry` incluent déjà la marge ; `src` vaut `det` (détection), `hold` (persistance) ou `manual` (ajout par l'utilisateur). Le rendu interpole linéairement entre deux images clés.

### 4.4 Algorithme de suivi

```
pour chaque image (t) :
    dets = detecteur.detect(image)                       # boîtes + scores, résolution d'analyse
    candidats = dets filtrés à score ≥ thresh_keep
    associer candidats ↔ pistes actives par IoU décroissant (IoU ≥ 0,3)
    pour chaque piste associée : mettre à jour la boîte (lissage sur 3 images), age = 0
    pour chaque candidat non associé avec score ≥ thresh_new : créer une piste
    pour chaque piste non associée :
        age += 1
        si age > hold_frames : fermer la piste
        sinon : boîte = dilater(boîte, 1,05) ; émettre une image clé src = "hold"
    pour chaque piste active : émettre une image clé (cx, cy, rx * mask_scale, ry * mask_scale)
```

Tests unitaires prévus : séquence synthétique avec un visage qui disparaît 10 images (le masque doit tenir), deux visages qui se croisent (pas d'échange de masque qui laisse un trou), détection isolée sous le seuil de création (pas de piste créée).

### 4.5 Paramètres exposés à l'utilisateur

| Paramètre | Défaut | Plage | Visible |
|---|---|---|---|
| Mode de masque | mosaïque | opaque, mosaïque, flou | Oui |
| Marge | 1,3 | 1,0 à 2,0 | Oui |
| Sensibilité (seuil de création) | 0,3 | 0,1 à 0,6 | Oui, libellé « plus de visages / moins de faux positifs » |
| Persistance | 15 images | 0 à 60 | Avancé |
| Détecteur | BlazeFace full-range | short-range, full-range, YuNet, CenterFace | Avancé |
| Largeur d'analyse | 960 | 480 à 1920 | Avancé |
| Délégué | GPU si disponible | CPU, GPU | Avancé |
| Codec de sortie | H.264 | H.264, H.265 | Avancé |

---

## 5. Structure du dépôt

```
blurr/
  README.md
  LICENSE                      # GPL-3.0-or-later (D12)
  docs/                        # ce plan et les analyses
  android/
    settings.gradle.kts
    gradle/libs.versions.toml  # versions figées (section 6)
    app/                       # module application (Compose, WorkManager)
    core/                      # modules detect, track, timeline, render, verify
    models/                    # blaze_face_short_range.tflite, blaze_face_full_range.tflite, face_detection_yunet_2023mar.onnx, LICENSES
    fastlane/metadata/android/ # fr-FR, en-US : description, captures, changelogs
  eval/
    corpus/                    # hors git : vidéos et annotations
    measure.py                 # fuite, rappel, faux positifs à partir d'une timeline JSON
  .github/workflows/android.yml
```

---

## 6. Chaîne d'outils et versions figées

| Composant | Version | Source |
|---|---|---|
| Android Gradle Plugin | 8.11.0 | exemple MediaPipe |
| Kotlin | 2.1.0 | exemple MediaPipe |
| JDK | 17 | |
| compileSdk / targetSdk / minSdk | 35 / 35 / 24 | D13 |
| com.google.mediapipe:tasks-vision | 1.1.0 | Google Maven, 06/10/2026 |
| androidx.media3 (transformer, effect, common) | 1.11.1 | Google Maven, 10/09/2026 |
| org.opencv:opencv (phase 4) | 5.0.0 | Maven Central, 21/07/2026 |
| com.microsoft.onnxruntime:onnxruntime-android (phase 4, option) | 1.31.0 | Maven Central, 09/10/2026 |
| Modèles | blaze_face_short_range.tflite (229 746 octets), blaze_face_full_range.tflite (1 083 786 octets), face_detection_yunet_2023mar.onnx (232 589 octets) | bucket mediapipe-models, opencv_zoo |

Toute montée de version passe par une PR dédiée avec exécution du corpus.

---

## 7. Phases, étapes et livrables

Les efforts sont indicatifs pour une personne à temps plein.

### Phase 0 : mise en place (2 jours)

Étapes :

1. Créer `android/` et `LICENSE` (GPL-3.0-or-later), ajouter le fichier `NOTICE` qui crédite l'exemple MediaPipe (Apache-2.0).
2. Installer Android Studio, JDK 17, SDK 35 ; vérifier qu'un émulateur API 34 et un appareil physique sont disponibles.
3. Mettre en place la CI GitHub Actions : `assembleDebug`, `lint`, tests unitaires, rapport de licences des dépendances (plugin `com.github.jk1.dependency-license-report` ou équivalent) qui échoue sur toute licence non libre.
4. Constituer le corpus d'évaluation : 10 à 20 extraits de 10 à 30 s filmés au téléphone (intérieur, extérieur, foule, profils, mouvement rapide, faible lumière, 720p et 1080p, 30 et 60 fps, portrait et paysage). Annoter un visage toutes les 5 images avec CVAT ou Label Studio. Le corpus reste hors du dépôt.
5. Écrire `eval/measure.py` : à partir d'une timeline JSON et des annotations, calcule le nombre d'images avec fuite, le rappel et les faux positifs.

Livrables : dépôt structuré, CI verte, corpus annoté, script de mesure.
Critère de sortie : `measure.py` donne un résultat sur une timeline écrite à la main.

### Phase 1 : squelette à partir de l'exemple MediaPipe (semaine 1, 5 jours)

Étapes :

1. Copier `mediapipe-samples/examples/face_detector/android` dans `android/app`, conserver les en-têtes de licence Apache-2.0 des fichiers repris.
2. Monter `tasks-vision` de 1.0.0 à 1.1.0, compileSdk et targetSdk à 35.
3. Supprimer `download_models.gradle` ; placer les deux modèles BlazeFace dans `android/models/` et les référencer comme `assets` (D09).
4. Garder `FaceDetectorHelper` (mode VIDEO, `detectForVideo`, délégué CPU ou GPU) et le fragment galerie ; retirer le fragment caméra.
5. Extraire l'interface `FaceDetector` et l'implémentation `MediaPipeDetector` dans `core/detect`.
6. Remplacer `MediaMetadataRetriever.getFrameAtTime`, qui arrondit à une image clé, par un décodage MediaCodec image par image avec les vrais `presentationTimeUs` (réutiliser `ImageReader` + `MediaCodec` ou `media3-exoplayer` en mode extraction).
7. Afficher les détections sur un aperçu avec une barre de temps.

Livrables : application qui lit une vidéo de la galerie et montre les boîtes de visages sur toute sa durée.
Critère de sortie : sur 3 vidéos du corpus, les boîtes suivent visuellement les visages ; temps d'analyse mesuré et noté.

### Phase 2 : suivi, timeline et premier rendu (semaine 2, 5 jours)

Étapes :

1. Implémenter `core/track` selon l'algorithme 4.4 avec les défauts D07, et ses tests unitaires.
2. Implémenter `core/timeline` : modèle, sérialisation, interpolation, test de référence (fichier JSON attendu).
3. Ajouter Media3 1.11.1. Implémenter `MaskOverlay : CanvasOverlay` qui, pour chaque `presentationTimeUs`, dessine les ellipses opaques interpolées.
4. Implémenter `Renderer` : `EditedMediaItem` avec `Effects(listOf(), listOf(OverlayEffect(listOf(MaskOverlay(timeline)))))`, `Transformer` avec H.264, écoute de la progression, annulation, écriture dans `Movies/blurr` via `MediaStore`.
5. Vérifier que l'audio est copié sans réencodage et que la durée de sortie est égale à l'entrée à une image près.
6. Exécuter le corpus : écrire la timeline, lancer `measure.py`, consigner fuite et rappel.

Livrables : premier MP4 anonymisé, audio présent, timeline JSON exportable.
Critère de sortie : rappel ≥ 0,95 et fuite documentée sur le corpus (l'objectif 0 est visé en phase 4), aucun plantage sur les 20 extraits.

### Phase 3 : mosaïque, flou, réglages, arrière-plan (semaine 3, 5 jours)

Étapes :

1. Implémenter `MaskShaderProgram : BaseGlShaderProgram` : fragment shader recevant jusqu'à 32 ellipses par image en uniformes ; pixelisation (taille de bloc proportionnelle à la hauteur de l'ellipse) et flou multi-passe à l'intérieur de l'ellipse ; repli sur le masque opaque au-delà de 32 ellipses.
2. Écran de réglages Compose selon le tableau 4.5, stockage `DataStore`.
3. Traitement en arrière-plan : `WorkManager` avec service au premier plan, notification de progression, reprise après rotation de l'écran.
4. Gestion des cas : vidéo tournée en portrait (métadonnée de rotation), 60 fps, fréquence variable, HDR (repli SDR avec message).
5. Mesures sur 3 appareils (entrée, milieu, haut de gamme) : durée par minute de 1080p en BlazeFace CPU et GPU, consommation mémoire. Consigner dans `docs/mesures.md`.

Livrables : version utilisable de bout en bout, réglages, mesures.
Critère de sortie : 1 minute de 1080p en moins de 3 minutes sur l'appareil milieu de gamme ; mosaïque et flou validés visuellement sur le corpus.

### Phase 4 : qualité, contrôle et revue (semaine 4, 5 jours)

Étapes :

1. `TiledDetector` : découpe 2 x 2 puis 3 x 3 avec recouvrement de 10 %, fusion par NMS ; activé automatiquement quand la largeur d'analyse dépasse 960.
2. `YuNetDetector` via `org.opencv:opencv:5.0.0` et `FaceDetectorYN` ; option « mode foule ». `CenterFaceDetector` via ONNX Runtime Android si le corpus montre un gain.
3. `core/verify` : relance le détecteur à seuil 0,15 sur la sortie, liste les horodatages avec visage résiduel, bloque l'export automatique (D11) et propose la revue.
4. Écran de revue : timeline avec vignettes, liste des pistes, prolongation d'un masque de N images, ajout d'une région manuelle (rectangle glissé, converti en ellipse, `src = "manual"`), relance du rendu.
5. Test des métadonnées : comparer les atomes MP4 de l'entrée et de la sortie (`exiftool` ou `ffprobe` sur poste) ; retirer toute métadonnée de localisation ou d'appareil si Transformer en copie.
6. Exécuter le corpus complet ; ajuster D07 si nécessaire et documenter les nouvelles valeurs.

Livrables : mode foule, passe de contrôle, écran de revue, rapport de corpus.
Critère de sortie : 0 image avec fuite sur le corpus après passe de contrôle et revue ; rappel ≥ 0,98 ; sortie sans métadonnée source.

### Phase 5 : publication libre (semaine 5, 3 jours)

Étapes :

1. Vérifier la reproductibilité : build depuis un clone propre sans réseau au-delà des dépôts Maven, versions figées, empreintes des modèles consignées dans `android/models/SHA256SUMS`.
2. Métadonnées fastlane fr-FR et en-US, captures d'écran, changelog `1.0.0`.
3. Clé de signature dédiée, stockée hors dépôt ; APK et AAB signés ; release GitHub `v1.0.0` avec empreintes SHA-256.
4. Soumission à F-Droid via une PR sur `fdroiddata`. Si l'AAR `tasks-vision` est refusé comme binaire, basculer le détecteur par défaut sur YuNet (D03) et retirer MediaPipe du build F-Droid via un `productFlavor` `fdroid`.
5. Page de projet : README avec captures, limites connues (profils extrêmes, visages très petits, masques faciaux), procédure de revue.

Livrables : APK publié, dépôt publiable, demande F-Droid ouverte.
Critère de sortie : un tiers reconstruit l'APK à l'identique à partir du tag ; la demande F-Droid passe la vérification automatique.

---

## 8. Stratégie de test et de qualité

| Niveau | Contenu | Outil |
|---|---|---|
| Unitaires | tracker (scénarios 4.4), interpolation de timeline, sérialisation, calcul de marge | JUnit, kotlinx-serialization |
| Instrumentés | détection sur une image de référence (`city.jpg` du dépôt deface, 25 visages attendus à 2 pixels près), rendu Transformer sur une vidéo synthétique de 5 s avec piste audio, vérification durée et présence audio | Émulateur API 34 en CI, appareil physique en local |
| Corpus | fuite, rappel, faux positifs, durée de traitement | `eval/measure.py`, exécuté avant chaque release |
| Licences | aucune dépendance non libre, aucune permission réseau | rapport de licences en CI, test du manifeste |
| Revue manuelle | lecture complète des sorties du corpus par une personne avant chaque release | checklist dans `docs/release.md` |

---

## 9. Jalons

| Jalon | Semaine | Contenu |
|---|---|---|
| J0 | 0 | Dépôt, CI, corpus annoté |
| J1 | 1 | Détection affichée sur une vidéo |
| J2 | 2 | Premier MP4 anonymisé avec audio |
| J3 | 3 | Mosaïque, flou, réglages, arrière-plan, mesures |
| J4 | 4 | Mode foule, passe de contrôle, revue, 0 fuite sur le corpus |
| J5 | 5 | Release 1.0.0, demande F-Droid |

---

## 10. Risques et parades

| Risque | Probabilité | Impact | Parade |
|---|---|---|---|
| BlazeFace rate les petits visages | Élevée | Fuite d'identité | Tuilage (phase 4), YuNet, passe de contrôle, revue |
| Décalage d'horodatage entre analyse et rendu | Moyenne | Masque décalé d'une image | Décodage MediaCodec avec vrais `presentationTimeUs` (phase 1, étape 6), interpolation, test instrumenté |
| API Media3 Effect marquée instable | Moyenne | Casse à la montée de version | Versions figées, test instrumenté du rendu, montée de version par PR dédiée |
| Refus F-Droid de l'AAR MediaPipe | Moyenne | Retard de publication | `productFlavor` `fdroid` avec YuNet uniquement |
| Mémoire insuffisante en 4K sur appareil d'entrée de gamme | Moyenne | Plantage | Analyse en résolution réduite, rendu GL sans copie CPU, message et repli 1080p |
| Vidéos HDR ou Dolby Vision | Faible | Couleurs altérées ou échec | Détection du format, repli SDR annoncé à l'utilisateur |
| Corpus non représentatif | Moyenne | Fausse confiance | Diversité imposée en phase 0, ajout d'extraits à chaque incident signalé |

---

## 11. Backlog après la version 1

- Plaques d'immatriculation : modèle `ego_blur_lp` d'EgoBlur (Apache-2.0) converti en ONNX ou TFLite, derrière l'interface `FaceDetector`.
- Altération de la voix : `AudioProcessor` Media3 de décalage de hauteur, ou coupure audio par plage.
- Traitement par lot d'un dossier.
- Mode « une passe » avec `ByteBufferGlEffect` pour les vidéos courtes.
- Partage de la timeline avec le pipeline desktop : import, export, rendu croisé.
- Caméra en direct avec masquage immédiat (mode LIVE_STREAM de MediaPipe).

---

## 12. Décisions ouvertes

À trancher avant la phase 0 :

1. Nom de l'application et identifiant de paquet (proposition : `blurr`, `org.blurr.android`).
2. Langues de la version 1 au-delà du français et de l'anglais.
3. Gamme d'appareils de référence pour les mesures (trois modèles concrets).
4. Maintien ou non de la piste desktop décrite dans [analyse-audit-et-plan.md](analyse-audit-et-plan.md) en parallèle de l'application Android.
5. Hébergement du corpus d'évaluation (stockage privé, pas dans le dépôt).
