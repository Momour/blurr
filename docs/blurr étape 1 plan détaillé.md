# blurr : étape 1, jeu de test, vérité terrain et mesure de référence

Oct 11, 2026 · déclinaison de la section 4 de [blurr plan complet de construction](blurr%20plan%20complet%20de%20construction.md) · révision 2 (corrections listées en section 8)

## 0. Résumé

L'étape 1 produit ce contre quoi tout le reste sera mesuré : des vidéos de test filmées avec consentement, leur vérité terrain annotée par pistes, un script d'évaluation qui calcule les métriques de la section 7 du plan général, et une première mesure de référence avec deface.

| Élément | Valeur |
| --- | --- |
| Durée estimée | J1 : 8 semaines à 10 h (12 oct. → 6 déc. 2026), 68 h planifiées sur 80, soit 12 h de marge ; J1b : environ 12 h, au plus tard le 20 déc. |
| Poste le plus incertain | Annotation : budget de 30 h au total (20 h développement, 10 h réservés), recalé par le pilote du lot L5 |
| Jalon de sortie | **J1** : clips de développement figés, annotés et audités ; `blurr-ref eval` testé ; rapport deface sur développement archivé. **J1b** : clips réservés annotés, rapport complété |
| Ce qui n'est pas fait ici | Pipeline YuNet, tuiles, suivi, ablations, format de pistes v1 (étape 2) |

J1b est séparé de J1 parce que les clips réservés ne servent qu'au rapport final de l'étape 2 : leur annotation peut chevaucher les deux premières semaines de l'étape 2 sans bloquer le pipeline YuNet. Elle doit être terminée avant tout chiffre publié sur les réservés.

## 1. Périmètre et découpage avec l'étape 2

La section 4 du plan général regroupe les étapes 1 et 2 en 7 tâches. Le découpage retenu :

| Tâche (section 4) | Étape |
| --- | --- |
| 1. Constituer le jeu de test | **1** |
| 2. Annoter dans CVAT | **1** |
| 3. Mesurer deface | **1** |
| 5. Script d'évaluation | **1** (avancé : sans lui, la tâche 3 ne produit aucun chiffre) |
| 4. Pipeline de référence YuNet | 2 |
| 6. Ablations | 2 |
| 7. Figer le format de pistes v1 | 2 |

**Corrections à reporter dans le plan général**

