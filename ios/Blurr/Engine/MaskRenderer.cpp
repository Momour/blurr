// Portage C++ de desktop/src/blurr/render.py : voir MaskRenderer.hpp.
//
// Les calculs suivent l'ordre et la précision de la version Python (coordonnées et poids en double, accumulations
// en float, arrondi et mélange par OpenCV) : l'écart attendu avec elle est d'au plus 1/255 (ordre des sommes).
#if defined(__clang__)
#pragma clang fp contract(off)
#endif

#include "MaskRenderer.hpp"

#include <opencv2/imgproc.hpp>

#include <algorithm>
#include <cmath>
#include <numeric>

namespace blurr {

namespace geometry {

double level(double rxPx, double ryPx) {
    const double diameter = 2.0 * std::max(rxPx, ryPx);
    if (!(diameter > 0)) return kMinLevel;
    const double lv = std::log2(diameter / kCellsPerEllipse);
    return std::min(std::max(kMinLevel, lv), double(kMaxLevels - 1));
}

int levelSize(int size, int k) {
    int s = size;
    for (int i = 0; i < k; ++i) s = std::max(1, (s + 1) / 2);
    return s;
}

}  // namespace geometry

MaskRenderer::MaskRenderer(int width, int height, MaskStyle style)
    : width_(width), height_(height), style_(style) {
    CV_Assert(width > 0 && height > 0);
    sizes_.reserve(geometry::kMaxLevels + 1);
    for (int k = 0; k <= geometry::kMaxLevels; ++k) {
        sizes_.emplace_back(geometry::levelSize(width, k), geometry::levelSize(height, k));
    }
    axes_.resize(geometry::kMaxLevels + 1);
    pyramid_.resize(geometry::kMaxLevels + 1);
}

MaskRenderer::Taps MaskRenderer::makeTaps(int outSize, int levelSize) {
    Taps t;
    t.index.assign(size_t(outSize) * 4, 0);
    t.weight.assign(size_t(outSize) * 4, 0.f);
    t.count.assign(size_t(outSize), 0);
    t.first.assign(size_t(outSize), 0);
    t.last.assign(size_t(outSize), 0);
    const int maxIndex = levelSize - 1;
    for (int p = 0; p < outSize; ++p) {
        const double center = (double(p) + 0.5) / double(outSize);
        const double x = center * double(levelSize) - 0.5;
        const double fi = std::floor(x);
        const double f = x - fi;
        const int i = int(fi);
        const double f2 = f * f;
        const double f3 = f2 * f;
        const double w[4] = {
            (1.0 - 3.0 * f + 3.0 * f2 - f3) / 6.0,
            (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0,
            (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) / 6.0,
            f3 / 6.0,
        };
        // Indices bornés (bord répété) ; les doublons s'additionnent, comme dans la version Python.
        int idx[4];
        double acc[4];
        int n = 0;
        for (int tap = 0; tap < 4; ++tap) {
            const int j = std::min(std::max(i - 1 + tap, 0), maxIndex);
            int found = -1;
            for (int q = 0; q < n; ++q) {
                if (idx[q] == j) {
                    found = q;
                    break;
                }
            }
            if (found >= 0) {
                acc[found] += w[tap];
            } else {
                idx[n] = j;
                acc[n] = w[tap];
                ++n;
            }
        }
        t.count[size_t(p)] = n;
        for (int q = 0; q < n; ++q) {
            t.index[size_t(p) * 4 + size_t(q)] = idx[q];
            t.weight[size_t(p) * 4 + size_t(q)] = float(acc[q]);
        }
        t.first[size_t(p)] = std::min(std::max(i - 1, 0), maxIndex);
        t.last[size_t(p)] = std::min(std::max(i + 2, 0), maxIndex);
    }
    return t;
}

const MaskRenderer::AxisPair& MaskRenderer::axes(int k) {
    AxisPair& a = axes_[size_t(k)];
    if (!a.ready) {
        a.x = makeTaps(width_, sizes_[size_t(k)].width);
        a.y = makeTaps(height_, sizes_[size_t(k)].height);
        a.ready = true;
    }
    return a;
}

void MaskRenderer::buildPyramid(const cv::Mat& frame, int levels) {
    // Chaque niveau est l'échantillonnage bilinéaire du précédent au centre de ses pixels (moyenne exacte des blocs
    // 2 x 2 quand la taille est paire), comme le rendu de la pyramide par le GPU sur Android.
    pyramid_[0] = frame;
    for (int k = 1; k <= levels; ++k) {
        cv::resize(pyramid_[size_t(k - 1)], pyramid_[size_t(k)], sizes_[size_t(k)], 0, 0, cv::INTER_LINEAR);
    }
}

void MaskRenderer::sample(int k, int x0, int x1, int y0, int y1, cv::Mat& out) {
    const AxisPair& ax = axes(k);
    const cv::Mat& level = pyramid_[size_t(k)];
    const int cn = level.channels();
    const int nu = x1 - x0;
    const int nv = y1 - y0;
    const int c0 = ax.x.first[size_t(x0)];
    const int c1 = ax.x.last[size_t(x1 - 1)] + 1;
    const int span = (c1 - c0) * cn;
    out.create(nv, nu, CV_32FC(cn));
    rowTmp_.create(1, span, CV_32F);
    float* tmp = rowTmp_.ptr<float>(0);
    for (int i = 0; i < nv; ++i) {
        const size_t y = size_t(y0 + i);
        const int cy = ax.y.count[y];
        // Passe verticale sur les colonnes utiles du niveau.
        for (int a = 0; a < cy; ++a) {
            const uchar* row = level.ptr<uchar>(ax.y.index[y * 4 + size_t(a)]) + size_t(c0) * size_t(cn);
            const float wa = ax.y.weight[y * 4 + size_t(a)];
            if (a == 0) {
                for (int t = 0; t < span; ++t) tmp[t] = wa * float(row[t]);
            } else {
                for (int t = 0; t < span; ++t) tmp[t] += wa * float(row[t]);
            }
        }
        // Passe horizontale.
        float* o = out.ptr<float>(i);
        for (int j = 0; j < nu; ++j) {
            const size_t x = size_t(x0 + j);
            const int cx = ax.x.count[x];
            for (int ch = 0; ch < cn; ++ch) {
                float s = 0.f;
                for (int b = 0; b < cx; ++b) {
                    s += ax.x.weight[x * 4 + size_t(b)] * tmp[(ax.x.index[x * 4 + size_t(b)] - c0) * cn + ch];
                }
                o[j * cn + ch] = s;
            }
        }
    }
}

bool MaskRenderer::draw(cv::Mat& frame, double cx, double cy, double rxp, double ryp, double lv) {
    if (!(rxp > 0) || !(ryp > 0)) return false;
    const double w = double(width_);
    const double h = double(height_);
    // Pixels dont le centre est dans le rectangle englobant l'ellipse (règle de rastérisation OpenGL).
    auto clampEdge = [](double v, double hi) { return int(std::min(std::max(v, 0.0), hi)); };
    const int x0 = clampEdge(std::ceil((cx - rxp) * w - 0.5), w);
    const int x1 = clampEdge(std::ceil((cx + rxp) * w - 0.5), w);
    const int y0 = clampEdge(std::ceil((cy - ryp) * h - 0.5), h);
    const int y1 = clampEdge(std::ceil((cy + ryp) * h - 0.5), h);
    if (x1 <= x0 || y1 <= y0) return false;
    const int nu = x1 - x0;
    const int nv = y1 - y0;

    // Opacité : 1 - smoothstep(EDGE_START, 1, r), r calculé en float comme dans la version Python.
    std::vector<float> dx2(static_cast<size_t>(nu));
    std::vector<float> dy2(static_cast<size_t>(nv));
    for (int j = 0; j < nu; ++j) {
        const double d = ((double(x0 + j) + 0.5) / w - cx) / rxp;
        dx2[size_t(j)] = float(d * d);
    }
    for (int i = 0; i < nv; ++i) {
        const double d = ((double(y0 + i) + 0.5) / h - cy) / ryp;
        dy2[size_t(i)] = float(d * d);
    }
    const float edge = float(geometry::kEdgeStart);
    const float inv = float(1.0 / (1.0 - geometry::kEdgeStart));
    alpha_.create(nv, nu, CV_32F);
    beta_.create(nv, nu, CV_32F);
    bool any = false;
    for (int i = 0; i < nv; ++i) {
        float* a = alpha_.ptr<float>(i);
        float* b = beta_.ptr<float>(i);
        for (int j = 0; j < nu; ++j) {
            const float r = std::sqrt(dy2[size_t(i)] + dx2[size_t(j)]);
            float t = (r - edge) * inv;
            t = std::min(std::max(t, 0.f), 1.f);
            const float cover = 1.0f - t * t * (3.0f - 2.0f * t);
            a[j] = cover;
            b[j] = 1.0f - cover;
            any = any || cover != 0.f;
        }
    }
    if (!any) return false;

    cv::Mat roi = frame(cv::Rect(x0, y0, nu, nv));
    const int cn = frame.channels();
    if (style_ == MaskStyle::Black || pyramid_[1].empty()) {
        color8_.create(nv, nu, frame.type());
        color8_.setTo(cn == 4 ? cv::Scalar(0, 0, 0, 255) : cv::Scalar(0, 0, 0));
    } else {
        const int lower = std::min(int(std::floor(lv)), geometry::kMaxLevels - 1);
        const double mix = std::min(std::max(lv - double(lower), 0.0), 1.0);
        sample(lower, x0, x1, y0, y1, color_);
        if (mix > 0) {
            sample(lower + 1, x0, x1, y0, y1, upper_);
            const float m = float(mix);
            for (int i = 0; i < nv; ++i) {
                float* c = color_.ptr<float>(i);
                const float* u = upper_.ptr<float>(i);
                for (int t = 0; t < nu * cn; ++t) c[t] += (u[t] - c[t]) * m;
            }
        }
        cv::convertScaleAbs(color_, color8_);  // arrondi et saturation sur 8 bits
        if (cn == 4) {
            // Canal alpha de l'image (opaque) : inchangé, quelles que soient les erreurs d'arrondi du flou.
            for (int i = 0; i < nv; ++i) {
                uchar* p = color8_.ptr<uchar>(i);
                const uchar* s = roi.ptr<uchar>(i);
                for (int j = 0; j < nu; ++j) p[j * 4 + 3] = s[j * 4 + 3];
            }
        }
    }
    // Mélange : couleur x opacité + image x (1 - opacité), arrondi sur 8 bits.
    roi.copyTo(region_);
    cv::blendLinear(color8_, region_, alpha_, beta_, roi);
    return true;
}

int MaskRenderer::apply(cv::Mat& frame, const float* ellipses, int count) {
    stats_.frames += 1;
    if (count <= 0 || ellipses == nullptr) return 0;
    CV_Assert(frame.cols == width_ && frame.rows == height_);
    CV_Assert(frame.type() == CV_8UC3 || frame.type() == CV_8UC4);
    const double w = double(width_);
    const double h = double(height_);

    const size_t n = static_cast<size_t>(count);
    std::vector<double> cx(n), cy(n), rx(n), ry(n), lv(n);
    double maxLevel = geometry::kMinLevel;
    for (int i = 0; i < count; ++i) {
        cx[size_t(i)] = double(ellipses[4 * i]);
        cy[size_t(i)] = double(ellipses[4 * i + 1]);
        rx[size_t(i)] = double(ellipses[4 * i + 2]);
        ry[size_t(i)] = double(ellipses[4 * i + 3]);
        lv[size_t(i)] = geometry::level(rx[size_t(i)] * w, ry[size_t(i)] * h);
        maxLevel = std::max(maxLevel, lv[size_t(i)]);
    }
    std::vector<int> order(n);
    std::iota(order.begin(), order.end(), 0);
    std::stable_sort(order.begin(), order.end(), [&](int a, int b) { return lv[size_t(a)] < lv[size_t(b)]; });

    if (style_ == MaskStyle::Blur) {
        // Niveaux 1 à maxLower + 1, recalculés sur l'image d'origine avant tout dessin.
        const int maxLower = std::max(1, int(std::floor(maxLevel)));
        buildPyramid(frame, std::min(maxLower + 1, geometry::kMaxLevels));
    }

    const double padX = geometry::kEdgePadPx / w;
    const double padY = geometry::kEdgePadPx / h;
    int drawn = 0;
    for (int i : order) {
        const size_t s = size_t(i);
        if (draw(frame, cx[s], cy[s], rx[s] + padX, ry[s] + padY, lv[s])) ++drawn;
    }
    if (drawn > 0) {
        stats_.maskedFrames += 1;
        stats_.drawnEllipses += drawn;
    }
    pyramid_[0].release();  // en-tête sur l'image de l'appelant : ne pas la garder
    return drawn;
}

}  // namespace blurr
