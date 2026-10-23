// Banc de parité du rendu C++ (Blurr/Engine/MaskRenderer.cpp) contre la version PC (render.py).
//
// Usage : render_cli <largeur> <hauteur> <canaux> <style 0=flou 1=noir> <image.raw> <ellipses.f32> <sortie.raw>
// image.raw : octets BGR ou BGRA, ligne par ligne ; ellipses.f32 : float32 [cx, cy, rx, ry] * n.
#include "../../Blurr/Engine/MaskRenderer.hpp"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <vector>

static std::vector<char> readAll(const char* path) {
    std::ifstream in(path, std::ios::binary);
    return std::vector<char>((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
}

int main(int argc, char** argv) {
    if (argc != 8) {
        std::fprintf(stderr, "usage : %s w h canaux style image.raw ellipses.f32 sortie.raw\n", argv[0]);
        return 2;
    }
    const int w = std::atoi(argv[1]);
    const int h = std::atoi(argv[2]);
    const int cn = std::atoi(argv[3]);
    const int style = std::atoi(argv[4]);
    std::vector<char> pixels = readAll(argv[5]);
    std::vector<char> raw = readAll(argv[6]);
    if (pixels.size() != size_t(w) * size_t(h) * size_t(cn)) {
        std::fprintf(stderr, "taille d'image incohérente\n");
        return 2;
    }
    std::vector<float> ellipses(raw.size() / sizeof(float));
    std::memcpy(ellipses.data(), raw.data(), ellipses.size() * sizeof(float));

    cv::Mat frame(h, w, cn == 4 ? CV_8UC4 : CV_8UC3, pixels.data());
    blurr::MaskRenderer renderer(w, h, style == 1 ? blurr::MaskStyle::Black : blurr::MaskStyle::Blur);
    const int drawn = renderer.apply(frame, ellipses.data(), int(ellipses.size() / 4));
    std::ofstream out(argv[7], std::ios::binary);
    out.write(pixels.data(), std::streamsize(pixels.size()));
    std::printf("%d\n", drawn);
    return 0;
}
