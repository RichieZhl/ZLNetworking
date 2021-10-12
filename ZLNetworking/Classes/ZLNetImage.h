//
//  ZLNetImage.h
//  ZLNetworking_Example
//
//  Created by lylaut on 2021/10/12.
//  Copyright © 2021 richiezhl. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreServices/CoreServices.h>

#define kZLUTTypeHEIC ((__bridge CFStringRef)@"public.heic")
#define kZLUTTypeHEIF ((__bridge CFStringRef)@"public.heif")
// HEIC Sequence (Animated Image)
#define kZLUTTypeHEICS ((__bridge CFStringRef)@"public.heics")
// kUTTypeWebP seems not defined in public UTI framework, Apple use the hardcode string, we define them :)
#define kZLUTTypeWebP ((__bridge CFStringRef)@"org.webmproject.webp")

typedef NS_ENUM(NSInteger, ZLImageFormat) {
    ZLImageFormatUndefined = -1,
    ZLImageFormatJPEG      = 0,
    ZLImageFormatPNG       = 1,
    ZLImageFormatGIF       = 2,
    ZLImageFormatTIFF      = 3,
    ZLImageFormatWebP      = 4,
    ZLImageFormatHEIC      = 5,
    ZLImageFormatHEIF      = 6,
    ZLImageFormatPDF       = 7,
    ZLImageFormatSVG       = 8
};

extern NSUInteger ZLDeviceTotalMemory(void);

extern NSUInteger ZLDeviceFreeMemory(void);

extern ZLImageFormat zl_imageFormatForImageData(NSData *_Nullable data);

extern _Nonnull CFStringRef zl_UTTypeFromImageFormat(ZLImageFormat format);

extern ZLImageFormat zl_imageFormatFromUTType(CFStringRef _Nullable uttype);

extern BOOL ZLImageHasAlpha(CGImageRef _Nullable image);

@protocol ZLAnimatedImage <NSObject>
@property (nonatomic, assign, readonly) NSUInteger animatedImageFrameCount;
@property (nonatomic, assign, readonly) NSUInteger animatedImageLoopCount;

- (nullable UIImage *)animatedImageFrameAtIndex:(NSUInteger)index;
- (NSTimeInterval)animatedImageDurationAtIndex:(NSUInteger)index;

@end

@interface ZLAnimatedImage : UIImage <ZLAnimatedImage>

@end

@interface ZLAnimatedImageView : UIImageView

@end

@interface UIImage (ZLNet)

+ (UIImage *_Nullable)zl_imageWithData:(NSData *_Nullable)data;

+ (UIImage *_Nullable)zl_imageWithContentsOfFile:(NSString *_Nullable)path;

+ (ZLAnimatedImage *_Nullable)zl_animatedImageWithData:(NSData *_Nullable)data scale:(CGFloat)scale;

- (NSData *_Nullable)zl_imageDataWithQuality:(float)quality;

@end

@interface UIImageView (ZLNet)

/**
 * Set the imageView `image` with an `url`, placeholder, custom options and context.
 *
 * The download is asynchronous and cached.
 *
 * @param url            The url for the image.
 * @param placeholder    The image to be set initially, until the image request finishes.
 * @param progressBlock  A block called while image is downloading
 *                       @note the progress block is executed on a background queue
 * @param completedBlock A block called when operation has been completed. This block has no return value
 *                       and takes the requested UIImage as first parameter. In case of error the image parameter
 *                       is nil and the second parameter may contain an NSError. The third parameter is a Boolean
 *                       indicating if the image was retrieved from the local cache or from the network.
 *                       The fourth parameter is the original image url.
 */
- (void)zl_setImageWithURL:(nullable NSURL *)url
          placeholderImage:(nullable UIImage *)placeholder
                  progress:(nullable void (^)(float progress))progressBlock
                 completed:(nullable void (^)(UIImage * _Nullable image, NSError * _Nullable error))completedBlock;

- (void)zl_setImageWithURL:(nullable NSURL *)url
          placeholderImage:(nullable UIImage *)placeholder;

- (void)zl_setImageWithURL:(nullable NSURL *)url;

@end
