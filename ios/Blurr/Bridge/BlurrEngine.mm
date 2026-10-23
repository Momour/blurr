// Implémentation Objective-C++ du pont vers le moteur C++. Les en-têtes OpenCV sont inclus avant ceux d'Apple
// (conflits de macros connus sinon).
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/objdetect.hpp>

#include "../Engine/AnalysisImage.hpp"
#include "../Engine/MaskRenderer.hpp"

#include <algorithm>
#include <memory>
#include <string>

#import "BlurrEngine.h"

static NSString *const BLREngineErrorDomain = @"blurr.engine";

static NSError *BLRError(NSString *message) {
    return [NSError errorWithDomain:BLREngineErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey : message}];
}

static NSString *BLRString(const std::string &s) {
    NSString *out = [NSString stringWithUTF8String:s.c_str()];
    return out ?: @"(message illisible)";
}

// ---------------------------------------------------------------------------------------------- détection

@implementation BLRFaceDetector {
    cv::Ptr<cv::FaceDetectorYN> _detector;
    cv::Size _inputSize;
    cv::Mat _faces;
    cv::Mat _small;
    cv::Mat _bgr;
    cv::Mat _upright;
}

- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                            scoreThreshold:(float)scoreThreshold
                                     error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    try {
        // Mêmes paramètres qu'Android et que la version PC : NMS 0,3, 5 000 visages au plus.
        _detector = cv::FaceDetectorYN::create(std::string(modelPath.fileSystemRepresentation), "", cv::Size(320, 320),
                                               scoreThreshold, 0.3f, 5000);
    } catch (const cv::Exception &e) {
        if (error) *error = BLRError([@"Chargement du modèle YuNet impossible : " stringByAppendingString:BLRString(e.what())]);
        return nil;
    }
    if (_detector.empty()) {
        if (error) *error = BLRError(@"Chargement du modèle YuNet impossible.");
        return nil;
    }
    return self;
}

- (nullable NSData *)detectInPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                 maxSide:(int)maxSide
                                mirrored:(BOOL)mirrored
                                rotation:(int)rotation {
    if (CVPixelBufferGetPixelFormatType(pixelBuffer) != kCVPixelFormatType_32BGRA) {
        _lastError = @"Format d'image inattendu (BGRA attendu).";
        return nil;
    }
    if (CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) {
        _lastError = @"Image décodée inaccessible.";
        return nil;
    }
    NSMutableData *out = nil;
    try {
        const int width = int(CVPixelBufferGetWidth(pixelBuffer));
        const int height = int(CVPixelBufferGetHeight(pixelBuffer));
        cv::Mat bgra(height, width, CV_8UC4, CVPixelBufferGetBaseAddress(pixelBuffer),
                     CVPixelBufferGetBytesPerRow(pixelBuffer));
        // L'image préparée est une copie : le tampon décodé peut être libéré tout de suite.
        const cv::Mat &image = blurr::prepareAnalysisImage(bgra, maxSide, mirrored, rotation, _small, _bgr, _upright);
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        pixelBuffer = nullptr;

        if (image.size() != _inputSize) {
            _detector->setInputSize(image.size());
            _inputSize = image.size();
        }
        _lastWidth = image.cols;
        _lastHeight = image.rows;
        _detector->detect(image, _faces);
        const int count = _faces.empty() ? 0 : _faces.rows;
        out = [NSMutableData dataWithLength:size_t(count) * 5 * sizeof(float)];
        float *dst = static_cast<float *>(out.mutableBytes);
        const float w = float(image.cols);
        const float h = float(image.rows);
        for (int i = 0; i < count; ++i) {
            const float *row = _faces.ptr<float>(i);
            // Colonnes YuNet : x, y, largeur, hauteur, 5 points de repère (10 valeurs), score.
            dst[i * 5 + 0] = row[0] / w;
            dst[i * 5 + 1] = row[1] / h;
            dst[i * 5 + 2] = row[2] / w;
            dst[i * 5 + 3] = row[3] / h;
            dst[i * 5 + 4] = row[_faces.cols - 1];
        }
        _lastError = nil;
    } catch (const cv::Exception &e) {
        if (pixelBuffer) CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        _lastError = [@"Détection impossible : " stringByAppendingString:BLRString(e.what())];
        return nil;
    }
    return out;
}

@end

// ---------------------------------------------------------------------------------------------- rendu

@implementation BLRMaskRenderer {
    std::unique_ptr<blurr::MaskRenderer> _renderer;
    BOOL _black;
}

- (instancetype)initWithWidth:(int)width height:(int)height black:(BOOL)black {
    self = [super init];
    if (self) {
        _black = black;
        _renderer = std::make_unique<blurr::MaskRenderer>(std::max(1, width), std::max(1, height),
                                                          black ? blurr::MaskStyle::Black : blurr::MaskStyle::Blur);
    }
    return self;
}

- (int)applyToPixelBuffer:(CVPixelBufferRef)pixelBuffer ellipses:(const float *)ellipses count:(int)count {
    _frames += 1;
    if (count <= 0 || ellipses == nullptr) return 0;
    if (CVPixelBufferGetPixelFormatType(pixelBuffer) != kCVPixelFormatType_32BGRA) {
        _lastError = @"Format d'image inattendu (BGRA attendu).";
        return -1;
    }
    if (CVPixelBufferLockBaseAddress(pixelBuffer, 0) != kCVReturnSuccess) {
        _lastError = @"Image décodée inaccessible en écriture.";
        return -1;
    }
    int drawn = -1;
    try {
        const int width = int(CVPixelBufferGetWidth(pixelBuffer));
        const int height = int(CVPixelBufferGetHeight(pixelBuffer));
        if (width != _renderer->width() || height != _renderer->height()) {
            _renderer = std::make_unique<blurr::MaskRenderer>(width, height,
                                                              _black ? blurr::MaskStyle::Black : blurr::MaskStyle::Blur);
        }
        cv::Mat frame(height, width, CV_8UC4, CVPixelBufferGetBaseAddress(pixelBuffer),
                      CVPixelBufferGetBytesPerRow(pixelBuffer));
        drawn = _renderer->apply(frame, ellipses, count);
        _lastError = nil;
    } catch (const cv::Exception &e) {
        _lastError = [@"Rendu impossible : " stringByAppendingString:BLRString(e.what())];
        drawn = -1;
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    if (drawn > 0) {
        _maskedFrames += 1;
        _drawnEllipses += drawn;
    }
    return drawn;
}

@end

// ---------------------------------------------------------------------------------------------- divers

@implementation BLREngineInfo

+ (NSString *)openCVVersion {
    return @CV_VERSION;
}

+ (BOOL)performCatchingExceptions:(NS_NOESCAPE void (^)(void))block error:(NSError **)error {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = BLRError([NSString stringWithFormat:@"%@ : %@", exception.name, exception.reason ?: @""]);
        }
        return NO;
    }
}

@end
