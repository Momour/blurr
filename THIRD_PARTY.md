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
