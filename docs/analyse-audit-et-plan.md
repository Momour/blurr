# Floutage de visages sur vidéo : analyse critique de l'audit, choix de la solution et plan de mise en place

Date : 9 octobre 2026
Contexte : dépôt `blurr` vide (un README), Codespace Linux x86_64, 2 vCPU, 7,8 Go de RAM, pas de GPU, Python 3.14.2, `ffmpeg` non installé, Docker disponible.

Toutes les affirmations ci-dessous ont été vérifiées le 9 octobre 2026 via l'API GitHub, PyPI, les README des dépôts, et des exécutions réelles sur ce Codespace (voir section 4).

---

## 1. Verdict en bref

- L'audit initial est globalement bien structuré et identifie le bon enjeu (la stabilité temporelle du masquage), mais il contient **trois erreurs importantes** et **plusieurs omissions** qui changent le classement.
- **DefaceIT, classé n°2, est à écarter** : aucune licence (donc non réutilisable légalement), 39 stars, et le code n'utilise pas YOLOv11 pour les visages mais MediaPipe ; le mode « plaques » utilise un modèle COCO générique qui n'a pas de classe « plaque ».
- **deface reste la meilleure brique prête à l'emploi** (MIT, CenterFace, audio conservé, testé fonctionnel ici), mais le projet est dormant depuis fin 2023 et il travaille image par image sans suivi temporel.
- **Solution retenue** : construire `blurr` comme un pipeline maison léger à licences permissives, qui réutilise les composants éprouvés de deface (CenterFace en ONNX Runtime) et y ajoute ce qui manque pour le RGPD : suivi temporel ByteTrack, persistance du masque, marge de sécurité, journal d'audit. deface sert de solution de transition immédiate et de référence de non-régression.

---

## 2. Vérification de l'audit

### 2.1 Tableau de vérification

| Affirmation de l'audit | Statut | Réalité constatée |
|---|---|---|
| deface : ~1 600 stars, MIT | Exact | 1 590 stars, MIT |
| deface : « actif et très mature » | **Partiellement faux** | Mature, mais dormant : dernière release PyPI 1.5.0 le 15/10/2023, dernier push le 13/10/2024, 42 issues ouvertes. Le README sur GitHub documente des options absentes de la version pip (`--disable-progress-output`). |
| deface : `pip install deface` suffit | **Incomplet** | Sur un serveur sans affichage, `opencv-python` échoue (`libGL.so.1` manquant) : il faut `opencv-python-headless` ou `libgl1`. ONNX Runtime n'est pas installé par défaut (repli sur OpenCV DNN, même vitesse mesurée). L'extra `deface[cuda]` pointe sur un paquet `onnxruntime-cuda` qui n'existe pas sur PyPI (le bon est `onnxruntime-gpu`). |
| DefaceIT : « licence open-source » | **Faux** | Aucun fichier LICENSE dans le dépôt. Par défaut, tous droits réservés : utilisation, modification et redistribution non autorisées. |
| DefaceIT : « YOLOv11 visages + plaques » | **Faux** | Le code (`video_blur_core.py`) utilise MediaPipe FaceDetection (BlazeFace) pour les visages quand mediapipe est installé (il est dans `requirements.txt`). Pour les plaques, sans modèle fourni, il charge `yolo11n.pt` (COCO), qui n'a pas de classe « plaque » : il floute alors toute boîte détectée (personnes, voitures, etc.) avec 10 % de marge. |
| DefaceIT : « dépôt en forte progression » | **Faux** | 39 stars, 6 forks, 21 commits, dernier push le 04/01/2026. |
| EgoBlur : ~290 stars, Apache 2.0 | Exact | 289 stars, Apache-2.0, actif (push du 11/06/2026). |
| EgoBlur : « téléchargement manuel des poids, GPU recommandé » | Exact | Poids à télécharger sur projectaria.com. Le paquet PyPI `egoblur` 2.0.1 impose Python 3.10 à 3.12 (donc pas Python 3.14). Gestion audio non documentée. Les seuils Gen2 sont calibrés par caméra Aria. |
| DashcamCleaner : licence GPL-3.0 | **Inexact** | GitHub détecte AGPL-3.0, le README dit MIT : conflit à lever avant tout usage. Dormant (dernier push 27/04/2024). Modèle entraîné pour les routes allemandes. |
| DashcamCleaner : pas de suivi temporel | **Omission** | Il possède une option « blur memory » (`-bm`, 0 à 10 frames) qui réapplique les zones détectées sur les frames précédentes. C'est exactement la parade au scintillement que l'audit réclame. |
| understand-ai/anonymizer : « référence historique pour benchmarks » | **Trompeur** | Dépôt archivé depuis 2022. À retirer de la liste. |
| blurfacefree : « outil récent » | **À retirer** | 6 stars, licence non standard, dépôt vitrine d'un service payant (freefaceblur.com). |
| OpenScrub : cité en passant | **Sous-estimé** | 16 stars mais Apache-2.0, actif (push 29/09/2026), YuNet/CenterFace/SCRFD, suivi des visages avec comblement des trous jusqu'à 4 s, revue humaine, rapport d'audit avec SHA-256. Seul outil clé en main qui traite le scintillement. Projet mono-contributeur, lourd (OCR, spaCy). |
| Pipeline YOLOv8/v11-Face + ByteTrack « recommandé » | **Risque de licence omis** | `ultralytics` est AGPL-3.0. Les dépôts de poids YOLO-face sont GPL-3.0 (akanametov/yolo-face, derronqi/yolov8-face). Incompatible avec un usage SaaS ou un produit fermé sans licence commerciale. |
| MediaPipe « > 100 fps » | **Non qualifié** | Aucune résolution ni matériel indiqués. Le modèle « full range » est prévu pour des visages à moins de 5 m, peu adapté aux foules. |
| Tailles d'installation (20 Mo, 800 Mo, 1,5 Go) | Non vérifiables | Aucune source. Ordres de grandeur plausibles seulement. |
| Sections 5 (guide de décision) et 6 (prise en main) | **Vides** | Les titres existent, le contenu est absent. |

