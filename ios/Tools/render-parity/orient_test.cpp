// Vérifie que le redressement C++ (AnalysisImage.cpp) place chaque point là où DisplayOrientation.toDisplay
// (BlurrCore, Swift) l'attend, pour les 8 orientations (4 rotations, avec ou sans symétrie).
//
// Compilation (une ligne) : g++ -std=c++17 -I/usr/include/opencv4 ../../Blurr/Engine/AnalysisImage.cpp
// orient_test.cpp -lopencv_core -lopencv_imgproc -o orient_test && ./orient_test
#include "../../Blurr/Engine/AnalysisImage.hpp"

#include <cstdio>

struct Orientation {
    int a, b, c, d;  // M = [a c; b d], x' = a x + c y, y' = b x + d y (coordonnées centrées)
};

static bool mirroredOf(const Orientation& o) { return o.a * o.d - o.b * o.c == -1; }

static int rotationOf(const Orientation& o) {
    const int r00 = mirroredOf(o) ? -o.a : o.a;
    const int r10 = mirroredOf(o) ? -o.b : o.b;
    if (r00 == 1 && r10 == 0) return 0;
    if (r00 == 0 && r10 == 1) return 90;
    if (r00 == -1 && r10 == 0) return 180;
    return 270;
}

int main() {
    const Orientation all[] = {
        {1, 0, 0, 1}, {0, 1, -1, 0}, {-1, 0, 0, -1}, {0, -1, 1, 0},
        {-1, 0, 0, 1}, {1, 0, 0, -1}, {0, 1, 1, 0}, {0, -1, -1, 0},
    };
    const int W = 7, H = 4;  // dimensions impaires : détecte les erreurs d'un pixel
    int failures = 0;
    for (const Orientation& o : all) {
        for (int py = 0; py < H; ++py) {
            for (int px = 0; px < W; ++px) {
                cv::Mat img(H, W, CV_8UC1, cv::Scalar(0));
                img.at<uchar>(py, px) = 255;
                cv::Mat work;
                const cv::Mat& out = blurr::orientImage(img, mirroredOf(o), rotationOf(o), work);
                // Position attendue : centre du pixel transformé autour du centre de l'image.
                const double xc = px + 0.5 - W / 2.0;
                const double yc = py + 0.5 - H / 2.0;
                const double xd = o.a * xc + o.c * yc;
                const double yd = o.b * xc + o.d * yc;
                const bool swap = o.a == 0;
                const int dw = swap ? H : W;
                const int dh = swap ? W : H;
                const int ex = int(xd + dw / 2.0 - 0.5 + 0.25);
                const int ey = int(yd + dh / 2.0 - 0.5 + 0.25);
                cv::Point found(-1, -1);
                cv::minMaxLoc(out, nullptr, nullptr, nullptr, &found);
                if (out.cols != dw || out.rows != dh || found.x != ex || found.y != ey) {
                    std::printf("ÉCHEC M=[%d %d; %d %d] point (%d,%d) : attendu (%d,%d) obtenu (%d,%d) taille %dx%d\n",
                                o.a, o.c, o.b, o.d, px, py, ex, ey, found.x, found.y, out.cols, out.rows);
                    ++failures;
                }
            }
        }
    }
    const cv::Size s1 = blurr::analysisSize(1920, 1080, 1280);
    const cv::Size s2 = blurr::analysisSize(1366, 768, 960);
    const cv::Size s3 = blurr::analysisSize(640, 360, 1280);
    if (s1 != cv::Size(1280, 720) || s2 != cv::Size(960, 540) || s3 != cv::Size(640, 360)) {
        std::printf("ÉCHEC analysisSize\n");
        ++failures;
    }
    std::printf("%s : %d échec(s)\n", failures ? "ÉCHEC" : "OK", failures);
    return failures ? 1 : 0;
}
