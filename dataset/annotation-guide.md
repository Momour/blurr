# Guide d'annotation de la vérité terrain (CVAT) - v0

Ce guide fixe les règles strictes d'annotation pour constituer la vérité terrain du jeu de test de `blurr`.  
Il sera consolidé en v1 à l'issue du pilote d'annotation (semaine 4).

---

## 1. Configuration du projet dans CVAT

- **Étiquette principale** : `face`
- **Attributs** :
  - `pose` (**mutable**, évalué image par image) : `face` | `trois-quarts` | `profil`
  - `occlusion` (**mutable**, évalué image par image) : `aucune` | `partielle` | `forte` (plus de 50 % masqué)
  - `type` (**immuable**, fixé pour toute la piste) : `réel` | `image` (photo, affiche, tableau, écran vidéo)
- **Qualité d'image à l'import** : **95 % ou plus** (ne jamais utiliser la compression CVAT par défaut de 70 %, qui détruit les visages de moins de 20 px en 4K).
- **Format d'export / import** : **CVAT for video 1.1** (XML avec interpolation, flags `outside`, `keyframe` et conservation des attributs). Ne pas exporter en MOT 1.1 (perte des attributs).

---

## 2. Délimitation des boîtes englobantes (Bounding Boxes)

| Règle | Spécification |
|---|---|
| **Périmètre du visage** | Du haut du front (naissance des cheveux ou ligne frontale) au bas du menton, et d'une tempe à l'autre. **Les oreilles sont expressément exclues**. |
| **Partie visible uniquement** | Si une partie de la tête est masquée par un obstacle opaque ou hors-champ, la boîte englobe strictement la partie visible du visage. |
| **Bords du cadre** | Si un visage est partiellement hors champ, la boîte est rognée au bord exact de l'image (coordonnées entre 0 et `width`/`height`). |
| **Seuil minimal de taille** | **Tout visage reconnaissable comme tel par un humain**, quelle que soit sa résolution (y compris < 20 px). La ventilation par catégorie de taille s'effectuera au calcul des métriques. |
| **Ce qui n'est PAS un visage** | L'arrière de la tête (cheveux seuls, nuque) sans aucun trait facial distinctif visible. |

---

## 3. Gestion des pistes temporelles (Tracking)

- **Unicité de l'identifiant** : Une même personne physique conserve le même identifiant de piste (`track id`) du début à la fin du clip.
- **Sorties de champ** : Dès qu'une personne quitte le champ ou devient totalement invisible (occultation à 100 %), marquer la boîte en `outside="1"`.
- **Réapparitions** : Lorsque la personne réapparaît, reprendre la même piste avec `outside="0"`.
- **Fréquence des images-clés (`keyframe`)** :
  - Poser une image-clé au minimum **toutes les 10 images** lors des mouvements lents ou rectilignes.
  - Poser une image-clé à **chaque changement de direction**, chaque rotation de tête, ou chaque modification rapide d'échelle.
  - En mouvement rapide ou caméra portée instable : annoter **image par image** (`keyframe="1"` sur chaque frame).

---

## 4. Protocole d'annotation et contrôles qualité

1. **Passe principale d'annotation** :
   - Délimitation rigoureuse des boîtes et ajustement des attributs `pose` et `occlusion`.
2. **Passe dédiée « visages manqués » (Obligatoire)** :
   - Relecture complète du clip image par image au ralenti, en observant spécifiquement les zones périphériques, l'arrière-plan et les bords du cadre pour traquer les visages sans boîte.
3. **Audit de cohérence** :
   - Ré-annotation à l'aveugle de 3 clips de développement au moins une semaine après.
   - Critère d'acceptation : zéro piste omise, IoU médiane ≥ 0,8.