### 2.2 Ce que l'audit a bien vu

- Le scintillement (visage non détecté sur une ou deux frames) est la faille principale d'un floutage image par image. Confirmé par l'issue ouverte n°66 de deface (« faces in videos are visible when they move head »).
- Une marge de masque de 1,3 est un bon défaut (deface l'applique).
- L'audio et les métadonnées sont des canaux d'identification à traiter.

### 2.3 Ce qui manquait

- Aucune mesure de vitesse ni test d'installation. La section 4 ci-dessous les apporte.
- Aucun critère d'acceptation (taux de fuite, recall) ni méthode de contrôle.
- Aucune analyse de licence des briques « sur-mesure ».

---

## 3. État réel des candidats

| Outil | Stars | Licence | Dernière activité | Détecteur | Suivi temporel | Audio | Plaques | Python | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| ORB-HD/deface | 1 590 | MIT | 10/2024 (release pip 10/2023) | CenterFace (ONNX) | Non | Oui (`-k`) | Non | ≥ 3.8, fonctionne en 3.14 | **Solution de transition et référence** |
| austinmabry/OpenScrub | 16 | Apache-2.0 | 09/2026 | YuNet, CenterFace, SCRFD | Oui, trous comblés jusqu'à 4 s | Oui, mutes et bips | Optionnel | pip ou Docker | Intéressant pour une revue humaine, trop lourd et trop jeune pour un socle |
| facebookresearch/EgoBlur | 289 | Apache-2.0 | 06/2026 | CNN Meta (face + plaque) | Non | Non documenté | Oui | 3.10 à 3.12 | Détecteur de contrôle ou option GPU |
| tfaehse/DashcamCleaner | 156 | AGPL-3.0 (conflit README) | 04/2024 | YOLOv8 custom | Oui (`-bm`) | Oui | Oui | ≥ 3.8 | Écarté : licence floue, dormant, routes allemandes |
| therealaleph/DefaceIT | 39 | Aucune | 01/2026 | MediaPipe (visages), COCO (plaques) | Non | Oui + pitch | Non réel | ≥ 3.8 | **Écarté** |
| understand-ai/anonymizer | 276 | Apache-2.0 | Archivé 2022 | Faster R-CNN | Non | Non | Oui | ancien | Écarté |
| Teylersf/blurfacefree | 6 | Non standard | 05/2026 | Non vérifié | Non vérifié | Non vérifié | Non | binaire | Écarté |
| OpenCV YuNet | (OpenCV) | Apache-2.0 | 2023 (modèle) | YuNet, 230 Ko | À construire | À construire | Non | cv2 ≥ 4.5.4 | **Brique retenue (mode rapide)** |
| CenterFace (via deface) | (deface) | MIT | 2019 (modèle) | CenterFace, 7 Mo | À construire | À construire | Non | ONNX Runtime | **Brique retenue (mode qualité)** |
| Ultralytics YOLO + yolo-face | 962 (yolo-face) | AGPL-3.0 + GPL-3.0 | 09/2026 | YOLOv8/11 face | ByteTrack intégré | À construire | Oui (modèles tiers) | ≥ 3.8 | Écarté sauf usage interne non distribué |
| roboflow/supervision | (lib) | MIT | actif | n/a | ByteTrack | n/a | n/a | ≥ 3.10 | **Brique retenue (suivi)** |

---

## 4. Mesures réalisées sur ce Codespace

Conditions : 2 vCPU, pas de GPU, vidéo de test 1280x720, 25 fps, 5 s (125 frames), générée à partir de l'image `examples/city.jpg` du dépôt deface (foule, environ 19 visages par frame) avec une piste audio. L'image étant fixe, ces mesures évaluent le débit, pas le scintillement.

| Test | Résultat | Remarque |
|---|---|---|
| `pip install deface` sur Python 3.14 | Échec puis succès | Échec initial `libGL.so.1`, corrigé par `opencv-python-headless` |
| deface sur image 720p, CPU | 0,9 s | 25 visages détectés, scores de 0,22 à 0,89 avec seuil 0,2 |
| deface vidéo 720p, ONNX Runtime CPU, `--keep-audio` | 36,1 s, soit 3,5 fps | Audio AAC conservé, sortie H.264 |
| deface vidéo, `--scale 640x360` | 12,8 s, soit 9,7 fps | 2,8 fois plus rapide, recall sur petits visages à vérifier |
| deface vidéo, backend OpenCV DNN | 35,4 s | Identique à ONNX Runtime sur CPU |
| deface vidéo, mosaïque + `--keep-metadata` | 34,9 s | Fonctionne |
| YuNet (OpenCV 5.0) détection seule, 720p | 17,3 fps | 19 visages par frame, sans floutage ni encodage |

Lecture : sur 2 vCPU, une minute de vidéo 720p dense prend environ 7 minutes avec deface en pleine résolution. YuNet est environ 4 à 5 fois plus rapide en détection pure, au prix d'un recall plus faible sur les petits visages (d'après les chiffres WIDER FACE publiés par les auteurs : YuNet environ 0,89 / 0,87 / 0,77 contre CenterFace environ 0,93 / 0,92 / 0,87 sur easy / medium / hard).

