# blurr

Application et outillage de masquage automatique des visages dans les vidéos (desktop & mobile).

## Principes clés

- **Confidentialité dès la conception** : le masquage s'opère en local, sans transfert réseau de flux vidéo.
- **Zéro média dans le dépôt** : aucun fichier vidéo ou image n'est versionné sous Git. Le jeu de test vidéo et les images extraites résident exclusivement sur un volume local chiffré (`blurr-data/`).
- **Évaluation rigoureuse** : jeu de test diversifié (27 clips représentatifs, conditions réelles de smartphone), vérité terrain annotée manuellement avec CVAT, séparation stricte entre clips de développement (D) et clips réservés (R).
- **Règle d'or sur les clips réservés** : les clips du lot réservé (R) ne doivent jamais être visionnés ni utilisés pour régler des hyperparamètres ou choisir des variantes d'algorithmes lors des ablations. Ils sont réservés à l'évaluation finale.

## Structure du dépôt

```
blurr/
  docs/               # Documentation d'architecture, plans détaillés et protocoles légaux
  desktop/            # Environnement Python desktop (CLI blurr-ref, ingestion, métriques, baselines)
  dataset/            # Métadonnées, matrice de conditions, guide d'annotation (aucun média)
  android/            # Application Android MVP v0.1 (YuNet via OpenCV, export Media3), voir docs/mvp-android.md
```

## Licence

Ce projet est distribué sous licence GNU General Public License v3.0 ou ultérieure ([LICENSE](LICENSE)).
