// Rendu du masquage sur processeur : portage C++ de desktop/src/blurr/render.py (version PC), lui-même équivalent
// du shader de MaskEffect.kt (Android v0.2), à 1/255 près.
//
// Déroulé d'une image :
//  1. si au moins un visage est à flouter, réduction de l'image en pyramide (niveaux 1/2, 1/4, ...), uniquement
//     jusqu'au niveau dont les visages de l'image ont besoin ;
//  2. pour chaque ellipse, flou reconstruit depuis la pyramide par B-spline cubique ou noir opaque, mélangé à
//     l'image avec un bord adouci calculé analytiquement à la résolution de sortie.
//
// Les ellipses sont dessinées par niveau de flou croissant : là où deux ellipses se recouvrent, le flou le plus fort
// l'emporte. Conventions du shader Android : centres de pixels en (i + 0,5) / taille, bords des niveaux répétés,
// niveaux de pyramide quantifiés sur 8 bits.
//
// Dépend uniquement des modules core et imgproc d'OpenCV : compilé dans l'application iOS et dans le banc de test
// Linux (ios/Tools/render-parity).
#pragma once

#include <opencv2/core.hpp>

#include <vector>

namespace blurr {

enum class MaskStyle { Blur = 0, Black = 1 };

namespace geometry {
constexpr double kCellsPerEllipse = 8.0;
constexpr double kMinLevel = 1.0;
constexpr int kMaxLevels = 12;
constexpr double kEdgeStart = 0.92;
constexpr double kEdgePadPx = 1.5;

/// Niveau de pyramide (fractionnaire) pour une ellipse de demi-axes rxPx x ryPx pixels.
double level(double rxPx, double ryPx);

/// Taille du niveau k de la pyramide d'une image de size pixels (division par 2 arrondie au supérieur).
int levelSize(int size, int k);
}  // namespace geometry

struct RenderStats {
    long frames = 0;
    long maskedFrames = 0;
    long drawnEllipses = 0;
};

class MaskRenderer {
public:
    MaskRenderer(int width, int height, MaskStyle style);

    /// Masque `count` ellipses [cx, cy, rx, ry] (normalisées) sur `frame` (CV_8UC3 ou CV_8UC4, modifiée sur place,
    /// de la taille donnée au constructeur). Renvoie le nombre d'ellipses dessinées.
    int apply(cv::Mat& frame, const float* ellipses, int count);

    const RenderStats& stats() const { return stats_; }
    int width() const { return width_; }
    int height() const { return height_; }

private:
    struct Taps {
        // Pour chaque pixel de sortie d'un axe : jusqu'à 4 texels (indices bornés, doublons fusionnés) et poids.
        std::vector<int> index;   // 4 par pixel
        std::vector<float> weight;  // 4 par pixel
        std::vector<int> count;   // nombre de texels utiles par pixel
        std::vector<int> first;   // premier texel couvert (borné)
        std::vector<int> last;    // dernier texel couvert (borné)
    };
    struct AxisPair {
        bool ready = false;
        Taps x;
        Taps y;
    };

    bool draw(cv::Mat& frame, double cx, double cy, double rxp, double ryp, double lv);
    void sample(int k, int x0, int x1, int y0, int y1, cv::Mat& out);
    const AxisPair& axes(int k);
    static Taps makeTaps(int outSize, int levelSize);
    void buildPyramid(const cv::Mat& frame, int levels);

    int width_;
    int height_;
    MaskStyle style_;
    std::vector<cv::Size> sizes_;
    std::vector<AxisPair> axes_;
    std::vector<cv::Mat> pyramid_;  // pyramid_[0] : en-tête sur l'image courante
    RenderStats stats_;
    // Tampons réutilisés.
    cv::Mat color_, upper_, color8_, alpha_, beta_, region_, rowTmp_;
};

}  // namespace blurr
