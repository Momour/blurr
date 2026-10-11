# blurr : application Android (MVP v0.1)

Floute les visages d'une vidéo, hors ligne. Détection YuNet (OpenCV), export Media3, aucune permission Internet.

Compilation rapide (JDK 17 ou plus, SDK Android 36, `local.properties` avec `sdk.dir=...`) :

```
./gradlew assembleDebug testDebugUnitTest
```

APK produit : `app/build/outputs/apk/debug/app-debug.apk`.

Sources principales : `app/src/main/java/app/blurr/` (`MainActivity` interface, `Analyzer` et `FrameSources` analyse, `MaskPlan` et `MaskEffect` masquage, `Exporter` export, `Verifier` contrôle du résultat).
