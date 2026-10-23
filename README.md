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
  desktop/            # Environnement Python desktop (CLI blurr-ref, ingestion, métriques, baselines)
  dataset/            # Métadonnées, matrice de conditions, guide d'annotation (aucun média)
  android/            # Application Android v0.2 (YuNet via OpenCV, suivi temporel, flou ou masque noir via Media3), APK dans android/apk/
  ios/                # Application iOS v0.2 (même moteur : Swift, rendu C++ avec OpenCV, AVFoundation), IPA dans la pré-version ios-latest
```

## Application iOS

Fichier `blurr-ios.ipa` de la pré-version [ios-latest](https://github.com/Momour/blurr/releases/tag/ios-latest), compilé par GitHub Actions, à installer sur iPhone (iOS 17 ou plus) avec Sideloadly et un compte Apple, même gratuit. Installation, utilisation et état de vérification : [ios/README.md](ios/README.md).

## Licence

Ce projet est distribué sous licence GNU General Public License v3.0 ou ultérieure ([LICENSE](LICENSE)).
