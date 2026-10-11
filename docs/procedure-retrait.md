# Procédure de retrait de consentement (Droit à l'effacement)

Cette procédure garantit l'effacement exhaustif et sans résidu de toutes les données liées à un participant ou à un clip suite à une demande de retrait de consentement.

> **Règle absolue** : Aucun fichier source, image extraite, annotation, métrique ou vidéo dérivée ne doit subsister sur aucun support.

---

## Liste de contrôle des emplacements à purger

Lorsqu'un participant `Pxx` demande le retrait, identifier les clips concernés via le registre des consentements (ex: clip `Cyy`).

| Étape | Emplacement | Action | Commande / Vérification |
|---|---|---|---|
| 1 | `blurr-data/raw/` | Supprimer le fichier vidéo brut source | `rm -f blurr-data/raw/Cyy.mp4` |
| 2 | `blurr-data/frames/` | Supprimer le dossier d'images extraites et son `frames.csv` | `rm -rf blurr-data/frames/Cyy/` |
| 3 | Interface CVAT | Supprimer la tâche d'annotation du clip | Bouton "Delete" dans l'UI CVAT |
| 4 | Volume Docker `cvat_data` | Vérifier et purger le cache / les données internes CVAT | `docker exec -it cvat_server rm -rf /home/django/data/data/<task_id>` |
| 5 | `blurr-data/annotations/` | Supprimer l'export CVAT XML et la vérité terrain v0 | `rm -f blurr-data/annotations/cvat/Cyy.xml blurr-data/annotations/gt/Cyy.json` |
| 6 | `blurr-data/runs/` | Supprimer les masques générés et rapports partiels | `rm -f blurr-data/runs/*/Cyy.masks.json` |
| 7 | `blurr-data/debug/` | Supprimer les vidéos de contrôle annotées | `rm -f blurr-data/debug/Cyy*.mp4` |
| 8 | Rapports & `worst.csv` | Purger les mentions du clip dans `worst.csv` et relancer l'évaluation | `uv run blurr-ref eval` |
| 9 | Sauvegarde chiffrée hors ligne | Monter la sauvegarde et répercuter les étapes 1 à 7 | Supprimer `Cyy` de tous les répertoires miroirs |
| 10 | Registre des consentements | Mettre à jour le statut du participant (date de retrait notée) | Mettre le statut à `RETIRÉ` avec la date |
| 11 | `dataset/manifest.csv` | Supprimer la ligne correspondant au clip | Retirer la ligne `Cyy` du fichier CSV |
| 12 | Contrôle d'intégrité | Exécuter le contrôle de matrice | `uv run blurr-ref check-matrix` (relancer un tournage si une condition devient déficitaire) |

---

## Test préalable obligatoire (clip fictif)

Avant le tout premier tournage de clips réels :
1. Ingérer un clip fictif généré par script (`CFIC.mp4`).
2. Créer une tâche CVAT d'essai et exporter l'annotation `CFIC.xml`.
3. Calculer les masques et exécuter `blurr-ref eval`.
4. Appliquer rigoureusement la procédure ci-dessus pour supprimer `CFIC`.
5. Vérifier par recherche récursive sur le disque et les volumes Docker qu'aucun résidu de `CFIC` n'existe.
