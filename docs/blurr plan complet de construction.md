# blurr : plan complet de construction

Oct 11, 2026 · @moms

Déroulé opérationnel en 5 étapes, avec validations et contrôles de passage : Étapes et contrôles

## 1. Périmètre et prémisses

blurr produit une copie d'une vidéo où chaque visage est masqué, sans réseau et avec des composants sous licence libre. Le livrable final est une application Android ; un outil Python desktop sert de référence et de banc de mesure.

**Prémisses à corriger avant de construire**

- Les documents cités dans la description du projet (`docs/plan-detaille-android.md`, `docs/analyse-audit-et-plan.md`, `docs/README.md`) sont absents du projet. Ce plan part de zéro.
- Flouter n'est pas anonymiser. Un réseau de neurones identifie des visages mosaïqués à plus de 95 % et floutés (flou YouTube) à 57 % sur 40 personnes, contre 2,5 % au hasard ([McPherson et al., 2016](https://arxiv.org/abs/1609.00408)). Le mode par défaut sera un masque opaque ; flou et mosaïque restent des options visuelles.
- Aucun détecteur n'atteint 100 % de rappel. Un visage manqué sur quelques images suffit à l'exposer. Le produit inclut donc un suivi temporel, des marges et une revue manuelle, pas seulement un détecteur.
- « 100 % libre » exclut des briques courantes : les poids pré-entraînés distribués par InsightFace, dépôt de SCRFD, sont réservés à la recherche non commerciale selon la politique générale du projet ([InsightFace](https://libraries.io/pypi/insightface)) ; ML Kit de Google n'est pas libre.
- Il n'y a pas de consensus sur le caractère libre de poids publiés sous MIT mais entraînés sur des données non libres (WIDER FACE). La politique d'inclusion F-Droid ne mentionne pas les modèles ; elle exige une licence valide pour tout asset ([F-Droid](https://f-droid.org/en/docs/Inclusion_Policy/)).

**Hypothèses de travail (à corriger si fausses)** : un développeur, environ 10 h par semaine, à l'aise en Python, débutant en Android/Kotlin.

**Objectifs et critère de vérification**

| Objectif | Critère vérifiable |
| --- | --- |
| Hors ligne | Aucune permission `INTERNET` dans le manifeste fusionné de l'APK |
| Libre | Chaque dépendance et le modèle ont une licence libre inventoriée ; build accepté par F-Droid |
| Couverture des visages | Cible de rappel fixée après la mesure de référence de l'étape 2 (section 7) |
| Fidélité | Résolution, cadence, durée et audio identiques à la source, sauf choix contraire de l'utilisateur |
| Confidentialité de la sortie | Aucune métadonnée de localisation dans le fichier exporté |

**Hors périmètre v1** : plaques d'immatriculation, anonymisation de la voix (seule la suppression de l'audio est proposée), traitement caméra en direct, iOS.

## 2. Architecture cible

Le pipeline tient en deux passes Media3 autour d'un fichier de pistes : la passe 1 détecte, le suivi consolide, l'utilisateur corrige, la passe 2 applique les masques.

&#91;embedded content: architecture · 6 étapes, 1 fichier de pistes\]

Le fichier de pistes est le seul état partagé : le suivi l'écrit, la revue le modifie, l'export le lit. L'outil desktop produit le même format, ce qui permet de comparer les deux implémentations clip par clip.

## 3. Choix techniques

Le socle retenu est YuNet (MIT) via OpenCV pour la détection et Media3 Transformer pour le décodage, l'analyse et le ré-encodage : deux dépendances libres, sans service Google, et une même chaîne de décodage pour les deux passes.

| Brique | Choix | Licence | Raison | Alternative ou exclusion |
| --- | --- | --- | --- | --- |
| Détecteur | [YuNet](https://huggingface.co/opencv/opencv_zoo/blob/d33294bfaec5f2386dab1783e1a4031330645f57/models/face_detection_yunet/README.md) (OpenCV Zoo) | MIT | AP WIDER Face 0,834 / 0,824 / 0,708 (easy / medium / hard) ; visages d'environ 10 à 300 px ; variante à entrée dynamique, multiples de 32 ([2026may](https://huggingface.co/pollen-robotics/face_detection_yunet_2026may)) | À comparer à l'étape 2 : CenterFace (utilisé par deface), BlazeFace full-range. Exclu : SCRFD (poids non commerciaux) |
| Inférence | [OpenCV Android](https://opencv.org/enhanced-opencv-for-android-support-arm-performance-gains/), API [FaceDetectorYN](https://docs.opencv.org/4.12.0/javadoc/org/opencv/objdetect/FaceDetectorYN.html) | [Apache 2.0](https://opencv.org/license/) | Sur Maven Central depuis 4.9.0 ; détection YuNet en un appel (boîte, 5 points, score) | ONNX Runtime si OpenCV DNN est trop lent sur appareil |
| Vidéo | [Media3 Transformer](https://developer.android.com/media/media3/transformer/transformations) | Apache 2.0 | Effets vidéo en programmes GL ; mode analyse sans encodage ; même effet en aperçu via `ExoPlayer.setVideoEffects` | Exclu : FFmpegKit, [officiellement retiré](https://cdn.jsdelivr.net/gh/arthenica/ffmpeg-kit@main/README.md) |
| Suivi | Tracker IoU + Kalman, association des détections faibles façon [ByteTrack](https://github.com/FoundationVision/ByteTrack) | MIT | Récupère les visages partiellement masqués au lieu de les jeter | Réimplémentation courte en Python puis Kotlin, sans dépendance |
| Interface | Kotlin, Jetpack Compose | Apache 2.0 | Standard Android actuel | Aucune |
| Tâche longue | WorkManager + service au premier plan de type `mediaProcessing` | Apache 2.0 | Type créé pour Android 15 ; limite de 6 h par 24 h en arrière-plan ([Android](https://developer.android.com/develop/background-work/services/fg-service-timeout)) | Type `dataSync` sous Android 14 et avant |
| Stockage | Photo Picker en entrée, MediaStore en sortie | Sans objet | Aucune permission de stockage à partir d'Android 10 | Aucune |
| Référence desktop | Python, `cv2.FaceDetectorYN`, ffmpeg en sous-processus | Apache 2.0 / LGPL-GPL | Même modèle que sur Android, donc résultats comparables | deface comme base de comparaison |

**Deux API Media3 à surveiller.** `ExperimentalAnalyzerModeFactory.buildAnalyzer` exécute Transformer sans encodage ni multiplexage ; elle est marquée `@ExperimentalApi` ([source](https://raw.githubusercontent.com/androidx/media/release/libraries/transformer/src/main/java/androidx/media3/transformer/ExperimentalAnalyzerModeFactory.java)). `ByteBufferGlEffect` livre chaque image au CPU à la taille demandée ; elle est marquée `@UnstableApi` ([source](https://raw.githubusercontent.com/androidx/media/release/libraries/effect/src/main/java/androidx/media3/effect/ByteBufferGlEffect.java)). Parade : version Media3 épinglée, accès isolé derrière une interface, chemin de repli MediaCodec.

**Masquage.** Un `GlEffect` maison applique dans un shader une liste d'ellipses reçue par image. Modes : opaque (défaut), mosaïque à gros blocs, flou (avec avertissement). Le même effet sert à l'aperçu et à l'export, donc ce qui est vu en revue est ce qui sera exporté.

**Format pivot.** Un fichier JSON versionné de pistes : métadonnées vidéo, puis pour chaque piste son origine (auto ou manuelle), son état (actif ou non) et ses images-clés `{pts_us, x, y, w, h, score}` en coordonnées normalisées, repère après rotation. Le desktop et Android lisent et écrivent ce même format.

## 4. Étapes 1 et 2 : jeu de test et référence desktop

Les étapes 1 et 2 fixent le détecteur, les réglages et les cibles chiffrées par la mesure, en Python, avant d'écrire une ligne d'Android. Leur sortie est un outil en ligne de commande `blurr-ref`, un rapport de banc d'essai et le format de pistes v1 figé.

**Tâches**

1. Constituer le jeu de test : 20 à 30 clips de 10 à 60 s, filmés avec des personnes consentantes, couvrant profil, petits visages lointains, contre-jour, nuit, flou de bougé, occultations (lunettes, masque, main), foule, plusieurs carnations, vidéo tournée à 90°, cadence variable, HDR.
2. Annoter les visages par pistes dans [CVAT](https://github.com/cvat-ai/cvat) (MIT, auto-hébergé via Docker Compose, export MOT). Annoter aussi les visages partiellement visibles : ce sont eux qui fuient.
3. Mesurer la référence existante : [deface](https://pypi.org/project/deface/) (MIT, CenterFace, seuil 0,2 par défaut, chaque image traitée indépendamment, dernière version 1.5.0 d'octobre 2023).
4. Écrire le pipeline de référence : décodage ffmpeg, YuNet en deux échelles (image réduite pour les grands visages, tuiles chevauchantes à pleine résolution pour les petits), fusion NMS, suivi, marges, masquage, ré-encodage avec copie de l'audio.
5. Écrire le script d'évaluation des métriques de la section 7 contre les annotations CVAT.
6. Lancer les ablations : seuil de score, nombre d'échelles, taille des tuiles, marge spatiale, prolongation temporelle des pistes, détecteur alternatif (CenterFace, BlazeFace full-range).
7. Figer le format de pistes v1 et exporter les détections brutes de chaque clip : elles serviront de tests de non-régression au port Kotlin.

**Point d'attention.** YuNet couvre des visages d'environ 10 à 300 px. Une vidéo 1080p réduite à 640 px de large divise la taille des visages par 3 : un visage de 25 px disparaît. D'où les tuiles, dont le coût de calcul est à mesurer ici, pas à supposer.

**Critère de sortie** : le rapport donne, pour chaque configuration, le rappel par image, la plus longue exposition et la vitesse ; une configuration est choisie et les cibles de la section 7 sont fixées en conséquence.

## 5. Étape 3 : application Android MVP

Le MVP reproduit sur téléphone la configuration choisie à l'étape 2 : importer, analyser, revoir les pistes, exporter. Son critère de sortie est la parité avec `blurr-ref` sur le jeu de test.

**Modules Gradle**

| Module | Contenu | Testé sur |
| --- | --- | --- |
| `:core` | Format de pistes, interpolation, géométrie ; Kotlin pur | JVM |
| `:track` | Port du tracker Python | JVM, contre les détections brutes de l'étape 2 |
| `:detect` | OpenCV, YuNet, tuiles, NMS ; `Processor` de `ByteBufferGlEffect` | Appareil |
| `:render` | `MaskEffect` (GlEffect + shader des ellipses) | Appareil, comparaison d'images |
| `:pipeline` | Transformer en mode analyse puis export ; `Worker` au premier plan ; reprise | Appareil |
| `:app` | Écrans Compose, navigation, réglages | Appareil |

**Écrans** : Import (Photo Picker) ; Analyse (progression, annulation) ; Revue (lecteur avec masques, liste des pistes avec vignette et interrupteur) ; Export (mode de masque, garder ou supprimer l'audio) ; Résultat (ouvrir, partager).

**Tâches**

1. Projet Gradle, `minSdk` 29, aucune permission `INTERNET`, intégration continue avec tests JVM et lint.
2. `:core` et `:track` : port du code Python, tests dorés (mêmes détections en entrée, mêmes pistes en sortie).
3. Export brut : Transformer copie une vidéo sans effet ; vérifier rotation, durée, audio.
4. `:render` : `MaskEffect` avec des pistes écrites à la main ; aperçu ExoPlayer identique à l'export.
5. `:detect` : YuNet sur une image fixe, puis via `ByteBufferGlEffect` dans Transformer en mode analyse ; détections indexées par `presentationTimeUs`.
6. `:pipeline` : enchaînement analyse, suivi, revue, export dans un `Worker` au premier plan.
7. Écrans Compose ; enregistrement des vidéos de sortie dans `Movies/blurr` via MediaStore.
8. Mesure sur trois appareils (entrée, milieu, haut de gamme) et sur le jeu de test complet.

**Règles de conception non négociables**

- La clé temporelle est l'horodatage de présentation, jamais le numéro d'image : les vidéos de téléphone sont souvent à cadence variable.
- Les deux passes passent par Transformer, donc voient les mêmes horodatages et la même orientation.
- Les vidéos HDR sont converties en SDR dans le MVP ; la conservation du HDR attend l'étape 4.
- Les fichiers temporaires restent dans le cache privé de l'application et sont supprimés après export.

**Critère de sortie** : sur le jeu de test, les métriques Android égalent celles de `blurr-ref` à une tolérance fixée d'avance ; export valide sur les trois appareils ; APK sans permission réseau.

## 6. Étape 4 : robustesse

L'étape 4 réduit les fuites résiduelles mesurées à l'étape 3, par ordre d'impact sur la plus longue exposition, puis élargit les formats pris en charge.

| Chantier | Contenu | Gain visé |
| --- | --- | --- |
| Suivi | Association des détections faibles ; interpolation des trous ; prolongation de chaque piste avant son début et après sa fin | Couvrir les images où le détecteur décroche |
| Passe de rattrapage | Nouvelle détection, plus fine et plus lente, sur les seuls segments où une piste s'interrompt | Rappel sur profils et occultations sans ralentir toute la vidéo |
| Revue manuelle | Avance image par image ; zones manuelles par images-clés avec interpolation ; liste des points à risque (pistes coupées, scores faibles) | Corriger ce que l'automatique rate |
| Formats | Conservation du HDR ; 4K ; 60 i/s ; vidéos sans piste audio | Couvrir les fichiers réels des téléphones récents |
| Fiabilité | Sauvegarde des pistes après chaque segment ; reprise après arrêt ou dépassement de la limite de 6 h | Ne jamais perdre une analyse longue |
| Performances | Profilage par module ; réglage de la taille d'analyse et des tuiles par gamme d'appareil | Respecter la cible de vitesse fixée à l'étape 3 |
| Accessibilité et langues | Interface FR et EN ; TalkBack ; tailles de police | Utilisable par tous |

**Arbitrage à éviter** : détecter une image sur k et suivre entre deux accélère le traitement mais crée des fuites sur les mouvements rapides. Ce mode reste optionnel et désactivé par défaut.

## 7. Tests et métriques d'acceptation

La métrique qui décide est la plus longue exposition d'un visage, pas la précision : un faux positif ne coûte qu'un masque inutile, un faux négatif expose une personne.

| Métrique | Définition | Cible proposée (à valider à la fin de l'étape 2) |
| --- | --- | --- |
| Plus longue exposition | Nombre maximal d'images consécutives où une personne annotée est découverte | 0 image pour les visages de face d'au moins 40 px |
| Rappel par image | Part des boîtes annotées couvertes à au moins 90 % par le masque | Au moins 99 % pour les visages d'au moins 20 px |
| Personnes jamais exposées | Part des pistes annotées sans aucune image découverte | À fixer selon la mesure de référence |
| Sur-masquage | Fausses détections par minute de vidéo | Suivi, sans seuil bloquant |
| Vitesse | Temps de traitement divisé par la durée de la vidéo, par appareil | À fixer après mesure à l'étape 3 |
| Fidélité | Résolution, cadence, durée, décalage audio contrôlés par ffprobe | Identiques à la source |
| Métadonnées | Champs de localisation et d'appareil lus par exiftool sur la sortie | Aucun champ de localisation |

Les chiffres de la dernière colonne sont des propositions, non des résultats : aucun n'a encore été mesuré.

**Niveaux de test**

- Unitaires JVM : interpolation, tracker, lecture et écriture du format de pistes.
- Dorés : mêmes détections brutes en entrée de Python et de Kotlin, pistes identiques en sortie.
- Instrumentés sur appareil : analyse et export d'un clip court ; comparaison d'images du masque à une image de référence.
- Corpus de fichiers difficiles : rotation 90 et 270, cadence variable, HDR10 et HLG, 4K 60 i/s, sans audio, fichier tronqué.
- Matrice d'appareils : au moins trois, couvrant Android 10, 13 et 15 ou plus.
- À chaque version : le jeu de test complet passe sur un appareil de référence et le rapport est archivé.

## 8. Distribution, licences, confidentialité

F-Droid est le canal principal, complété par des APK signés publiés avec chaque version. Ses règles imposent un logiciel libre, une chaîne de compilation 100 % libre, des binaires issus de la compilation ou de sources autorisées, et aucune bibliothèque Google Play Services ou Firebase ([politique d'inclusion](https://f-droid.org/en/docs/Inclusion_Policy/)).

**Licences**

- Licence de l'application recommandée : GPL-3.0-or-later. Elle accepte les dépendances MIT et Apache 2.0 et empêche une reprise fermée. ObscuraCam, l'application libre la plus proche, utilise la même ([F-Droid](https://f-droid.org/en/packages/org.witness.sscphase1/)).
- Le fichier du modèle est versionné dans le dépôt avec sa licence MIT, son URL d'origine et son empreinte SHA-256 : provenance vérifiable par F-Droid comme par l'utilisateur.
- Un fichier `THIRD_PARTY.md` liste chaque dépendance, sa version et sa licence ; il est régénéré et contrôlé en intégration continue.
- Le scanner F-Droid tourne en intégration continue dès l'étape 3, pas à la fin.

**Confidentialité**

- Pas de permission réseau, pas de télémétrie, pas de rapport de plantage envoyé.
- Les vidéos et images intermédiaires restent dans le stockage privé et sont effacées après export ou annulation.
- La sortie est vérifiée sans métadonnées de localisation ; le comportement de Transformer sur ce point est à tester, pas à supposer.
- Avant le premier export, l'application indique que la détection automatique peut manquer des visages et que la revue est nécessaire avant publication.

**Positionnement par rapport à l'existant**

| Outil | Plateforme | Vidéo | Licence | Limite constatée |
| --- | --- | --- | --- | --- |
| [ObscuraCam](https://f-droid.org/en/packages/org.witness.sscphase1/) | Android | Oui | GPL-3.0+ | Dernière version 5.0.0-RC-1, ajoutée en juin 2022 |
| [deface](https://pypi.org/project/deface/) | Desktop, ligne de commande | Oui | MIT | Images traitées indépendamment, sans suivi ; dernière version octobre 2023 |
| [PrivacyBlur](https://f-droid.org/packages/de.mathema.privacyblur/) | Android | Non, images seules | MIT | Source plus disponible selon F-Droid |
| [PutMask](https://techpp.com/2026/03/10/putmask-blur-censor-faces-videos-photos/) | Android | Oui, avec suivi | Non indiquée | Version gratuite : filigrane, 540p maximum, conversion en 30 i/s |

Aucun outil libre listé ici ne combine Android, vidéo, suivi temporel et maintenance récente : c'est la place de blurr.

## 9. Calendrier, risques, décisions

Estimation : environ 31 semaines à 10 h par semaine, soit une soumission à F-Droid mi-mai 2027. Ces dates découlent de l'hypothèse de charge de la section 1, pas d'une mesure ; elles seront recalées à chaque jalon.

&#91;embedded content: calendrier · 4 phases, 4 jalons\]

Chaque jalon conditionne l'étape suivante : sans configuration figée en J2, le port Android n'a pas de référence à égaler.

**Risques**

| Risque | Signal d'alerte | Parade |
| --- | --- | --- |
| Rappel insuffisant (petits visages, profils, nuit) | Exposition au-dessus de la cible à l'étape 2 | Tuiles, détecteur secondaire, passe de rattrapage, revue manuelle |
| API Media3 expérimentales modifiées ou retirées | Casse à la montée de version | Version épinglée, interface d'isolement, repli MediaCodec |
| Courbe d'apprentissage Android | Étape 3 au-delà de 14 semaines | Modules JVM d'abord ; partir des exemples Media3 officiels |
| Lenteur sur entrée de gamme | Vitesse au-dessus de la cible | Taille d'analyse adaptée à l'appareil ; traitement en charge |
| Limite de 6 h en arrière-plan (Android 15+) | Analyses longues interrompues | Sauvegarde par segment et reprise |
| HDR et fichiers atypiques | Export en échec ou couleurs fausses | SDR dans le MVP ; corpus de fichiers difficiles |
| Refus ou retard F-Droid | Scanner en échec | Scanner en intégration continue dès l'étape 3 ; provenance du modèle |
| Fausse impression de sécurité | Exports publiés sans revue | Masque opaque par défaut ; revue obligatoire ; avertissement |

**Décisions à prendre**

| Décision | Options | Recommandation | Échéance |
| --- | --- | --- | --- |
| Licence de l'application | GPL-3.0-or-later, Apache-2.0 | GPL-3.0-or-later | Oct 18, 2026 |
| Hébergement du code et intégration continue | GitHub, Codeberg | Dépend de l'extension de « 100 % libre » à l'outillage : Codeberg si oui | Oct 18, 2026 |
| Version Android minimale | 26, 29 | 29 (MediaStore sans permission) | Nov 22, 2026 |
| Mode de masque par défaut | Opaque, mosaïque, flou | Opaque | Nov 22, 2026 |
| Revue obligatoire avant export | Oui, non | Oui | Nov 22, 2026 |
| Cibles chiffrées de la section 7 | Valeurs proposées, valeurs mesurées | Fixées au vu de l'étape 2 | Nov 22, 2026 |

## Sources

- [YuNet, OpenCV Zoo (licence, AP WIDER Face)](https://huggingface.co/opencv/opencv_zoo/blob/d33294bfaec5f2386dab1783e1a4031330645f57/models/face_detection_yunet/README.md)
- [YuNet 2026may, entrée dynamique et plage de tailles](https://huggingface.co/pollen-robotics/face_detection_yunet_2026may)
- [OpenCV FaceDetectorYN, API Java](https://docs.opencv.org/4.12.0/javadoc/org/opencv/objdetect/FaceDetectorYN.html)
- [OpenCV sur Maven Central](https://opencv.org/enhanced-opencv-for-android-support-arm-performance-gains/) ; [licence OpenCV](https://opencv.org/license/)
- [MediaPipe Face Detector (BlazeFace)](https://developers.google.com/edge/mediapipe/solutions/vision/face_detector)
- [InsightFace, licence des modèles](https://libraries.io/pypi/insightface)
- [Media3 Transformer, transformations et effets](https://developer.android.com/media/media3/transformer/transformations)
- [ExperimentalAnalyzerModeFactory, source](https://raw.githubusercontent.com/androidx/media/release/libraries/transformer/src/main/java/androidx/media3/transformer/ExperimentalAnalyzerModeFactory.java) ; [ByteBufferGlEffect, source](https://raw.githubusercontent.com/androidx/media/release/libraries/effect/src/main/java/androidx/media3/effect/ByteBufferGlEffect.java)
- [Android, délai des services au premier plan](https://developer.android.com/develop/background-work/services/fg-service-timeout)
- [FFmpegKit, README (retrait)](https://cdn.jsdelivr.net/gh/arthenica/ffmpeg-kit@main/README.md)
- [ByteTrack](https://github.com/FoundationVision/ByteTrack) ; [CVAT](https://github.com/cvat-ai/cvat)
- [F-Droid, politique d'inclusion](https://f-droid.org/en/docs/Inclusion_Policy/)
- [McPherson, Shokri, Shmatikov, Defeating Image Obfuscation with Deep Learning (2016)](https://arxiv.org/abs/1609.00408)
- [deface](https://pypi.org/project/deface/) ; [ObscuraCam](https://f-droid.org/en/packages/org.witness.sscphase1/) ; [PrivacyBlur](https://f-droid.org/packages/de.mathema.privacyblur/) ; [PutMask (TechPP)](https://techpp.com/2026/03/10/putmask-blur-censor-faces-videos-photos/)