- L'ordre des tâches de la section 4 place le script d'évaluation (5) après la mesure de deface (3). Il faut l'inverser.
- Le plan ne prévoit pas de **séparation développement / test réservé**. Les ablations de l'étape 2 choisiront des réglages au vu des clips : sans clips réservés, les chiffres finaux seront optimistes. Ce plan en réserve un tiers.
- Les vidéos de test et leurs annotations sont des **données personnelles** (visages identifiables). Le plan général n'en traite pas ; le lot L1 s'en charge.
- La cible « 0 image pour les visages **de face** d'au moins 40 px » suppose que la pose soit annotée. Le guide d'annotation (L5) l'impose.
- La section 4 prévoit un export CVAT au format MOT. MOT perd les attributs et l'état `outside` ; le format retenu est « CVAT for video 1.1 » (L5).
- La règle de masque de deface n'est pas « boîte agrandie de 1,3 ». Dans le code, `scale_bb` étend chaque côté de `(mask_scale - 1) × taille`, soit un agrandissement effectif de **1,6** avec le défaut 1,3 (L7).
- Les échéances du 22 nov. 2026 de la section 9 (cibles chiffrées « au vu de l'étape 2 », version Android minimale, mode de masque, revue obligatoire) sont caduques : J1 tombe le 6 déc. Le calendrier général et J2 sont à recaler à la sortie de l'étape 1.

## 2. Prérequis et décisions

| Décision | Options | Recommandation | Échéance | Bloque |
| --- | --- | --- | --- | --- |
| Licence de l'application | GPL-3.0-or-later, Apache-2.0 | GPL-3.0-or-later (plan général) | 18 oct. | Création du dépôt |
| Hébergement du code | GitHub, Codeberg | Codeberg si « 100 % libre » couvre l'outillage | 18 oct. | Création du dépôt |
| Moteur de conteneurs pour CVAT | Docker Desktop, Docker Engine sous WSL2, Podman | Docker Engine sous WSL2 : Docker Desktop n'est pas libre | 18 oct. | Installation de CVAT |
| Emplacement des données Docker (volumes CVAT) | Disque virtuel WSL2 par défaut, data-root sur le volume chiffré, chiffrement du disque entier | Data-root Docker sur le volume chiffré, ou disque entier chiffré (BitLocker ou VeraCrypt) : CVAT garde une copie de toutes les images | 18 oct. | Installation de CVAT |
| Lieux de tournage | Lieux publics, lieux contrôlés | Lieux contrôlés uniquement (cour, salle, jardin privé, rue déserte vérifiée) : aucun tiers non consentant dans le champ | 18 oct. | Tournage |
| Pré-annotation automatique | Aucune, union de détecteurs à seuil bas | Union YuNet + CenterFace à seuil bas, avec garde-fous (L5) | 8 nov. (après le pilote) | Production de l'annotation |
| Visages sur écrans et affiches | Ignorés, annotés à part | Annotés avec `type = image` et comptés à part | 18 oct. | Guide d'annotation |
| Stockage du jeu de test | Disque local chiffré, cloud | Disque local chiffré + une sauvegarde chiffrée hors ligne | 18 oct. | Tournage |

**Matériel** : au moins deux téléphones différents, dont un qui filme en HDR (HDR10 ou HLG) et un Android connu pour produire de la cadence variable en basse lumière. Un PC avec 40 Go libres sur le volume chiffré : environ 12 à 15 Go d'images extraites, autant pour la copie que CVAT conserve dans ses volumes, plus les vidéos de contrôle.

## 3. Lots de travail

Chaque lot se termine par un contrôle de passage : on ne commence pas le lot dépendant tant qu'il n'est pas vert.

### L1 : cadre légal et consentement (≈ 4 h)

**But** : pouvoir filmer, stocker et exploiter les clips sans exposer les participants.

1. Rédiger un formulaire de consentement : finalité (test d'un logiciel de masquage des visages, détection sans reconnaissance), usage interne uniquement, pas de publication des vidéos, droit de retrait à tout moment.
2. Durée de conservation : **tant que l'application est maintenue**, avec revue annuelle et information des participants à chaque revue. Le plan général rejoue le jeu de test à chaque version de l'application ; une durée « fin du projet + 1 an » serait contredite par cet usage.
3. Ajouter une case optionnelle et distincte « autorise l'usage d'un extrait dans un jeu public de non-régression ». Le texte dit explicitement que l'extrait serait publié **avec le visage visible, non masqué**, sous licence libre, pour une durée indéfinie, et que le retrait ne peut pas rappeler les copies déjà distribuées. C'est le seul moyen d'avoir un jour des clips réels dans l'intégration continue d'un dépôt public.
4. Exclure les mineurs du tournage, sauf accord écrit des deux responsables légaux.
5. Tenir un registre `consentements` (hors dépôt) : identifiant de participant, date, clips concernés, options cochées. Les clips ne portent que l'identifiant.
6. Procédure de retrait, qui couvre **tous** les emplacements : `raw/`, `frames/`, la tâche CVAT (suppression de la tâche dans l'interface, puis contrôle du volume `cvat_data`), `annotations/`, `runs/` (masques, rapports, `worst.csv`, vidéos de contrôle), la sauvegarde hors ligne, puis la ligne du manifeste. L'évaluation est relancée ensuite. La procédure est testée sur un clip fictif avant le premier tournage.

**Livrables** : formulaire, registre vide, procédure de retrait d'une page avec la liste des emplacements.
**Contrôle de passage** : formulaire relu par une personne extérieure au projet ; procédure de retrait exécutée sur un clip fictif ingéré, annoté et évalué, sans résidu ; à faire valider juridiquement si le jeu de test doit un jour être partagé.

### L2 : outillage (≈ 8 h)

**But** : un dépôt, un environnement Python reproductible et un CVAT local opérationnels.

1. Créer le dépôt avec la licence décidée, `README.md`, `THIRD_PARTY.md` vide, et `.gitignore` qui exclut tout fichier vidéo et image. Les fixtures de test sont **générées en code** (tableaux numpy) : aucun fichier image dans le dépôt, même synthétique.
2. Créer le projet Python `desktop/` avec uv, Python épinglé, dépendances épinglées dans le fichier de verrouillage : `numpy`, `opencv-python`, `deface`, `pytest`.
3. Installer ffmpeg et ffprobe en version **5.1 ou plus** (`-fps_mode` n'existe pas avant), version notée dans le dépôt, avec le filtre `zscale` ou `libplacebo` pour la conversion HDR ; installer exiftool.
4. Configurer Docker Engine avec `data-root` sur le volume chiffré (ou vérifier que le disque entier est chiffré), puis installer CVAT depuis son dépôt, sur une version publiée épinglée et notée :
   ```powershell
   git clone https://github.com/cvat-ai/cvat
   cd cvat
   git checkout <tag-de-version>
   docker compose up -d
   docker exec -it cvat_server bash -ic "python3 ~/manage.py createsuperuser"
   ```
   Interface sur `http://localhost:8080`, aucune exposition réseau au-delà de la machine.
5. Définir dans CVAT le projet et ses étiquettes : `face` avec les attributs `pose` et `occlusion` **mutables** (valeur par image) et `type` **immuable** (valeur par piste). Qualité d'image des tâches à 95 ou plus : la compression par défaut (70) dégrade les visages de moins de 20 px en 4K.
6. Préparer le volume chiffré `blurr-data/` (structure en section 4.1).

**Arborescence du dépôt à l'issue de l'étape 1**

```
blurr/
  docs/
  desktop/
    pyproject.toml
    uv.lock
    src/blurr_ref/
      ingest.py        # manifeste, empreintes, ffprobe, extraction des images
      gt.py            # CVAT XML -> gt.json ; écriture de CVAT XML pour la pré-annotation
      masks.py         # lecture et écriture de masks.json
      matrix.py        # contrôle de la matrice clips × conditions et de la répartition
      eval/
        coverage.py    # couverture boîte / masques
        metrics.py     # rappel, exposition, sur-masquage
        report.py      # rapport Markdown + JSON
      baselines/
        deface_run.py  # CenterFace de deface sur nos images extraites
      cli.py           # blurr-ref ingest | gt | eval | baseline | check-matrix
    tests/             # fixtures générées en code, aucun fichier image
  dataset/
    manifest.csv       # métadonnées et empreintes, sans aucune image
    conditions.csv     # clip, étiquettes de condition, lot (D ou R)
    annotation-guide.md
```

**Contrôle de passage** : `uv run pytest` passe sur un dépôt neuf cloné ; CVAT ouvre une tâche de test créée à partir de 10 images synthétiques, une piste y est annotée sur 2 images-clés, et l'export « CVAT for video 1.1 » contient bien une boîte par image, les boîtes interpolées portant `keyframe="0"` ; `docker volume inspect cvat_data` pointe sur le volume chiffré ; aucun fichier média n'est suivi par git.

### L3 : matrice de tournage et capture (≈ 8 h, dont tournage)

**But** : 27 clips de 10 à 30 s qui couvrent chaque étiquette de condition au moins deux fois, dont au moins une fois dans les clips réservés.

Des clips de 10 à 30 s plutôt que 60 s : le coût d'annotation est proportionnel à la durée, et la diversité des conditions compte plus que la longueur.

**Étiquettes de condition** (liste fermée, fichier `dataset/conditions.csv`)

| Étiquette | Définition |
| --- | --- |
| `profil` | Au moins une personne en profil ou trois-quarts marqué pendant plus de la moitié du clip |
| `petit` | Visages de moins de 40 px de hauteur à la résolution native |
| `foule` | Au moins 4 personnes simultanément dans le champ |
| `contre-jour` | Source lumineuse principale derrière les sujets |
| `nuit` | Basse lumière, bruit visible |
| `flou` | Flou de bougé de la caméra |
| `rapide` | Mouvement rapide des sujets ou 60 i/s |
| `occultation` | Accessoire, masque ou main devant le visage |
| `sortie-retour` | Sortie du champ, bord du cadre ou croisement de pistes |
| `image` | Visages sur photo, affiche ou écran |
| `rotation-90` | Portrait, rotation 90° dans les métadonnées |
| `rotation-270` | Portrait inversé, rotation 270° |
| `hdr` | Fonction de transfert `smpte2084` ou `arib-std-b67` |
| `vfr` | Cadence variable, constatée à l'ingestion (L4), pas choisie au tournage |
| `zoom` | Changement d'échelle pendant la prise |
| `contraste` | Ombres dures ou éclairage coloré |

Trois étiquettes n'ont qu'une scène dans la matrice (`image`, `rotation-270`, `zoom`) : ces scènes sont filmées en **deux prises distinctes** (lieux ou participants différents), notées a et b, l'une en développement, l'autre réservée. D'où 27 clips.

| ID | Scène | Étiquettes | Pers. | Orientation / format | Lot |
| --- | --- | --- | --- | --- | --- |
| C01 | Deux personnes face caméra, intérieur | (référence facile) | 2 | Paysage, 1080p | D |
| C02 | Conversation en marchant | `profil`, `rotation-90` | 2 | Portrait | D |
| C03 | Rotation lente de la tête 0 → 90° | `profil` | 1 | Paysage | D |
| C04 | Personnes à 5, 10, 20 m | `petit` | 3 | Paysage, 4K | R |
| C05 | Groupe de 8 à 15 volontaires, lieu contrôlé | `foule`, `petit` | 8–15 | Paysage, 4K | D |
| C06 | Devant une fenêtre ensoleillée | `contre-jour`, `hdr` | 2 | Paysage, HDR | D |
| C07 | Rue déserte de nuit, éclairage public | `nuit`, `rotation-90`, `vfr` attendu | 2 | Portrait | D |
| C08 | Intérieur faiblement éclairé | `nuit`, `vfr` attendu | 2 | Paysage | D |
| C09 | Caméra tenue en courant | `flou`, `rotation-90` | 2 | Portrait | D |
| C10 | Personne qui passe vite devant la caméra | `rapide` | 1–2 | Paysage, 60 i/s | D |
| C11 | Lunettes de soleil, casquette | `occultation` | 2 | Paysage | D |
| C12 | Masque chirurgical, écharpe | `occultation`, `rotation-90` | 2 | Portrait | R |
| C13 | Main devant le visage, boire, téléphone à l'oreille | `occultation` | 2 | Paysage | D |
| C14 | Personne qui sort du champ et revient | `sortie-retour` | 2 | Paysage | D |
| C15 | Visages coupés par le bord de l'image | `sortie-retour`, `rotation-90` | 2 | Portrait | D |
| C16 | Personnes qui se croisent | `sortie-retour`, `profil` | 3 | Paysage | R |
| C17a, C17b | Pièce avec photos au mur et écran allumé (deux pièces) | `image` | 1 + images | Paysage | D, R |
| C18a, C18b | Vidéo filmée à 270° (deux scènes) | `rotation-270` | 1 | Portrait inversé | D, R |
| C19 | Extérieur en plein soleil, ombres dures, une partie à contre-jour | `contre-jour`, `contraste`, `hdr` | 3 | Paysage, HDR | R |
| C20 | Terrasse privée ou cour, ambiance café | `foule`, `rotation-90` | 4–6 | Portrait | D |
| C21a, C21b | Zoom optique ou numérique pendant la prise (deux scènes) | `zoom` | 2 | Paysage | D, R |
| C22 | Panoramique rapide | `flou`, `rapide` | 3 | Paysage | R |
| C23 | Réunion autour d'une table | `foule`, `profil` | 4–6 | Paysage | D |
| C24 | Fête ou repas, lumière colorée | `foule`, `nuit`, `contraste`, `rotation-90`, `vfr` attendu | 4–6 | Portrait | R |

Répartition proposée : 18 clips en développement (D), 9 réservés (R) : C04, C12, C16, C17b, C18b, C19, C21b, C22, C24. Chaque étiquette y figure au moins une fois. La répartition est confirmée après ingestion, quand les étiquettes constatées (`vfr`, `hdr`, `petit`) sont connues ; `blurr-ref check-matrix` vérifie la règle et échoue sinon.

**Règles de tournage**

- Lieux contrôlés uniquement : aucune personne non consentante dans le champ, même floue ou de dos. Une prise où un tiers entre dans le champ est refaite ou coupée avant l'ingestion. La foule (C05) se fait avec un groupe de volontaires dans un lieu fermé, jamais avec des passants.
- Répartir les participants pour couvrir plusieurs carnations dans des conditions variées, en particulier en basse lumière et contre-jour, où les écarts de détection sont les plus probables.
- Toute personne filmée a signé le formulaire, y compris en arrière-plan.
- Filmer avec l'application caméra native et les réglages par défaut : on teste ce que les utilisateurs produiront.
- Noter pour chaque clip : téléphone, mode (HDR, 60 i/s, 4K), lieu, participants.

**Règle sur les réservés** : les clips réservés ne sont pas regardés pendant les ablations de l'étape 2 ; ils ne servent qu'au rapport final de l'étape 2 et aux mesures de l'étape 3. Avec un clip par étiquette dans les réservés, la ventilation par condition sur les réservés est indicative, pas statistique ; seul le chiffre global sur les réservés est opposable.

**Contrôle de passage** : 27 clips (24 au minimum, les prises b en priorité basse) ; `blurr-ref check-matrix` vert : chaque étiquette dans au moins deux clips, dont un réservé ; chaque participant présent au registre ; aucun tiers non consentant visible.

### L4 : ingestion (≈ 6 h)

**But** : pour chaque clip, des images numérotées dont l'horodatage de présentation est connu exactement, dans l'orientation d'affichage.

CVAT est alimenté par **séquence d'images** et non par la vidéo. Raison : le plan impose l'horodatage de présentation comme clé temporelle, et les vidéos de téléphone ont souvent une cadence variable et une rotation dans les métadonnées. En extrayant nous-mêmes les images, l'index d'image dans CVAT correspond à un horodatage que nous contrôlons, quelle que soit la façon dont CVAT décode les vidéos.

`blurr-ref ingest <clip>` fait, dans l'ordre :

1. Calcule le SHA-256 du fichier source et l'écrit au manifeste.
2. Lit les métadonnées avec ffprobe : dimensions, rotation (matrice d'affichage dans `side_data_list`), `r_frame_rate` et `avg_frame_rate`, `time_base`, fonction de transfert des couleurs (`smpte2084` ou `arib-std-b67` signalent du HDR), pistes audio, durée.
3. Liste les horodatages des images, en entiers dans la base de temps du flux puis convertis en microsecondes :
   ```powershell
   ffprobe -v error -select_streams v:0 -show_entries frame=best_effort_timestamp,duration -of csv=p=0 C07.mp4
   ```
   **Convention `pts_us`** : horodatage brut du conteneur converti en microsecondes, arrondi au plus proche, **sans renormalisation** à 0. Le premier pts n'est pas toujours 0 (edit lists des fichiers iPhone, par exemple) ; la valeur du premier pts est écrite dans le manifeste. La durée de la dernière image est prise égale à la médiane si le conteneur ne la donne pas.
4. Extrait chaque image décodée, sans duplication ni suppression ; ffmpeg applique la rotation par défaut ; numérotation à partir de 0 pour coïncider avec l'index CVAT et `gt.json` :
   ```powershell
   ffmpeg -v error -i C07.mp4 -map 0:v:0 -fps_mode passthrough -start_number 0 -q:v 2 frames/C07/%06d.jpg
   ```
   Pour les clips HDR, ajouter un filtre de conversion vers SDR (tonemap) : seules les couleurs changent, pas la géométrie. La conversion de ffmpeg n'est pas celle que Media3 appliquera sur Android ; les détections sur clips HDR ne sont donc comparables entre desktop et Android qu'à cette réserve près, notée dans le manifeste (`hdr_tonemap = ffmpeg-<filtre>`). Les JPEG sont une approximation du décodage direct ; l'équivalence est contrôlée en L7.
5. Vérifie que le nombre d'images extraites égale le nombre d'horodatages, et que les dimensions des images correspondent aux dimensions après rotation. Sinon, le clip est rejeté avec un message explicite.
6. Écrit `frames/C07/frames.csv` (`index,pts_us,duration_us`) et marque le clip à cadence variable selon la règle : **durée maximale d'image supérieure à 1,5 fois la médiane, ou plus de 1 % des images à plus de 10 % de la médiane**. La gigue de quelques centaines de microsecondes des horodatages de téléphone ne doit pas déclencher le marquage.
7. Met à jour `conditions.csv` avec les étiquettes constatées (`vfr`, `hdr`, `rotation-90`, `rotation-270`) et relance `check-matrix`.

**Contrôle de passage** : tous les clips ingérés sans rejet ; au moins un clip marqué `vfr` par la règle ci-dessus, un en rotation 90°, un en 270°, un en HDR. Si l'un manque, le tournage le complète.

### L5 : annotation (≈ 30 h, à recaler)

**But** : une vérité terrain par pistes assez fiable pour qu'un visage manqué par l'annotation ne passe pas pour un visage bien masqué.

**Guide d'annotation** (`dataset/annotation-guide.md`, figé en v1 après le pilote)

| Règle | Contenu |
| --- | --- |
| Étiquette | `face` |
| Boîte | Du haut du front au menton, d'une tempe à l'autre, oreilles exclues ; partie visible seulement ; boîte coupée au bord de l'image |
| Minimum | Tout visage reconnaissable comme tel, quelle que soit sa taille ; les métriques sont ventilées par taille |
| Pas de visage | Arrière de la tête sans aucun trait visible |
| Piste | Une piste = une personne sur tout le clip ; quand elle quitte le champ, la piste passe en `outside`, puis reprend avec le même identifiant |
| Attribut `pose` (mutable) | `face`, `trois-quarts`, `profil` |
| Attribut `occlusion` (mutable) | `aucune`, `partielle`, `forte` (plus de la moitié cachée) |
| Attribut `type` (immuable) | `réel`, `image` (photo, affiche, écran) |
| Images-clés | Au moins toutes les 10 images, et à chaque changement de direction ou de taille ; en mouvement rapide, à chaque image |

**Déroulé**

1. **Pilote** (semaine 4) : annoter entièrement C01, C09 et **C23** (plusieurs personnes, profils) à la main, sans pré-annotation. Chronométrer par clip et compter les personnes-images et les images-clés posées. **Extrapoler en personnes-images, pas en clips** : C01 et C09 (deux personnes) ne prédisent rien sur C05 (8 à 15 pistes en 4K), qui représente à lui seul 15 à 20 % du budget. Réviser le guide sur les cas ambigus rencontrés.
2. **Décision de pré-annotation**, au vu du pilote. Si l'extrapolation dépasse 30 h, pré-annoter : union de YuNet et de CenterFace à seuil bas (0,1), boîtes reliées en pistes par simple recouvrement, écrites directement en **« CVAT for video 1.1 »** par `blurr-ref gt --write` (l'inverse du parseur, avec les attributs à leur valeur par défaut), importées puis corrigées. MOT 1.1 est écarté : il perd les attributs.
3. **Garde-fou contre le biais de pré-annotation** : une pré-annotation hérite des oublis des détecteurs, et ce sont ces détecteurs qu'on veut évaluer. Donc, sur chaque clip pré-annoté, une passe dédiée « visages manqués » : lecture image par image à vitesse réduite, en ne cherchant que des visages sans boîte. Et les trois clips du pilote restent annotés sans pré-annotation, pour mesurer l'écart.
4. **Production** : clips de développement (J1), puis clips réservés (J1b).
5. **Audit** : réannoter de zéro 3 clips de développement (dont un difficile : C05 ou C07) au moins une semaine plus tard, et comparer aux premières versions. Un seul annotateur : l'audit mesure la constance, pas l'exactitude ; c'est la passe « visages manqués » qui vise l'exactitude. **En cas d'échec de l'audit** : nouvelle passe « visages manqués » sur tous les clips annotés depuis la même date, puis nouvel audit sur 2 autres clips.
6. Exporter chaque tâche au format « CVAT for video 1.1 » (une boîte par image, `outside`, `keyframe`, attributs), puis convertir avec `blurr-ref gt` en `gt.json` (section 4.3), qui ajoute les horodatages depuis `frames.csv`.

**Contrôle de passage**

- 100 % des clips du lot annotés, passe « visages manqués » faite sur chacun.
- Audit : aucune piste présente dans la réannotation et absente de la première version ; IoU médiane entre les deux versions d'au moins 0,8 (proposition, à confirmer au pilote).
- Écart pilote : la pré-annotation corrigée ne manque, sur C01, C09 et C23, aucune piste trouvée à la main.

### L6 : script d'évaluation `blurr-ref eval` (≈ 12 h)

**But** : un calcul des métriques de la section 7 du plan général, testé, indépendant de la méthode de masquage évaluée.

Le script évalue des **masques**, pas des détections : chaque méthode convertit ses détections en formes de masque avec sa propre règle (marge, ellipse). C'est ce qui sera réellement appliqué à la vidéo, donc ce qui expose ou non une personne.

Entrées : `gt.json`, `masks.json` (section 4.4), `frames.csv`. **Appariement par horodatage au plus proche voisin, tolérance 1 ms** : ffprobe convertit des pts en base 1/90000 (33 366,67 µs) et Android fournit `presentationTimeUs` avec son propre arrondi ; un appariement exact casserait à l'étape 3. Une image de la vérité terrain sans masque apparié dans la tolérance est une erreur, pas une image sans masque ; deux images de masques appariées à la même image de vérité terrain, idem.

Définitions précises en section 4.5.

**Sorties**

- `report.json` : toutes les métriques, globales, par clip et ventilées.
- `report.md` : tableaux lisibles.
- `worst.csv` : les 20 plus longues expositions avec clip, personne, horodatage de début et de fin.
- Option `--debug-video` : vidéo de contrôle avec vérité terrain en vert, masques en rouge, images exposées signalées. Elle ne quitte jamais le volume chiffré et figure dans la procédure de retrait.

**Tests (données synthétiques générées en code, sans visage réel)**

| Cas | Résultat attendu |
| --- | --- |
| Masques = boîtes de vérité terrain (rectangles) | Rappel 100 %, exposition 0 |
| Aucun masque | Rappel 0 %, exposition = plus longue présence continue |
| Ellipse inscrite dans la boîte | Couverture π/4 ≈ 78,5 % : **non couverte** au seuil de 90 % |
| Ellipse inscrite dans la boîte agrandie de 1,3 (cas synthétique) | Couverture ≈ 98,6 % : couverte |
| Ellipse inscrite dans la boîte agrandie de 1,6 (règle effective de deface, `mask_scale` 1,3) | Couverture 100 % : les coins de la boîte vérifient (0,5/0,8)² × 2 = 0,78 < 1 |
| Rectangle décalé de la moitié de sa largeur | Couverture 50 % : non couverte |
| Personne qui sort et revient, exposée avant et après | Deux expositions distinctes, non additionnées |
| Cadence variable (durées d'image inégales) | Exposition en ms = somme des durées réelles |
| Horodatage de masque à 0,5 ms de la vérité terrain | Apparié |
| Horodatage de masque à 2 ms, ou image de vérité terrain sans masque | Erreur explicite |

Le cas de l'ellipse inscrite est un avertissement pour l'étape 2 : le seuil de 90 % dépend directement de la forme du masque et de la convention de boîte. Une marge nulle échoue par construction.

**Contrôle de passage** : tous les tests passent ; un clip réel passé avec masques = vérité terrain donne rappel 100 % et exposition 0.

### L7 : mesure de référence deface et rapport (≈ 10 h)

**But** : des chiffres de départ, reproductibles par une seule commande.

**Méthode**

- Ne pas lancer la ligne de commande deface pour la mesure : elle lit la vidéo par son propre chemin de décodage, et rien ne garantit qu'elle voie les mêmes images que nos `frames.csv` sur un clip à cadence variable. On appelle à la place le détecteur `CenterFace` livré par le paquet deface sur nos images extraites, à la résolution native (défaut de deface), avec le même backend (onnxruntime) et le nombre de fils noté.
- **Ordre des couleurs** : deface lit ses images avec imageio, donc en RGB, et `blobFromImage` est appelé avec `swapRB=False` ; le réseau reçoit du RGB. Nos JPEG lus avec `cv2.imread` sont en BGR : conversion `BGR → RGB` obligatoire avant l'appel.
- **Règle de masque, identique au code de deface** : `scale_bb` étend chaque côté de `(mask_scale - 1) × taille`, soit une boîte agrandie de `1 + 2 × (mask_scale - 1)` = **1,6** avec le défaut 1,3 ; ellipse inscrite dans cette boîte (mode `blur`, défaut). En mode `solid`, deface dessine un rectangle plein : cette variante est mesurée aussi, car c'est le mode opaque que blurr prendra par défaut.
- **Contrôle d'équivalence** : sur un clip à cadence constante, comparer image par image le nombre de détections de notre appel et celui de la ligne de commande deface (`--draw-scores`, sortie vidéo lue ensuite) ; un écart au-delà de quelques images signale que les JPEG ou l'ordre des couleurs altèrent la mesure.
- Seuils mesurés : 0,2 (défaut de deface), puis 0,1, 0,3 et 0,5. Le coût est faible et donne une première courbe.
- Vitesse : temps mur de détection seule divisé par la durée du clip ; processeur, backend et nombre de fils notés.
- Fidélité et métadonnées : lancer en plus la ligne de commande deface avec `--keep-audio` sur 3 clips (dont un à cadence variable et un en rotation), et comparer source et sortie avec ffprobe (résolution, cadence, durée, audio) et exiftool (localisation). Cela fixe la référence pour les critères de fidélité du plan général.

**Rapport** `docs/rapport-reference-etape1.md`

1. Jeu de test : nombre de clips, durée totale, nombre de pistes et de boîtes, répartition par taille, pose, occlusion, étiquette de condition.
2. Résultats deface par seuil et par mode (`blur` ellipse, `solid` rectangle), sur développement (J1) puis sur réservés (J1b) séparément : rappel par image, plus longue exposition (images et ms), personnes jamais exposées, sur-masquage, vitesse.
3. Ventilation par taille (< 20, 20–40, 40–80, ≥ 80 px), pose, occlusion, étiquette, type.
4. Les 10 pires expositions, décrites en mots (pas d'image dans le dépôt).
5. Fidélité et métadonnées de la sortie deface.
6. Résultat du contrôle d'équivalence (JPEG et ordre des couleurs).
7. Temps d'annotation réel et écart au budget, pour recaler le calendrier général.
8. Versions : commit, fichier de verrouillage, ffmpeg, CVAT, deface, empreintes des clips.

**Contrôle de passage** : `blurr-ref baseline deface --all` puis `blurr-ref eval` régénèrent le rapport à l'identique sur une seconde exécution.

## 4. Spécifications

### 4.1 Données hors dépôt

```
blurr-data/                     volume chiffré, sauvegarde chiffrée hors ligne
  raw/C07.mp4
  frames/C07/000000.jpg …
  frames/C07/frames.csv
  annotations/cvat/C07.xml
  annotations/gt/C07.json
  runs/deface-t0.2-blur/C07.masks.json
  runs/deface-t0.2-blur/report.json
  debug/                        vidéos de contrôle (--debug-video)
docker/                         data-root Docker (volumes CVAT), sur le même volume chiffré
```

Le registre des consentements est stocké à part, pas dans `blurr-data/`.

### 4.2 `manifest.csv` (dans le dépôt)

`clip,sha256,split,device,width,height,rotation,avg_fps,vfr,hdr_transfer,hdr_tonemap,first_pts_us,has_audio,duration_ms,n_frames,participants`

Ce fichier ne contient aucune image et ne nomme personne : `participants` liste des identifiants du registre. Les étiquettes de condition sont dans `conditions.csv`.

### 4.3 `gt.json` v0

```json
{
  "schema": "blurr-gt/0",
  "clip": "C07",
  "source_sha256": "…",
  "width": 1080,
  "height": 1920,
  "pts_origin": "container",
  "frames": [{ "i": 0, "pts_us": 0, "dur_us": 33366 }],
  "persons": [
    {
      "id": 1,
      "type": "réel",
      "boxes": [
        { "i": 0, "x": 412, "y": 300, "w": 96, "h": 118,
          "pose": "face", "occlusion": "aucune", "keyframe": true }
      ]
    }
  ]
}
```

Coordonnées en pixels, repère après rotation, origine en haut à gauche. `pts_us` est le pts brut du conteneur en microsecondes (`pts_origin = container`), jamais renormalisé. Une personne absente d'une image n'a pas de boîte à cet index.

### 4.4 `masks.json` v0

```json
{
  "schema": "blurr-masks/0",
  "clip": "C07",
  "method": "deface-centerface",
  "params": { "threshold": 0.2, "mask_scale": 1.3, "effective_scale": 1.6, "shape": "ellipse" },
  "pts_origin": "container",
  "frames": [
    { "pts_us": 0,
      "shapes": [{ "kind": "ellipse", "cx": 460, "cy": 359, "rx": 77, "ry": 94 }] }
  ]
}
```

Formes admises : `ellipse` (`cx, cy, rx, ry`) et `rect` (`x, y, w, h`). L'appariement avec `gt.json` se fait sur `pts_us` au plus proche voisin, tolérance 1 ms (L6). Ce format v0 est un brouillon d'évaluation ; le format de pistes v1, en coordonnées normalisées, sera figé à l'étape 2 et `blurr-ref eval` le lira aussi.

### 4.5 Définitions des métriques

| Métrique | Définition opérationnelle |
| --- | --- |
| Couverture d'une boîte | Part des pixels de la boîte situés dans l'union des formes de masque de l'image appariée |
| Boîte couverte | Couverture ≥ 0,9 |
| Rappel par image | Boîtes couvertes / boîtes annotées, global et par case de ventilation |
| Exposition | Suite d'images consécutives où une personne est présente et sa boîte non couverte ; une absence (`outside`) interrompt la suite |
| Plus longue exposition | Maximum des expositions, en images et en ms (somme des `dur_us`) |
| Personnes jamais exposées | Pistes sans aucune image non couverte / pistes, sur toutes les pistes et sur celles de taille médiane ≥ 20 px |
| Sur-masquage | Formes dont moins de 10 % de la surface recouvre une boîte annotée, par minute de vidéo ; informatif |
| Vitesse | Temps mur de la méthode / durée du clip, détection seule et chaîne complète séparément |

Taille d'une boîte : sa hauteur en pixels à la résolution native après rotation. Les boîtes `type = image` sont comptées à part et n'entrent pas dans les chiffres principaux.

## 5. Calendrier (10 h par semaine)

| Semaine | Dates | Travail | Heures | Contrôle en fin de semaine |
| --- | --- | --- | --- | --- |
| S1 | 12–18 oct. | L1 ; décisions de la section 2 ; L2 étapes 1 à 3 (dépôt, uv, ffmpeg) ; matrice et `conditions.csv` ; guide v0 ; planification des tournages avec les volontaires | 10 | L1 vert |
| S2 | 19–25 oct. | L2 étapes 4 à 6 (Docker, CVAT, volume chiffré) ; script d'ingestion L4 sur un clip d'essai | 10 | L2 vert |
| S3 | 26 oct.–1er nov. | Tournage (L3) ; ingestion de tous les clips ; `check-matrix` | 10 | L3 et L4 verts |
| S4 | 2–8 nov. | Pilote d'annotation (C01, C09, C23) ; guide v1 ; décision de pré-annotation ; `blurr-ref gt` (lecture et écriture CVAT XML) | 10 | Budget d'annotation recalé |
| S5 | 9–15 nov. | Annotation (développement) ; L6 couverture et métriques | 8 + 2 | aucun |
| S6 | 16–22 nov. | Annotation (développement) ; L6 tests synthétiques ; tournage complémentaire si une étiquette manque | 8 + 2 | aucun |
| S7 | 23–29 nov. | Fin de l'annotation de développement ; audit ; L6 terminé | 6 + 4 | L5 (développement) et L6 verts |
| S8 | 30 nov.–6 déc. | Exécution deface sur développement ; rapport ; contrôle de sortie J1 | 8 | **J1** |
| S9–S10 | 7–20 déc. | J1b : annotation des réservés (≈ 10 h) ; deface sur réservés et rapport complété (≈ 2 h) ; peut chevaucher le début de l'étape 2 | 12 | **J1b** |

Total S1 à S8 : 68 h planifiées pour 80 h disponibles ; la marge de 12 h absorbe un dépassement du pilote ou un tournage à refaire. Le tournage dépend de la disponibilité des volontaires : à planifier dès S1. Si le tournage glisse, l'écriture de L6 avance sur données synthétiques.

## 6. Risques propres à l'étape 1

| Risque | Signal d'alerte | Parade |
| --- | --- | --- |
| Annotation bien plus longue que prévu | Pilote extrapolé en personnes-images au-delà de 30 h | Clips raccourcis à 10–15 s ; pré-annotation avec garde-fous ; ne jamais sous-échantillonner les images, ce qui fausserait l'exposition ; J1b peut glisser dans l'étape 2 |
| Vérité terrain biaisée par la pré-annotation | Écart sur les clips du pilote | Passe « visages manqués » obligatoire ; clips du pilote annotés à la main |
| Tiers non consentant dans le champ | Visage inconnu du registre à l'annotation | Prise refaite ou coupée avant ingestion ; lieux contrôlés uniquement |
| Copie des images hors du volume chiffré | `docker volume inspect` hors du volume ; fichiers temporaires de ffmpeg ou de CVAT ailleurs | Data-root Docker sur le volume chiffré ; contrôle en L2 ; procédure de retrait qui liste tous les emplacements |
| Volontaires insuffisants pour la foule | Moins de 8 personnes disponibles | Foule réduite filmée de plus loin ; compléter à l'étape 4 |
| Images extraites désalignées avec les horodatages | Contrôle du nombre d'images en échec | Rejet du clip ; diagnostic ffprobe ; transcodage exclu car il change les images |
| Réglages ajustés sur les clips réservés | Clips réservés ouverts pendant les ablations | Règle écrite dans le README ; réservés évalués seulement en fin d'étape 2 |
| Fuite des données de test | Fichier média suivi par git, stockage non chiffré | `.gitignore` des médias, contrôle en intégration continue, volume chiffré |
| Convention de boîte incompatible avec le seuil de 90 % | Rappel faible même avec des masques visuellement corrects | Cas synthétiques de L6 ; marge réglée à l'étape 2 et non dans la vérité terrain |
| Mesure deface non représentative de la ligne de commande | Contrôle d'équivalence L7 en écart | Corriger l'ordre des couleurs ou extraire en PNG le clip concerné |

## 7. Contrôle de sortie

**J1**

- [ ] Au moins 24 clips ingérés, `check-matrix` vert (chaque étiquette dans deux clips, dont un réservé).
- [ ] Consentement enregistré pour chaque participant ; procédure de retrait testée sur un clip fictif, tous emplacements compris.
- [ ] Volumes CVAT et `blurr-data/` sur le volume chiffré ; aucun fichier média dans le dépôt.
- [ ] Tous les clips ingérés ; horodatages, convention `pts_us` et rotation vérifiés.
- [ ] Clips de développement annotés, passe « visages manqués » faite, audit dans les seuils de L5.
- [ ] Guide d'annotation v1 figé dans le dépôt.
- [ ] `blurr-ref eval` : tests synthétiques verts, dont les cas 1,6 et tolérance d'appariement ; contrôle vérité terrain = masques à 100 %.
- [ ] Rapport deface sur développement régénérable par une commande, archivé avec les versions, contrôle d'équivalence inclus.
- [ ] Temps réel de l'étape comparé à l'estimation ; calendrier général et échéances de la section 9 recalés.

**J1b**

- [ ] Clips réservés annotés avec passe « visages manqués ».
- [ ] Rapport complété avec les résultats sur réservés, avant tout chiffre publié sur les réservés à l'étape 2.

## 8. Historique des révisions

**Révision 2 (11 oct. 2026)**, après relecture critique :

- Règle de masque de deface corrigée (agrandissement effectif 1,6, pas 1,3) d'après le code de `scale_bb` ; cas de test L6 ajouté ; mode `solid` mesuré aussi.
- Liste fermée d'étiquettes de condition et fichier `conditions.csv` ; trois scènes doublées (27 clips) pour que chaque étiquette ait deux clips dont un réservé ; contrôle `check-matrix`.
- Lieux de tournage contrôlés uniquement ; procédure de retrait étendue à tous les emplacements, dont les volumes CVAT ; data-root Docker sur le volume chiffré ; durée de conservation alignée sur la maintenance de l'application ; option « jeu public » explicite sur la publication non masquée.
- Calendrier rééquilibré (S1 et S2 étaient à 12 et 14 h) ; J1b séparé pour les réservés ; marge de 12 h ; échéances du 22 nov. du plan général signalées comme caduques.
- Pilote étendu à C23 et extrapolation en personnes-images.
- Convention `pts_us` (pts brut du conteneur), appariement au plus proche voisin avec tolérance 1 ms, numérotation des images à partir de 0, règle de détection de cadence variable, ffmpeg ≥ 5.1, fixtures générées en code, attributs CVAT mutables ou immuables, pré-annotation en CVAT XML plutôt qu'en MOT, conversion BGR → RGB et contrôle d'équivalence en L7, stockage porté à 40 Go.

## Sources

- [blurr plan complet de construction](blurr%20plan%20complet%20de%20construction.md) (sections 4 et 7)
- [CVAT](https://github.com/cvat-ai/cvat) ; [export des pistes, `bindings.py`](https://github.com/cvat-ai/cvat/blob/develop/cvat/apps/dataset_manager/bindings.py) (`get_interpolated_shapes`)
- [deface](https://pypi.org/project/deface/) ; [`deface.py`](https://github.com/ORB-HD/deface/blob/master/deface/deface.py) (`scale_bb`, `draw_det`, défauts) ; [`centerface.py`](https://github.com/ORB-HD/deface/blob/master/deface/centerface.py) (`blobFromImage`, `swapRB=False`)
- [YuNet, OpenCV Zoo](https://huggingface.co/opencv/opencv_zoo/blob/d33294bfaec5f2386dab1783e1a4031330645f57/models/face_detection_yunet/README.md)
- [ffmpeg, documentation](https://ffmpeg.org/ffmpeg.html) ; [ffprobe, documentation](https://ffmpeg.org/ffprobe.html)
