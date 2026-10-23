// Préparation des images pour le détecteur (équivalent de FramePreprocessor.kt, Android v0.2) : réduction de
// l'image codée (INTER_AREA, plus grand côté ramené à maxSide), conversion BGRA vers BGR, puis redressement
// (symétrie horizontale éventuelle, rotation horaire) pour obtenir l'image affichée.
//
// Dépend uniquement des modules core et imgproc d'OpenCV.
#pragma once

#include <opencv2/core.hpp>

namespace blurr {

/// Taille de l'image analysée (repère codé) : plus grand côté ramené à maxSide, arrondi au plus proche (demi vers le
/// haut), 2 pixels au minimum. Identique à Android, à la version PC et à `analysisSize` (BlurrCore).
cv::Size analysisSize(int width, int height, int maxSide);

/// Image BGR redressée et réduite, prête pour le détecteur. `bgra` : image codée CV_8UC4. Les tampons `small`, `bgr`
/// et `upright` sont réutilisés d'un appel à l'autre ; la référence renvoyée désigne l'un d'eux.
const cv::Mat& prepareAnalysisImage(const cv::Mat& bgra, int maxSide, bool mirrored, int rotationDegrees,
                                    cv::Mat& small, cv::Mat& bgr, cv::Mat& upright);

/// Redresse une image : symétrie horizontale si `mirrored`, puis rotation horaire de `rotationDegrees` (0, 90, 180,
/// 270). Renvoie `src` si aucune opération n'est nécessaire, sinon `work`.
const cv::Mat& orientImage(const cv::Mat& src, bool mirrored, int rotationDegrees, cv::Mat& work);

}  // namespace blurr
