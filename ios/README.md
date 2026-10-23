# blurr : application iOS (v0.2)

Floute les visages d'une vidéo sur iPhone, hors ligne. Même moteur que l'application Android v0.2 et que la version
PC : détection YuNet (OpenCV), pistes à double seuil, flou pyramidal ou masque noir, contrôle du fichier produit.

**Statut : prototype. Compilé et testé automatiquement (moteur, rendu, chaîne vidéo complète sur simulateur iPhone),
jamais exécuté sur un iPhone réel par l'auteur de ces modifications.** Regarder la vidéo produite en entier avant
toute diffusion. Les points non vérifiés sont listés en section 6.

## 1. Installer l'application (Windows, compte Apple gratuit)

Il n'existe pas d'APK sur iOS : une application hors App Store doit être signée avec un compte Apple au moment de
l'installation. Avec un compte gratuit, l'application cesse de s'ouvrir au bout de 7 jours et doit être re-signée
(automatique si l'option de renouvellement de Sideloadly est active, voir l'étape 6).

Prérequis : iPhone sous iOS 17 ou plus récent, câble USB, PC Windows, un identifiant Apple (un identifiant
secondaire, créé pour l'occasion, convient et évite de saisir son identifiant principal dans un logiciel tiers).

1. **Télécharger l'application** : `blurr-ios.ipa` dans la pré-version
   [ios-latest](https://github.com/Momour/blurr/releases/tag/ios-latest) (l'empreinte SHA-256 figure dans la
   description de la pré-version).
2. **Installer iTunes et iCloud, versions du site d'Apple** (pas celles du Microsoft Store, à désinstaller d'abord si
   elles sont présentes) : liens donnés sur la page de [Sideloadly](https://sideloadly.io/).
3. **Installer Sideloadly** depuis [sideloadly.io](https://sideloadly.io/), puis le lancer.
4. **Brancher l'iPhone** en USB, le déverrouiller et répondre « Faire confiance » à l'ordinateur. L'iPhone apparaît
   dans la liste « iDevice » de Sideloadly.
5. **Glisser `blurr-ios.ipa`** sur la fenêtre de Sideloadly (ou cliquer sur l'icône IPA), saisir l'identifiant Apple
   puis « Start ». Saisir le mot de passe et le code de double authentification demandés.
6. **Renouvellement automatique (recommandé)** : laisser activée l'icône de renouvellement à gauche de « Start ».
   Sideloadly re-signe alors l'application tous les quelques jours, tant qu'il tourne sur le PC et que l'iPhone est
   joignable (même réseau Wi-Fi, ou câble). Sinon, refaire l'étape 5 au moins une fois par semaine.
7. **Sur l'iPhone** :
   - Réglages > Général > VPN et gestion de l'appareil > « App de développeur » : toucher l'identifiant Apple utilisé,
     puis « Faire confiance ».
   - Réglages > Confidentialité et sécurité > Mode développeur : activer, redémarrer l'iPhone, puis confirmer
     l'activation au redémarrage.
8. Ouvrir **blurr** depuis l'écran d'accueil.

Limites du compte gratuit : 3 applications installées ainsi en même temps, 10 identifiants d'application par
période de 7 jours. Si la signature bloque à l'étape 5 : quitter complètement iTunes, renommer le dossier
`C:\ProgramData\Apple Computer\iTunes\adi` en `adi.bak`, puis recommencer.

Autres voies : AltStore (même principe, renouvellement par AltServer sur le PC) ; TestFlight ou App Store avec le
programme Apple Developer payant (99 USD par an) ; AltStore PAL dans l'Union européenne (programme payant et
notarisation par Apple).

## 2. Utilisation

1. « Choisir une vidéo » (photothèque, sans demande d'accès à toute la photothèque) ou « Choisir dans Fichiers ».
2. Régler si besoin (mêmes réglages et mêmes valeurs par défaut qu'Android et la version PC) :
   - précision de l'analyse : Rapide (960 px), Standard (1280 px, défaut), Précise (1920 px) ;
   - sensibilité : Normale, Élevée (défaut), Maximale (tableau de `docs/mvp-android.md`, section 3) ;
   - rendu : Flou (défaut) ou Masque noir ; conserver le son (oui par défaut) ; contrôler le résultat (oui par défaut).
3. « Masquer les visages ». **Garder blurr à l'écran** : iOS interrompt le traitement si l'application passe en
   arrière-plan (l'écran ne se met pas en veille pendant le traitement).
4. Résultat : bilan (pistes masquées et écartées, part des images masquées, instants signalés par le contrôle),
   boutons « Lire la vidéo », « Enregistrer dans Photos », « Partager », « Supprimer ce fichier de l'application ». Le
   fichier reste aussi dans l'app Fichiers > Sur mon iPhone > blurr, sous le nom `<nom>_blurr.mp4`.
5. En cas de problème : « Copier le journal (diagnostic) », puis coller le texte dans un message. Le journal contient
   le modèle de l'iPhone, la version d'iOS, les caractéristiques techniques de la vidéo, les réglages et les étapes
   du traitement ; ni image ni position.

## 3. Principe

Trois passes, comme sur Android :

1. **Analyse.** Décodage image par image (AVAssetReader, images BGRA converties en BT.709 : les vidéos HDR et Dolby
   Vision de l'iPhone sont ramenées en SDR par AVFoundation), réduction (INTER_AREA, plus grand côté à la précision
   choisie), redressement selon l'orientation de la vidéo, détection YuNet (`face_detection_yunet_2023mar.onnx`, MIT)
   par OpenCV 4.14. Les détections forment des pistes (`BlurrCore/MaskPlan.swift`, portage exact de `MaskPlan.kt`).
2. **Export.** Nouveau décodage, rendu du flou ou du masque noir sur processeur (`Blurr/Engine/MaskRenderer.cpp`,
   portage du rendu de la version PC, lui-même équivalent au shader Android), encodage H.264 par AVAssetWriter avec
   la même orientation et les mêmes horodatages que la source. Son copié sans ré-encodage (AAC), sinon ré-encodé en
   AAC. Aucune métadonnée de la source recopiée (position, date, appareil).
3. **Contrôle.** Relecture du fichier produit (une image sur n, 600 au plus) à la même précision, seuil égal au plus
   grand de 0,6 et du seuil de confirmation ; une détection hors de toute ellipse du plan est signalée avec son
   instant.

L'application n'utilise pas le réseau. iOS ne permet pas de le garantir par une permission (contrairement à Android) :
la garantie repose sur le code source, sans aucun appel réseau ni bibliothèque tierce de suivi. Vérifiable par
l'utilisateur dans Réglages > Confidentialité et sécurité > Rapport de confidentialité des apps, qui liste les
domaines contactés par chaque application.

## 4. Différences avec Android v0.2

| Point | Android v0.2 | iOS |
|---|---|---|
| Décodage, encodage | MediaCodec, Media3 Transformer | AVAssetReader, AVAssetWriter (H.264) |
| Rendu | Shader OpenGL ES | Processeur (C++, OpenCV) ; écart d'au plus 1/255 avec la version PC |
| Orientation | Rotation du fichier | `preferredTransform` (quarts de tour et symétries), recopiée dans le fichier produit |
| HDR | Converti en SDR (repli si échec) | Converti en SDR par AVFoundation (BT.709) |
| Débit vidéo | Débit de la source (2 à 80 Mb/s) | Idem, multiplié par 1,5 pour une source HEVC (sortie H.264) |
| Fichier produit | Galerie, Movies/blurr | Fichiers > Sur mon iPhone > blurr ; Photos sur demande |
| Hors ligne | Permission Internet absente | Aucun code réseau (pas de garantie par le système) |
| Écran « Licences » | Non | Oui (blurr GPL-3.0, YuNet MIT, OpenCV Apache-2.0) |

## 5. Compilation

Sans Mac : à chaque envoi sur la branche `ios`, GitHub Actions (`.github/workflows/ios.yml`, Mac gratuit pour un
dépôt public) télécharge OpenCV 4.14.0 pour iOS (empreinte vérifiée), exécute les tests du moteur, génère le projet
Xcode avec XcodeGen, exécute les tests sur simulateur iPhone, archive l'application sans signature et publie
`blurr-ios.ipa` dans la pré-version `ios-latest`.

Sur un Mac (Xcode 26 ou plus) :

```
cd ios
bash Tools/fetch_opencv.sh 4.14.0 Frameworks
swift Tools/make_icon.swift Blurr/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
brew install xcodegen && xcodegen generate
open Blurr.xcodeproj
```

Le cadre OpenCV publié ne contient pas l'architecture arm64 du simulateur : sur un Mac Apple Silicon, exécuter
l'application sur un iPhone branché, ou les tests sur un simulateur x86_64 (Rosetta).

Tests hors Mac : `swift test --package-path ios/BlurrCore` (Linux, Windows ou macOS) ; parité du rendu C++ avec la
version PC : `ios/Tools/render-parity/run_parity.py` (OpenCV C++ et Python requis, voir l'en-tête du fichier).

Sources : `BlurrCore/` (moteur Swift), `Blurr/Engine/` (rendu et préparation des images, C++), `Blurr/Bridge/` (pont
Objective-C++), `Blurr/Pipeline/` (passes AVFoundation), `Blurr/UI/` et `Blurr/App/` (interface SwiftUI),
`BlurrTests/` (tests sur simulateur), `Tools/` (scripts).

## 6. État de vérification

| Élément | Statut | Détail |
|---|---|---|
| Moteur (suivi, plan de masquage, géométrie, règles) | Vérifié | 46 tests Swift (Linux et macOS) : les 20 tests de `MaskPlanTest.kt`, ceux de `BlurGeometryTest.kt` et `PoliciesTest.kt`, orientation, bilan |
| Parité du plan avec la version PC | Vérifié | 360 images, 1 091 détections synthétiques : mêmes pistes, mêmes images masquées, mêmes ellipses (écart au plus 1e-5) pour les trois sensibilités |
| Rendu C++ (flou, masque noir) | Vérifié hors iPhone | Comparé à `render.py` sur 11 cas (tailles impaires, 40 ellipses, ellipses coupées par le bord, 3 et 4 canaux) : écart au plus 1/255, pixels hors ellipses identiques |
| Redressement des images d'analyse | Vérifié | 8 orientations (quarts de tour et symétries), positions identiques au calcul Swift |
| Compilation pour iPhone | Vérifié | Archive Release arm64 (Xcode 26.6, SDK iOS 26.5), sans avertissement du code de blurr ; IPA de 2,9 Mo, binaire de 6,9 Mo (OpenCV lié statiquement, modules inutilisés retirés) |
| Tests sur simulateur iPhone | Vérifié | 12 tests (GitHub Actions, simulateur x86_64) : pont C++ (masque noir, flou d'un damier, image sans ellipse, chargement du modèle, exceptions) ; détection d'un vrai visage sur une vidéo portrait, position identique après redressement ; chaîne complète sur vidéos fabriquées en code : visage en mouvement avec son (1 piste masquée sur 5, 60 images masquées, son copié, contrôle : 0 visage hors masque, flou et masque noir mesurés au centre du visage, aucune position dans les métadonnées), vidéo portrait (orientation conservée), sans visage ni son, son coupé, annulation sans fichier, nom unique |
| Exécution sur iPhone réel | **Non vérifié** | Décodage des vidéos de l'appareil photo (HEVC, Dolby Vision), mémoire, vitesse |
| Installation par Sideloadly | **Non vérifiée** | Procédure tirée de la documentation de Sideloadly |
| Rappel de détection (visages manqués) | **Non mesuré** | Comme Android et la version PC |

## 7. Limites et risques connus

- Mêmes limites de détection qu'Android (section 6 de `docs/mvp-android.md`) : aucun détecteur ne trouve 100 % des
  visages ; un visage dont aucune détection n'atteint le seuil de confirmation n'est pas masqué ; le flou protège
  moins que le masque noir ; seuils choisis sur une seule vidéo ; seuls les visages sont masqués.
- **Premier plan obligatoire** : passer à une autre application interrompt le traitement (à relancer).
- **Vitesse et mémoire non mesurées sur iPhone** ; le rendu se fait sur processeur.
- **HDR** : la vidéo produite est en SDR (couleurs moins vives que l'original sur un écran HDR).
- **Formats** : ceux que lit AVFoundation (MOV, MP4 ; H.264, HEVC, ProRes) ; sortie MP4 H.264 8 bits. Seule la
  première piste audio est recopiée ; sous-titres et pistes de données ne le sont pas.
- **Sélecteur de Photos** : iOS peut convertir la vidéo choisie avant de la transmettre (le mode « actuel » est
  demandé pour l'éviter, sans garantie).
- **Distribution** : signature personnelle valable 7 jours avec un compte gratuit. La licence GPL-3.0 du projet pose
  question pour une diffusion par l'App Store par des tiers (voir l'analyse dans la documentation du projet).
- **Licences** : les composants internes d'OpenCV (libjpeg-turbo, libpng, zlib, Protobuf, etc.) restent à
  inventorier, comme pour Android.

## 8. Décisions

| Réf. | Décision |
|---|---|
| I1 | Application native (Swift, SwiftUI), sans cadre multiplateforme : décodage, rendu et encodage doivent de toute façon utiliser les API d'Apple. |
| I2 | Moteur porté en Swift (`BlurrCore`, sans dépendance Apple) plutôt que partagé par Kotlin Multiplatform, avec parité vérifiée par les tests portés et un jeu de détections commun avec la version PC. |
| I3 | YuNet conservé via OpenCV 4.14 (cadre publié par OpenCV, empreinte vérifiée), appelé par un pont Objective-C++ : mêmes scores et mêmes préréglages qu'Android et la version PC. |
| I4 | Rendu sur processeur en C++ (portage de `render.py`) plutôt qu'en Metal : testable hors iPhone et sur simulateur, identique à la version PC à 1/255 près. |
| I5 | Orientation conservée comme métadonnée (`preferredTransform`) : rendu sur l'image codée, ellipses converties du repère affiché au repère codé. |
| I6 | Plan appliqué par horodatage : analyse et export lisent le même fichier avec les mêmes réglages, les horodatages coïncident (décalage nul attendu, calage d'Android conservé par sécurité). |
| I7 | Sortie H.264 en BT.709 (compatibilité maximale), débit de la source multiplié par 1,5 si elle est en HEVC. |
| I8 | Compilation sans Mac par GitHub Actions ; IPA non signée publiée en pré-version, signée à l'installation par l'utilisateur (Sideloadly). |
| I9 | Aucune image versionnée : icône dessinée à la compilation (`Tools/make_icon.swift`), image de test téléchargée par la compilation. |
