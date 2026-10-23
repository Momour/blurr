// Interface Objective-C du moteur C++ (OpenCV) : détection YuNet et rendu du masquage, utilisée depuis Swift.
// Aucun type C++ n'apparaît ici : ce fichier est importé par l'en-tête de pont Swift.
#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

/// Détecteur de visages YuNet (OpenCV Zoo, licence MIT) exécuté par OpenCV. Une instance par fil d'exécution.
@interface BLRFaceDetector : NSObject

- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                            scoreThreshold:(float)scoreThreshold
                                     error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Détecte les visages d'une image BGRA du repère codé : réduction (plus grand côté ramené à `maxSide`, INTER_AREA),
/// symétrie horizontale si `mirrored`, rotation horaire de `rotation` degrés, puis YuNet.
/// Renvoie [x, y, w, h, score] par visage (float32), normalisés dans l'image affichée ; nil en cas d'erreur
/// (voir `lastError`).
- (nullable NSData *)detectInPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                 maxSide:(int)maxSide
                                mirrored:(BOOL)mirrored
                                rotation:(int)rotation NS_SWIFT_NAME(detect(pixelBuffer:maxSide:mirrored:rotation:));

/// Taille de la dernière image analysée (repère affiché), pour le journal.
@property (nonatomic, readonly) int lastWidth;
@property (nonatomic, readonly) int lastHeight;
@property (nonatomic, readonly, copy, nullable) NSString *lastError;

@end

/// Flou pyramidal ou masque noir sur une image BGRA, modifiée sur place (portage du rendu de la version PC).
@interface BLRMaskRenderer : NSObject

- (instancetype)initWithWidth:(int)width height:(int)height black:(BOOL)black NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// `ellipses` : [cx, cy, rx, ry] * `count`, normalisés dans l'image fournie (repère codé). Renvoie le nombre
/// d'ellipses dessinées, ou -1 en cas d'erreur (voir `lastError`).
- (int)applyToPixelBuffer:(CVPixelBufferRef)pixelBuffer
                 ellipses:(const float *_Nullable)ellipses
                    count:(int)count NS_SWIFT_NAME(apply(pixelBuffer:ellipses:count:));

@property (nonatomic, readonly) long frames;
@property (nonatomic, readonly) long maskedFrames;
@property (nonatomic, readonly) long drawnEllipses;
@property (nonatomic, readonly, copy, nullable) NSString *lastError;

@end

@interface BLREngineInfo : NSObject
/// Version d'OpenCV liée à l'application.
+ (NSString *)openCVVersion;
/// Exécute `block` et convertit une éventuelle exception Objective-C (AVFoundation) en erreur, au lieu d'arrêter
/// l'application.
+ (BOOL)performCatchingExceptions:(NS_NOESCAPE void (^)(void))block
                            error:(NSError **)error NS_SWIFT_NAME(catchingExceptions(_:));
@end

NS_ASSUME_NONNULL_END
