#include "AnalysisImage.hpp"

#include <opencv2/imgproc.hpp>

#include <algorithm>
#include <cmath>

namespace blurr {

cv::Size analysisSize(int width, int height, int maxSide) {
    const int longSide = std::max(width, height);
    if (longSide <= maxSide || longSide <= 0) return cv::Size(width, height);
    const double scale = double(maxSide) / double(longSide);
    const int w = int(std::floor(double(width) * scale + 0.5));
    const int h = int(std::floor(double(height) * scale + 0.5));
    return cv::Size(std::max(2, w), std::max(2, h));
}

const cv::Mat& orientImage(const cv::Mat& src, bool mirrored, int rotationDegrees, cv::Mat& work) {
    const int rot = ((rotationDegrees % 360) + 360) % 360;
    if (!mirrored && rot == 0) return src;
    const cv::Mat* current = &src;
    cv::Mat flipped;
    if (mirrored) {
        cv::flip(src, flipped, 1);
        current = &flipped;
        if (rot == 0) {
            flipped.copyTo(work);
            return work;
        }
    }
    switch (rot) {
        case 90: cv::rotate(*current, work, cv::ROTATE_90_CLOCKWISE); break;
        case 180: cv::rotate(*current, work, cv::ROTATE_180); break;
        case 270: cv::rotate(*current, work, cv::ROTATE_90_COUNTERCLOCKWISE); break;
        default: current->copyTo(work); break;
    }
    return work;
}

const cv::Mat& prepareAnalysisImage(const cv::Mat& bgra, int maxSide, bool mirrored, int rotationDegrees,
                                    cv::Mat& small, cv::Mat& bgr, cv::Mat& upright) {
    CV_Assert(bgra.type() == CV_8UC4);
    const cv::Size size = analysisSize(bgra.cols, bgra.rows, maxSide);
    const cv::Mat* current = &bgra;
    if (size != bgra.size()) {
        cv::resize(bgra, small, size, 0, 0, cv::INTER_AREA);
        current = &small;
    }
    cv::cvtColor(*current, bgr, cv::COLOR_BGRA2BGR);
    return orientImage(bgr, mirrored, rotationDegrees, upright);
}

}  // namespace blurr
