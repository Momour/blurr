# Mentions de tiers et dépendances (THIRD_PARTY)

Ce document répertorie les bibliothèques logicielles tierces, leurs licences et leurs notices de copyright utilisées par `blurr`.

| Dépendance | Licence | Utilisation |
|---|---|---|
| AndroidX Media3 1.11.1 (`media3-transformer`, `media3-effect`, `media3-common`, `media3-muxer`) | Apache-2.0 | Android : décodage, effet OpenGL de masquage, encodage et mux de la vidéo |
| OpenCV 4.14.0 (`org.opencv:opencv`) | Apache-2.0 | Android : exécution du détecteur YuNet (`FaceDetectorYN`) et conversions d'images |
| Modèle YuNet `face_detection_yunet_2023mar.onnx` (OpenCV Zoo, © 2020 Shiqi Yu) | MIT | Android : détection de visages. Fichier embarqué sans modification dans `android/app/src/main/assets/models/` |
| Composants natifs liés statiquement dans `libopencv_java4.so` (OpenCV 4.14.0) : libjpeg-turbo 3.1.2, libpng, libwebp, libtiff, libopenjp2, OpenEXR 2.3.0, zlib 1.3.0.1, Protobuf 3.19.1, TBB 2022.1, KleidiCV 26.03, carotene 0.0.1, ADE, ittnotify, libcpufeatures | **À inventorier** | Android : dépendances internes d'OpenCV, présentes dans l'APK. L'archive OpenCV ne fournit aucun texte de licence pour ces composants |
| AndroidX Activity 1.12.4 et AndroidX Core 1.17.0 (`activity-ktx`, `core-ktx`) | Apache-2.0 | Android : activité, sélecteur de médias, compatibilité |
| Kotlin (bibliothèque standard) 2.3.21 | Apache-2.0 | Android : exécution du code Kotlin |
| Autres dépendances Java de l'application Android (AndroidX, Guava 33.3.1-android, kotlinx-coroutines 1.9.0, annotations JetBrains, etc.) | Apache-2.0 (une exception : `checker-qual` 3.43.0, MIT) | Android : dépendances transitives de Media3 et d'AndroidX |
| JUnit 4.13.2 | EPL-1.0 | Android : tests unitaires JVM. Non inclus dans l'APK |

## Notes (application Android)

- Les licences Java sont celles déclarées dans les fichiers POM des 60 artefacts résolus par Gradle pour l'exécution (`./gradlew :app:dependencies --configuration debugRuntimeClasspath`) : 59 sous Apache-2.0, 1 sous MIT (`org.checkerframework:checker-qual` 3.43.0). Il s'agit d'un relevé technique, pas d'une revue juridique.
- Les noms et versions des composants natifs d'OpenCV proviennent du rapport de configuration inclus dans `libopencv_java4.so`. L'inventaire de leurs licences reste à faire.
- L'APK n'embarque pas encore les textes de licence ni l'avis de copyright du modèle YuNet (MIT). À ajouter (écran « Licences » ou fichiers dans l'APK) avant toute diffusion publique.

## Application iOS

| Dépendance | Licence | Utilisation |
|---|---|---|
| OpenCV 4.14.0, cadre iOS publié par le projet OpenCV (`opencv-4.14.0-ios-framework.zip`, SHA-256 `f4f428fa9270adf95b3ed4705eb18ba3028ed2c2777a4f1a002739b869986a6a`) | Apache-2.0 | iOS : exécution de YuNet (`FaceDetectorYN`), réduction des images, rendu du flou. Bibliothèque statique liée à l'application ; seuls les modules utilisés sont retenus à l'édition de liens |
| Composants internes du cadre OpenCV pour iOS (zlib, Protobuf, libjpeg-turbo, libpng, etc.) | **À inventorier** | iOS : comme pour Android, aucun texte de licence n'est fourni avec le cadre |
| Modèle YuNet `face_detection_yunet_2023mar.onnx` (OpenCV Zoo, © 2020 Shiqi Yu) | MIT | iOS : même fichier que l'application Android (`android/app/src/main/assets/models/`), copié dans l'application |
| Cadres d'Apple (AVFoundation, CoreMedia, CoreVideo, SwiftUI, Photos, etc.) | Bibliothèques système | iOS : décodage, encodage, interface |
| XcodeGen | MIT | Compilation uniquement (génération du projet Xcode). Non inclus dans l'application |
| Image `samples/data/messi5.jpg` du dépôt OpenCV | Celle du dépôt OpenCV | Tests sur simulateur uniquement : téléchargée par la compilation, ni versionnée ni distribuée |

## Notes (application iOS)

- L'application comporte un écran « Licences » : textes de la GPL-3.0 (blurr), de la licence MIT de YuNet et de la licence Apache 2.0 d'OpenCV.
- Le manifeste de confidentialité (`ios/Blurr/Resources/PrivacyInfo.xcprivacy`) déclare l'absence de suivi et de données collectées, et les raisons d'usage des API concernées (réglages, espace disque, horodatage de fichiers, mesure de durées).