---

## 5. Choix de la solution

### 5.1 Critères de décision

1. Aucun visage visible sur aucune frame (exigence RGPD), donc suivi temporel et persistance obligatoires.
2. Licences permissives de bout en bout (pas d'AGPL ni de GPL) pour garder la liberté de distribuer ou d'exposer en service.
3. Fonctionne sur CPU, accélérable sur GPU sans réécriture.
4. Dépendances maintenues, sans projet mono-contributeur en point unique de défaillance.
5. Traçabilité : paramètres, détections et empreintes des fichiers conservés pour prouver le traitement.

### 5.2 Pourquoi pas les alternatives

- **deface seul** : remplit 2 et 3, échoue sur 1 (pas de suivi, issue n°66) et 4 (dormant). Ses briques sont bonnes, son enveloppe est figée.
- **OpenScrub** : remplit 1, 2, 5 mais échoue sur 4 (un contributeur, 16 stars, « best-effort, not a compliance guarantee ») et embarque OCR, NER et transcription inutiles ici.
- **Ultralytics + yolo-face + ByteTrack** : la meilleure précision, mais AGPL-3.0 et GPL-3.0. Acceptable uniquement pour un traitement interne jamais distribué ni exposé en réseau.
- **EgoBlur** : excellent détecteur, mais Python ≤ 3.12, audio non géré, seuils calibrés pour les caméras Aria. À garder comme détecteur de contrôle indépendant.

### 5.3 Solution retenue : `blurr`, pipeline maison à licences permissives

| Composant | Choix | Licence | Rôle |
|---|---|---|---|
| Détecteur qualité | CenterFace (fichier `centerface.onnx` de deface) via ONNX Runtime | MIT / MIT | Mode par défaut, meilleur recall sur petits visages |
| Détecteur rapide | YuNet via `cv2.FaceDetectorYN` | Apache-2.0 | Mode prévisualisation et flux temps réel |
| Suivi | `supervision.ByteTrack` | MIT | Identifiants stables, comblement des pertes de détection |
| Persistance | Code maison : garder la dernière boîte d'une piste N frames, dilatée progressivement | MIT (nous) | Supprime le scintillement |
| Masquage | Flou gaussien, mosaïque ou aplat, masque elliptique, marge 1,3 par défaut | MIT (nous) | Même rendu que deface |
| Entrée / sortie | FFmpeg via `imageio-ffmpeg` (binaire fourni) | Binaire GPL appelé en processus séparé | Décodage, encodage H.264/H.265, remux audio, purge des métadonnées |
| Journal d'audit | JSON par vidéo : paramètres, détections par frame, SHA-256 entrée et sortie | MIT (nous) | Preuve de traitement |
| Contrôle qualité | Second détecteur indépendant (EgoBlur ou YuNet à seuil bas) exécuté sur la sortie | Apache-2.0 | Compte les visages résiduels, bloque la livraison si > 0 |

Architecture :

```
vidéo source ──> FFmpeg (décodage, frames BGR) ──> détecteur (CenterFace ou YuNet)
                                                        │
                                                        v
                                              ByteTrack + persistance N frames
                                                        │
                                                        v
                                         masque elliptique dilaté (x1.3) + flou
                                                        │
                                                        v
            FFmpeg (encodage H.264, remux audio, -map_metadata -1) ──> vidéo anonymisée
                                                        │
                                                        v
                                    contrôle : second détecteur sur la sortie
                                                        │
                                                        v
                                         journal d'audit JSON + SHA-256
```

Pourquoi cette solution est « la meilleure » et pas seulement « une de plus » : elle garde tout ce qui est prouvé dans deface (modèle, marge, pipeline FFmpeg) et n'ajoute que les 200 à 400 lignes qui manquent pour le RGPD, sans dette de licence et sans dépendre d'un projet dormant.

---

## 6. Plan de mise en place

### Phase 0 : transition immédiate et base de mesure (jour 0 à jour 2)

Objectif : pouvoir anonymiser dès aujourd'hui et disposer d'un corpus pour mesurer.

1. Installer deface dans un environnement isolé (commandes validées sur ce Codespace) :

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install deface onnxruntime opencv-python-headless
pip uninstall -y opencv-python          # évite l'erreur libGL.so.1 sans affichage
deface entree.mp4 -o sortie.mp4 --keep-audio --keep-metadata --mask-scale 1.3 --thresh 0.2
deface entree.mp4 -o sortie.mp4 --keep-audio --scale 960x540   # 2 à 3 fois plus rapide
```

2. Constituer un corpus d'évaluation de 10 à 20 extraits de 10 à 30 s représentatifs des cas réels (intérieur, extérieur, foule, profils, mouvement rapide, faible lumière, 720p et 1080p). Annoter les visages toutes les 5 frames avec CVAT ou Label Studio, ou pseudo-annoter avec EgoBlur sur GPU puis corriger à la main.
3. Fixer les critères d'acceptation :
   - fuite : 0 frame où un visage annoté est couvert à moins de 90 % par le masque ;
   - recall par frame ≥ 0,98 sur le corpus ;
   - débit minimal : 1 minute de 1080p traitée en moins de 10 minutes sur 4 vCPU.
4. Mesurer deface sur ce corpus : c'est la référence à battre.

Livrables : script `eval/measure.py`, corpus annoté hors dépôt, rapport de référence.

### Phase 1 : MVP du pipeline (semaine 1)

Objectif : reproduire deface dans `blurr`, avec une architecture modulaire.

Arborescence cible :

```
blurr/
  pyproject.toml              # dépendances : onnxruntime, opencv-python-headless, numpy, imageio-ffmpeg, supervision
  src/blurr/
    cli.py                    # blurr entree.mp4 -o sortie.mp4 [--detector centerface|yunet] [--thresh] [--mask-scale] [--hold] [--mode blur|mosaic|solid]
    detectors/base.py         # interface : detect(frame) -> boîtes xyxy + scores
    detectors/centerface.py   # ONNX Runtime, prétraitement identique à deface
    detectors/yunet.py        # cv2.FaceDetectorYN
    masking.py                # masque elliptique, marge, flou / mosaïque / aplat
    video_io.py               # lecture frames, écriture, remux audio, purge métadonnées
  tests/                      # image de référence, vidéo synthétique, tests de non-régression
  eval/measure.py
  Dockerfile
```

Tâches :
1. Porter le détecteur CenterFace (reprendre `centerface.py` et le fichier ONNX de deface, licence MIT, en citant l'origine).
2. Implémenter YuNet comme second détecteur derrière la même interface.
3. Implémenter le masquage elliptique avec marge, puis la boucle vidéo avec FFmpeg et remux audio.
4. Test de non-régression : sur l'image `city.jpg`, obtenir les mêmes boîtes que deface à 2 pixels près.

Critère de sortie : score identique à deface sur le corpus de la phase 0, même débit à 10 % près.

### Phase 2 : suivi temporel et persistance (semaine 2)

Objectif : supprimer les fuites de frames.

1. Brancher `supervision.ByteTrack` sur les détections de chaque frame. Paramètres de départ : `track_activation_threshold=0.2`, `lost_track_buffer=fps` (1 s), `minimum_matching_threshold=0.8`.
2. Persistance : pour chaque piste perdue, réappliquer la dernière boîte pendant `--hold` frames (défaut : 15, soit 0,5 s à 30 fps), en la dilatant de 5 % par frame pour couvrir le mouvement.
3. Lissage : moyenne glissante sur 3 frames des coordonnées de chaque piste, pour éviter les masques qui tremblent.
4. Seuil adaptatif : seuil de détection à 0,2 pour créer une piste, 0,1 pour la maintenir (le suivi tolère des détections faibles sans créer de faux positifs isolés).
5. Mesurer sur le corpus : fuites, recall, faux positifs. Ajuster `--hold` et la dilatation.

Squelette de la logique :

```python
import supervision as sv
tracker = sv.ByteTrack(track_activation_threshold=0.2, lost_track_buffer=fps,
                       minimum_matching_threshold=0.8, frame_rate=fps)
last_seen = {}  # track_id -> (boîte, frames_depuis_vue)
for frame in frames:
    boxes, scores = detector.detect(frame)
    tracks = tracker.update_with_detections(sv.Detections(xyxy=boxes, confidence=scores))
    seen = set()
    for box, tid in zip(tracks.xyxy, tracks.tracker_id):
        last_seen[tid] = (box, 0); seen.add(tid)
    for tid, (box, age) in list(last_seen.items()):
        if tid in seen: continue
        if age >= hold: del last_seen[tid]; continue
        last_seen[tid] = (dilate(box, 1.05), age + 1)
    for box, _ in last_seen.values():
        frame = mask(frame, box, scale=1.3, mode=mode)
```

Critère de sortie : 0 fuite sur le corpus, recall ≥ 0,98, débit dégradé de moins de 15 % par rapport à la phase 1.

### Phase 3 : contrôle qualité, performance et packaging (semaine 3)

1. Contrôle par second détecteur : exécuter EgoBlur (dans un conteneur Python 3.12) ou YuNet à seuil 0,3 sur la vidéo de sortie ; tout visage résiduel fait échouer le traitement et produit un rapport. Option `--verify`.
2. Performance CPU : inférence sur frame réduite (`--scale`, comme deface) avec reprojection des boîtes sur la pleine résolution, threads ONNX Runtime réglés sur le nombre de cœurs, lecture et encodage dans des processus séparés.
3. Performance GPU : `onnxruntime-gpu` (CUDA) ou `onnxruntime-directml`, sélection automatique du fournisseur d'exécution, sans changement de code.
4. Packaging : `pip install .` avec entrée `blurr`, image Docker CPU (base `python:3.12-slim` + `libgl1` ou headless) et variante CUDA, traitement par lot d'un dossier.
5. Plaques d'immatriculation (optionnel, selon besoin) : ajouter un détecteur ONNX de plaques derrière la même interface, par exemple le modèle `ego_blur_lp` d'EgoBlur (Apache-2.0).

Critère de sortie : 1 minute de 1080p en moins de 10 minutes sur 4 vCPU, image Docker reproductible, suite de tests verte en CI.

### Phase 4 : durcissement RGPD et documentation (semaine 4)

1. Purge des métadonnées par défaut (`-map_metadata -1`, suppression GPS, dates, nom d'appareil) ; option `--keep-metadata` explicite.
2. Journal d'audit JSON par vidéo : version de `blurr`, détecteur, paramètres, nombre de pistes, nombre de frames masquées par persistance, SHA-256 de l'entrée et de la sortie, résultat du contrôle.
3. Audio : option `--mute` et option de décalage de hauteur via filtre FFmpeg `rubberband` ou `asetrate`, car la voix identifie aussi.
4. Documentation : README, limites connues (visages de profil extrême, masques, très basse résolution), procédure de revue manuelle des cas signalés par le contrôle.
5. Registre des traitements : conserver uniquement les sorties et les journaux, jamais les sources au-delà de la durée nécessaire.

Critère de sortie : revue de conformité interne, procédure documentée, premiers lots traités en production.

---

## 7. Risques et parades

| Risque | Impact | Parade |
|---|---|---|
| Petits visages ou profils non détectés | Fuite d'identité | CenterFace par défaut, seuil bas de maintien, persistance, contrôle par second détecteur, seuil de taille minimale documenté |
| Faux positifs (objets floutés) | Qualité dégradée | ByteTrack élimine les détections isolées, option de seuil de création de piste à 0,3 |
| Dérive des dépendances (deface dormant) | Maintenance | Ne dépendre que du fichier ONNX et de notre code, pas du paquet deface |
| Débit insuffisant sur CPU | Délai de traitement | `--scale`, traitement par lot en parallèle, GPU via ONNX Runtime sans réécriture |
| Licence AGPL introduite par inadvertance | Juridique | Interdire `ultralytics` et `yolo-face` dans `pyproject.toml`, vérification des licences en CI (`pip-licenses`) |
| Python 3.14 trop récent pour certaines roues | Installation | Cibler Python 3.12 dans Docker et la CI, tolérer 3.14 en local |

---

## 8. Dimensionnement matériel

| Machine | Débit attendu 720p (CenterFace, pleine résolution) | 1 minute de vidéo | Statut |
|---|---|---|---|
| Codespace 2 vCPU | 3,5 fps | environ 7 min | Mesuré |
| VM 8 vCPU | 10 à 15 fps | 2 à 3 min | Estimation, à mesurer en phase 3 |
| GPU NVIDIA T4 ou équivalent | plus de 60 fps | moins de 30 s | Estimation, à mesurer en phase 3 |

Avec `--scale 640x360`, multiplier le débit par 2,5 à 3 (mesuré : 9,7 fps sur ce Codespace), à condition de vérifier le recall sur les petits visages.

---

## 9. Sources

- https://github.com/ORB-HD/deface et https://pypi.org/project/deface/ (release 1.5.0, 15/10/2023)
- https://github.com/ORB-HD/deface/issues/66
- https://github.com/facebookresearch/EgoBlur et https://pypi.org/project/egoblur/
- https://github.com/therealaleph/DefaceIT (fichiers `video_blur_core.py`, `requirements.txt`)
- https://github.com/tfaehse/DashcamCleaner
- https://github.com/austinmabry/OpenScrub
- https://github.com/understand-ai/anonymizer (archivé)
- https://github.com/Teylersf/blurfacefree
- https://github.com/akanametov/yolo-face, https://github.com/derronqi/yolov8-face, https://github.com/lindevs/yolov8-face
- https://pypi.org/project/ultralytics/ (AGPL-3.0), https://pypi.org/project/supervision/, https://pypi.org/project/onnxruntime/
- https://github.com/opencv/opencv_zoo (modèle `face_detection_yunet_2023mar.onnx`)
- https://docs.ultralytics.com/modes/track/
