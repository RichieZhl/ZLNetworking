//
//  ZLNetImage.m
//  ZLNetworking_Example
//
//  Created by lylaut on 2021/10/12.
//  Copyright © 2021 richiezhl. All rights reserved.
//

#import "ZLNetImage.h"
#import <objc/runtime.h>
#import <mach/mach.h>
#import "ZLURLSessionManager.h"

#define ZL_CSTR(str) #str
#define ZL_NSSTRING(str) @(ZL_CSTR(str))

NSUInteger ZLDeviceTotalMemory(void) {
  return (NSUInteger)[[NSProcessInfo processInfo] physicalMemory];
}

NSUInteger ZLDeviceFreeMemory(void) {
  mach_port_t host_port = mach_host_self();
  mach_msg_type_number_t host_size = sizeof(vm_statistics_data_t) / sizeof(integer_t);
  vm_size_t page_size;
  vm_statistics_data_t vm_stat;
  kern_return_t kern;

  kern = host_page_size(host_port, &page_size);
  if (kern != KERN_SUCCESS) return 0;
  kern = host_statistics(host_port, HOST_VM_INFO, (host_info_t)&vm_stat, &host_size);
  if (kern != KERN_SUCCESS) return 0;
  return (vm_stat.free_count - vm_stat.speculative_count) * page_size;
}

ZLImageFormat zl_imageFormatForImageData(NSData *_Nullable data) {
    if (!data) {
        return ZLImageFormatUndefined;
    }
    
    // File signatures table: http://www.garykessler.net/library/file_sigs.html
    uint8_t c;
    [data getBytes:&c length:1];
    switch (c) {
        case 0xFF:
            return ZLImageFormatJPEG;
        case 0x89:
            return ZLImageFormatPNG;
        case 0x47:
            return ZLImageFormatGIF;
        case 0x49:
        case 0x4D:
            return ZLImageFormatTIFF;
        case 0x52: {
            if (data.length >= 12) {
                //RIFF....WEBP
                NSString *testString = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, 12)] encoding:NSASCIIStringEncoding];
                if ([testString hasPrefix:@"RIFF"] && [testString hasSuffix:@"WEBP"]) {
                    return ZLImageFormatWebP;
                }
            }
            break;
        }
        case 0x00: {
            if (data.length >= 12) {
                //....ftypheic ....ftypheix ....ftyphevc ....ftyphevx
                NSString *testString = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(4, 8)] encoding:NSASCIIStringEncoding];
                if ([testString isEqualToString:@"ftypheic"]
                    || [testString isEqualToString:@"ftypheix"]
                    || [testString isEqualToString:@"ftyphevc"]
                    || [testString isEqualToString:@"ftyphevx"]) {
                    return ZLImageFormatHEIC;
                }
                //....ftypmif1 ....ftypmsf1
                if ([testString isEqualToString:@"ftypmif1"] || [testString isEqualToString:@"ftypmsf1"]) {
                    return ZLImageFormatHEIF;
                }
            }
            break;
        }
        case 0x25: {
            if (data.length >= 4) {
                //%PDF
                NSString *testString = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(1, 3)] encoding:NSASCIIStringEncoding];
                if ([testString isEqualToString:@"PDF"]) {
                    return ZLImageFormatPDF;
                }
            }
        }
        case 0x3C: {
            // Check end with SVG tag
            if ([data rangeOfData:[@"</svg>" dataUsingEncoding:NSUTF8StringEncoding] options:NSDataSearchBackwards range: NSMakeRange(data.length - MIN(100, data.length), MIN(100, data.length))].location != NSNotFound) {
                return ZLImageFormatSVG;
            }
        }
    }
    return ZLImageFormatUndefined;
}

CFStringRef zl_UTTypeFromImageFormat(ZLImageFormat format) {
    CFStringRef UTType;
    switch (format) {
        case ZLImageFormatJPEG:
            UTType = kUTTypeJPEG;
            break;
        case ZLImageFormatPNG:
            UTType = kUTTypePNG;
            break;
        case ZLImageFormatGIF:
            UTType = kUTTypeGIF;
            break;
        case ZLImageFormatTIFF:
            UTType = kUTTypeTIFF;
            break;
        case ZLImageFormatWebP:
            UTType = kZLUTTypeWebP;
            break;
        case ZLImageFormatHEIC:
            UTType = kZLUTTypeHEIC;
            break;
        case ZLImageFormatHEIF:
            UTType = kZLUTTypeHEIF;
            break;
        case ZLImageFormatPDF:
            UTType = kUTTypePDF;
            break;
        case ZLImageFormatSVG:
            UTType = kUTTypeScalableVectorGraphics;
            break;
        default:
            // default is kUTTypeImage abstract type
            UTType = kUTTypeImage;
            break;
    }
    return UTType;
}

ZLImageFormat zl_imageFormatFromUTType(CFStringRef _Nullable uttype) {
    if (!uttype) {
        return ZLImageFormatUndefined;
    }
    ZLImageFormat imageFormat;
    if (CFStringCompare(uttype, kUTTypeJPEG, 0) == kCFCompareEqualTo) {
        imageFormat = ZLImageFormatJPEG;
    } else if (CFStringCompare(uttype, kUTTypePNG, 0) == kCFCompareEqualTo) {
        imageFormat = ZLImageFormatPNG;
    } else if (CFStringCompare(uttype, kUTTypeGIF, 0) == kCFCompareEqualTo) {
        imageFormat = ZLImageFormatGIF;
    } else if (CFStringCompare(uttype, kUTTypeTIFF, 0) == kCFCompareEqualTo) {
        imageFormat = ZLImageFormatTIFF;
    } else if (CFStringCompare(uttype, kZLUTTypeWebP, 0) == kCFCompareEqualTo) {
        imageFormat = ZLImageFormatWebP;
    } else if (CFStringCompare(uttype, kZLUTTypeHEIC, 0) == kCFCompareEqualTo) {
        imageFormat = ZLImageFormatHEIC;
    } else if (CFStringCompare(uttype, kZLUTTypeHEIF, 0) == kCFCompareEqualTo) {
        imageFormat = ZLImageFormatHEIF;
    } else if (CFStringCompare(uttype, kUTTypePDF, 0) == kCFCompareEqualTo) {
        imageFormat = ZLImageFormatPDF;
    } else if (CFStringCompare(uttype, kUTTypeScalableVectorGraphics, 0) == kCFCompareEqualTo) {
        imageFormat = ZLImageFormatSVG;
    } else {
        imageFormat = ZLImageFormatUndefined;
    }
    return imageFormat;
}

inline BOOL ZLImageHasAlpha(CGImageRef _Nullable image) {
    if (image == nil) {
        return NO;
    }
    switch (CGImageGetAlphaInfo(image)) {
        case kCGImageAlphaNone:
        case kCGImageAlphaNoneSkipLast:
        case kCGImageAlphaNoneSkipFirst:
            return NO;
        default:
            return YES;
    }
}

static inline CGAffineTransform ZLCGContextTransformFromOrientation(CGImagePropertyOrientation orientation, CGSize size) {
    // Inspiration from @libfeihu
    // We need to calculate the proper transformation to make the image upright.
    // We do it in 2 steps: Rotate if Left/Right/Down, and then flip if Mirrored.
    CGAffineTransform transform = CGAffineTransformIdentity;
    
    switch (orientation) {
        case kCGImagePropertyOrientationDown:
        case kCGImagePropertyOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, size.width, size.height);
            transform = CGAffineTransformRotate(transform, M_PI);
            break;
            
        case kCGImagePropertyOrientationLeft:
        case kCGImagePropertyOrientationLeftMirrored:
            transform = CGAffineTransformTranslate(transform, size.width, 0);
            transform = CGAffineTransformRotate(transform, M_PI_2);
            break;
            
        case kCGImagePropertyOrientationRight:
        case kCGImagePropertyOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, 0, size.height);
            transform = CGAffineTransformRotate(transform, -M_PI_2);
            break;
        case kCGImagePropertyOrientationUp:
        case kCGImagePropertyOrientationUpMirrored:
            break;
    }
    
    switch (orientation) {
        case kCGImagePropertyOrientationUpMirrored:
        case kCGImagePropertyOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, size.width, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
            
        case kCGImagePropertyOrientationLeftMirrored:
        case kCGImagePropertyOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, size.height, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
        case kCGImagePropertyOrientationUp:
        case kCGImagePropertyOrientationDown:
        case kCGImagePropertyOrientationLeft:
        case kCGImagePropertyOrientationRight:
            break;
    }
    
    return transform;
}

static inline CGColorSpaceRef ZLColorSpaceGetDeviceRGB(void) {
    static CGColorSpaceRef colorSpace;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (@available(iOS 9.0, tvOS 9.0, *)) {
            colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        } else {
            colorSpace = CGColorSpaceCreateDeviceRGB();
        }
    });
    return colorSpace;
}

static inline CGImageRef CGImageCreateDecoded(CGImageRef cgImage, CGImagePropertyOrientation orientation) {
    if (!cgImage) {
        return NULL;
    }
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    if (width == 0 || height == 0) return NULL;
    size_t newWidth;
    size_t newHeight;
    switch (orientation) {
        case kCGImagePropertyOrientationLeft:
        case kCGImagePropertyOrientationLeftMirrored:
        case kCGImagePropertyOrientationRight:
        case kCGImagePropertyOrientationRightMirrored: {
            // These orientation should swap width & height
            newWidth = height;
            newHeight = width;
        }
            break;
        default: {
            newWidth = width;
            newHeight = height;
        }
            break;
    }
    
    BOOL hasAlpha = ZLImageHasAlpha(cgImage);
    // iOS prefer BGRA8888 (premultiplied) or BGRX8888 bitmapInfo for screen rendering, which is same as `UIGraphicsBeginImageContext()` or `- [CALayer drawInContext:]`
    // Though you can use any supported bitmapInfo (see: https://developer.apple.com/library/content/documentation/GraphicsImaging/Conceptual/drawingwithquartz2d/dq_context/dq_context.html#//apple_ref/doc/uid/TP30001066-CH203-BCIBHHBB ) and let Core Graphics reorder it when you call `CGContextDrawImage`
    // But since our build-in coders use this bitmapInfo, this can have a little performance benefit
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Host;
    bitmapInfo |= hasAlpha ? kCGImageAlphaPremultipliedFirst : kCGImageAlphaNoneSkipFirst;
    CGContextRef context = CGBitmapContextCreate(NULL, newWidth, newHeight, 8, 0, ZLColorSpaceGetDeviceRGB(), bitmapInfo);
    if (!context) {
        return NULL;
    }
    
    // Apply transform
    CGAffineTransform transform = ZLCGContextTransformFromOrientation(orientation, CGSizeMake(newWidth, newHeight));
    CGContextConcatCTM(context, transform);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage); // The rect is bounding box of CGImage, don't swap width & height
    CGImageRef newImageRef = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    
    return newImageRef;
}

@interface ZLGIFCoderFrame : NSObject

@property (nonatomic, assign) NSUInteger index;
@property (nonatomic, assign) NSTimeInterval duration;

@end

@implementation ZLGIFCoderFrame

@end

@interface ZLAnimatedImage ()

+ (float)frameDurationAtIndex:(NSUInteger)index source:(CGImageSourceRef)source;

@end

@implementation ZLAnimatedImage {
  CGImageSourceRef _imageSource;
  CGFloat _scale;
  NSUInteger _loopCount;
  NSUInteger _frameCount;
  NSArray<ZLGIFCoderFrame *> *_frames;
}

- (instancetype)initWithData:(NSData *)data scale:(CGFloat)scale {
    if (self = [super init]) {
        CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
        if (!imageSource) {
            return nil;
        }

        BOOL framesValid = [self scanAndCheckFramesValidWithSource:imageSource];
        if (!framesValid) {
            CFRelease(imageSource);
            return nil;
        }

        _imageSource = imageSource;

        // grab image at the first index
        UIImage *image = [self animatedImageFrameAtIndex:0];
        if (!image) {
            return nil;
        }
        self = [super initWithCGImage:image.CGImage scale:MAX(scale, 1) orientation:image.imageOrientation];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveMemoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }

    return self;
}

- (BOOL)scanAndCheckFramesValidWithSource:(CGImageSourceRef)imageSource {
    if (!imageSource) {
      return NO;
    }
    NSUInteger frameCount = CGImageSourceGetCount(imageSource);
    NSUInteger loopCount = [self imageLoopCountWithSource:imageSource];
    NSMutableArray<ZLGIFCoderFrame *> *frames = [NSMutableArray array];

    for (size_t i = 0; i < frameCount; i++) {
        ZLGIFCoderFrame *frame = [[ZLGIFCoderFrame alloc] init];
        frame.index = i;
        frame.duration = [self.class frameDurationAtIndex:i source:imageSource];
        [frames addObject:frame];
    }

    _frameCount = frameCount;
    _loopCount = loopCount;
    _frames = [frames copy];

    return YES;
}

- (NSUInteger)imageLoopCountWithSource:(CGImageSourceRef)source {
    NSUInteger loopCount = 1;
    NSDictionary *imageProperties = (__bridge_transfer NSDictionary *)CGImageSourceCopyProperties(source, nil);
    NSDictionary *gifProperties = imageProperties[(__bridge NSString *)kCGImagePropertyGIFDictionary];
    if (gifProperties) {
        NSNumber *gifLoopCount = gifProperties[(__bridge NSString *)kCGImagePropertyGIFLoopCount];
        if (gifLoopCount != nil) {
            loopCount = gifLoopCount.unsignedIntegerValue;
            // A loop count of 1 means it should repeat twice, 2 means, thrice, etc.
            if (loopCount != 0) {
                loopCount++;
            }
        }
    }
    return loopCount;
}

+ (float)frameDurationAtIndex:(NSUInteger)index source:(CGImageSourceRef)source {
    NSDictionary *options = @{
        (__bridge NSString *)kCGImageSourceShouldCacheImmediately : @(YES),
        (__bridge NSString *)kCGImageSourceShouldCache : @(YES) // Always cache to reduce CPU usage
    };
    float frameDuration = 0.1f;
    CFDictionaryRef cfFrameProperties = CGImageSourceCopyPropertiesAtIndex(source, index, (__bridge CFDictionaryRef)options);
    if (!cfFrameProperties) {
        return frameDuration;
    }
    NSDictionary *frameProperties = (__bridge NSDictionary *)cfFrameProperties;
    NSDictionary *gifProperties = frameProperties[(NSString *)kCGImagePropertyGIFDictionary];

    NSNumber *delayTimeUnclampedProp = gifProperties[(NSString *)kCGImagePropertyGIFUnclampedDelayTime];
    if (delayTimeUnclampedProp != nil && [delayTimeUnclampedProp floatValue] != 0.0f) {
        frameDuration = [delayTimeUnclampedProp floatValue];
    } else {
        NSNumber *delayTimeProp = gifProperties[(NSString *)kCGImagePropertyGIFDelayTime];
        if (delayTimeProp != nil) {
            frameDuration = [delayTimeProp floatValue];
        }
    }

    CFRelease(cfFrameProperties);
    return frameDuration;
}

- (NSUInteger)animatedImageLoopCount {
    return _loopCount;
}

- (NSUInteger)animatedImageFrameCount {
    return _frameCount;
}

- (NSTimeInterval)animatedImageDurationAtIndex:(NSUInteger)index {
    if (index >= _frameCount) {
        return 0;
    }
    return _frames[index].duration;
}

- (UIImage *)animatedImageFrameAtIndex:(NSUInteger)index {
    CGImageRef imageRef = CGImageSourceCreateImageAtIndex(_imageSource, index, NULL);
    if (!imageRef) {
        return nil;
    }
    UIImage *image = [[UIImage alloc] initWithCGImage:imageRef scale:_scale orientation:UIImageOrientationUp];
    CGImageRelease(imageRef);
    return image;
}

- (void)didReceiveMemoryWarning:(NSNotification *)notification {
    if (_imageSource) {
        for (size_t i = 0; i < _frameCount; i++) {
            CGImageSourceRemoveCacheAtIndex(_imageSource, i);
        }
    }
}

- (void)dealloc {
    if (_imageSource) {
        CFRelease(_imageSource);
        _imageSource = NULL;
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

@protocol ZLDisplayRefreshable

- (void)displayDidRefresh:(CADisplayLink *)displayLink;

@end

@interface ZLDisplayWeakRefreshable : NSObject

@property (nonatomic, weak) id<ZLDisplayRefreshable> refreshable;

+ (CADisplayLink *)displayLinkWithWeakRefreshable:(id<ZLDisplayRefreshable>)refreshable;

@end

@implementation ZLDisplayWeakRefreshable

+ (CADisplayLink *)displayLinkWithWeakRefreshable:(id<ZLDisplayRefreshable>)refreshable {
  ZLDisplayWeakRefreshable *target = [[ZLDisplayWeakRefreshable alloc] initWithRefreshable:refreshable];
  return [CADisplayLink displayLinkWithTarget:target selector:@selector(displayDidRefresh:)];
}

- (instancetype)initWithRefreshable:(id<ZLDisplayRefreshable>)refreshable
{
  if (self = [super init]) {
    _refreshable = refreshable;
  }
  return self;
}

- (void)displayDidRefresh:(CADisplayLink *)displayLink {
  [_refreshable displayDidRefresh:displayLink];
}

@end

@interface ZLAnimatedImageView () <CALayerDelegate, ZLDisplayRefreshable>

@property (nonatomic, assign) NSUInteger maxBufferSize;
@property (nonatomic, strong, readwrite) UIImage *currentFrame;
@property (nonatomic, assign, readwrite) NSUInteger currentFrameIndex;
@property (nonatomic, assign, readwrite) NSUInteger currentLoopCount;
@property (nonatomic, assign) NSUInteger totalFrameCount;
@property (nonatomic, assign) NSUInteger totalLoopCount;
@property (nonatomic, strong) UIImage<ZLAnimatedImage> *animatedImage;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIImage *> *frameBuffer;
@property (nonatomic, assign) NSTimeInterval currentTime;
@property (nonatomic, assign) BOOL bufferMiss;
@property (nonatomic, assign) NSUInteger maxBufferCount;
@property (nonatomic, strong) NSOperationQueue *fetchQueue;
@property (nonatomic, strong) dispatch_semaphore_t lock;
@property (nonatomic, assign) CGFloat animatedImageScale;
@property (nonatomic, strong) CADisplayLink *displayLink;

@end

@implementation ZLAnimatedImageView

- (instancetype)initWithFrame:(CGRect)frame {
  if (self = [super initWithFrame:frame]) {
    self.lock = dispatch_semaphore_create(1);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveMemoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];

  }
  return self;
}

- (void)resetAnimatedImage {
      self.animatedImage = nil;
      self.totalFrameCount = 0;
      self.totalLoopCount = 0;
      self.currentFrame = nil;
      self.currentFrameIndex = 0;
      self.currentLoopCount = 0;
      self.currentTime = 0;
      self.bufferMiss = NO;
      self.maxBufferCount = 0;
      self.animatedImageScale = 1;
      [_fetchQueue cancelAllOperations];
      _fetchQueue = nil;
      dispatch_semaphore_wait(self.lock, DISPATCH_TIME_FOREVER);
      [_frameBuffer removeAllObjects];
      _frameBuffer = nil;
      dispatch_semaphore_signal(self.lock);
}

- (void)setImage:(UIImage *)image {
    if (self.image == image) {
        return;
    }

    [self stop];
    [self resetAnimatedImage];

    if ([image respondsToSelector:@selector(animatedImageFrameAtIndex:)]) {
        NSUInteger animatedImageFrameCount = ((UIImage<ZLAnimatedImage> *)image).animatedImageFrameCount;

        // In case frame count is 0, there is no reason to continue.
        if (animatedImageFrameCount == 0) {
            return;
        }

        self.animatedImage = (UIImage<ZLAnimatedImage> *)image;
        self.totalFrameCount = animatedImageFrameCount;

        // Get the current frame and loop count.
        self.totalLoopCount = self.animatedImage.animatedImageLoopCount;

        self.animatedImageScale = image.scale;

        self.currentFrame = image;

        dispatch_semaphore_wait(self.lock, DISPATCH_TIME_FOREVER);
        self.frameBuffer[@(self.currentFrameIndex)] = self.currentFrame;
        dispatch_semaphore_signal(self.lock);

        // Calculate max buffer size
        [self calculateMaxBufferCount];

        if ([self paused]) {
            [self start];
        }

        [self.layer setNeedsDisplay];
    } else {
        super.image = image;
    }
}

#pragma mark - Private

- (NSOperationQueue *)fetchQueue {
    if (!_fetchQueue) {
        _fetchQueue = [[NSOperationQueue alloc] init];
        _fetchQueue.maxConcurrentOperationCount = 1;
    }
    return _fetchQueue;
}

- (NSMutableDictionary<NSNumber *,UIImage *> *)frameBuffer {
    if (!_frameBuffer) {
        _frameBuffer = [NSMutableDictionary dictionary];
    }
    return _frameBuffer;
}

- (CADisplayLink *)displayLink {
    if (!_animatedImage) {
        return nil;
    }

    if (!_displayLink) {
        _displayLink = [ZLDisplayWeakRefreshable displayLinkWithWeakRefreshable:self];
        NSString *runLoopMode = [NSProcessInfo processInfo].activeProcessorCount > 1 ? NSRunLoopCommonModes : NSDefaultRunLoopMode;
        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:runLoopMode];
    }
    return _displayLink;
}

#pragma mark - Animation

- (void)start {
    self.displayLink.paused = NO;
}

- (void)stop {
    self.displayLink.paused = YES;
}

- (BOOL)paused {
    return self.displayLink.isPaused;
}

- (void)displayDidRefresh:(CADisplayLink *)displayLink {
#if TARGET_OS_UIKITFORMAC
    // TODO: `displayLink.frameInterval` is not available on UIKitForMac
    NSTimeInterval durationToNextRefresh = displayLink.duration;
#else
    // displaylink.duration -- time interval between frames, assuming maximumFramesPerSecond
    // displayLink.preferredFramesPerSecond (>= iOS 10) -- Set to 30 for displayDidRefresh to be called at 30 fps
    // durationToNextRefresh -- Time interval to the next time displayDidRefresh is called
    
    NSTimeInterval durationToNextRefresh = displayLink.targetTimestamp - displayLink.timestamp;
#endif
    NSUInteger totalFrameCount = self.totalFrameCount;
    NSUInteger currentFrameIndex = self.currentFrameIndex;
    NSUInteger nextFrameIndex = (currentFrameIndex + 1) % totalFrameCount;

    // Check if we have the frame buffer firstly to improve performance
    if (!self.bufferMiss) {
        // Then check if timestamp is reached
        self.currentTime += durationToNextRefresh;
        NSTimeInterval currentDuration = [self.animatedImage animatedImageDurationAtIndex:currentFrameIndex];
        if (self.currentTime < currentDuration) {
          // Current frame timestamp not reached, return
            return;
        }
        self.currentTime -= currentDuration;
        // nextDuration - duration to wait before displaying next image
        NSTimeInterval nextDuration = [self.animatedImage animatedImageDurationAtIndex:nextFrameIndex];
        if (self.currentTime > nextDuration) {
            // Do not skip frame
            self.currentTime = nextDuration;
        }
    }

    // Update the current frame
    UIImage *currentFrame;
    UIImage *fetchFrame;
    dispatch_semaphore_wait(self.lock, DISPATCH_TIME_FOREVER);
    currentFrame = self.frameBuffer[@(currentFrameIndex)];
    fetchFrame = currentFrame ? self.frameBuffer[@(nextFrameIndex)] : nil;
    dispatch_semaphore_signal(self.lock);
    BOOL bufferFull = NO;
    if (currentFrame) {
        dispatch_semaphore_wait(self.lock, DISPATCH_TIME_FOREVER);
        // Remove the frame buffer if need
        if (self.frameBuffer.count > self.maxBufferCount) {
            self.frameBuffer[@(currentFrameIndex)] = nil;
        }
        // Check whether we can stop fetch
        if (self.frameBuffer.count == totalFrameCount) {
            bufferFull = YES;
        }
        dispatch_semaphore_signal(self.lock);
        self.currentFrame = currentFrame;
        self.currentFrameIndex = nextFrameIndex;
        self.bufferMiss = NO;
        [self.layer setNeedsDisplay];
    } else {
        self.bufferMiss = YES;
    }

    // Update the loop count when last frame rendered
    if (nextFrameIndex == 0 && !self.bufferMiss) {
        // Update the loop count
        self.currentLoopCount++;
        // if reached the max loop count, stop animating, 0 means loop indefinitely
        NSUInteger maxLoopCount = self.totalLoopCount;
        if (maxLoopCount != 0 && (self.currentLoopCount >= maxLoopCount)) {
            [self stop];
            return;
        }
    }

    // Check if we should prefetch next frame or current frame
    NSUInteger fetchFrameIndex;
    if (self.bufferMiss) {
        // When buffer miss, means the decode speed is slower than render speed, we fetch current miss frame
        fetchFrameIndex = currentFrameIndex;
    } else {
        // Or, most cases, the decode speed is faster than render speed, we fetch next frame
        fetchFrameIndex = nextFrameIndex;
    }

    if (!fetchFrame && !bufferFull && self.fetchQueue.operationCount == 0) {
        // Prefetch next frame in background queue
        UIImage<ZLAnimatedImage> *animatedImage = self.animatedImage;
        NSOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
            UIImage *frame = [animatedImage animatedImageFrameAtIndex:fetchFrameIndex];
            dispatch_semaphore_wait(self.lock, DISPATCH_TIME_FOREVER);
            self.frameBuffer[@(fetchFrameIndex)] = frame;
            dispatch_semaphore_signal(self.lock);
        }];
        [self.fetchQueue addOperation:operation];
    }
}

#pragma mark - CALayerDelegate

- (void)displayLayer:(CALayer *)layer {
    if (_currentFrame) {
        layer.contentsScale = self.animatedImageScale;
        layer.contents = (__bridge id)_currentFrame.CGImage;
    } else {
        [super displayLayer:layer];
    }
}

#pragma mark - Util

- (void)calculateMaxBufferCount {
    NSUInteger bytes = CGImageGetBytesPerRow(self.currentFrame.CGImage) * CGImageGetHeight(self.currentFrame.CGImage);
    if (bytes == 0) bytes = 1024;

    NSUInteger max = 0;
    if (self.maxBufferSize > 0) {
        max = self.maxBufferSize;
    } else {
        // Calculate based on current memory, these factors are by experience
        NSUInteger total = ZLDeviceTotalMemory();
        NSUInteger free = ZLDeviceFreeMemory();
        max = MIN(total * 0.2, free * 0.6);
    }

    NSUInteger maxBufferCount = (double)max / (double)bytes;
    if (!maxBufferCount) {
        // At least 1 frame
        maxBufferCount = 1;
    }

    self.maxBufferCount = maxBufferCount;
}

#pragma mark - Lifecycle

- (void)dealloc {
    // Removes the display link from all run loop modes.
    [_displayLink invalidate];
    _displayLink = nil;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didReceiveMemoryWarning:(NSNotification *)notification {
    [_fetchQueue cancelAllOperations];
    [_fetchQueue addOperationWithBlock:^{
    NSNumber *currentFrameIndex = @(self.currentFrameIndex);
    dispatch_semaphore_wait(self.lock, DISPATCH_TIME_FOREVER);
    NSArray *keys = self.frameBuffer.allKeys;
    // only keep the next frame for later rendering
    for (NSNumber * key in keys) {
        if (![key isEqualToNumber:currentFrameIndex]) {
            [self.frameBuffer removeObjectForKey:key];
        }
    }
    dispatch_semaphore_signal(self.lock);
    }];
}

@end

static CGImagePropertyOrientation CGImagePropertyOrientationFromUIImageOrientation(UIImageOrientation imageOrientation) {
  // see https://stackoverflow.com/a/6699649/496389
  switch (imageOrientation) {
    case UIImageOrientationUp: return kCGImagePropertyOrientationUp;
    case UIImageOrientationDown: return kCGImagePropertyOrientationDown;
    case UIImageOrientationLeft: return kCGImagePropertyOrientationLeft;
    case UIImageOrientationRight: return kCGImagePropertyOrientationRight;
    case UIImageOrientationUpMirrored: return kCGImagePropertyOrientationUpMirrored;
    case UIImageOrientationDownMirrored: return kCGImagePropertyOrientationDownMirrored;
    case UIImageOrientationLeftMirrored: return kCGImagePropertyOrientationLeftMirrored;
    case UIImageOrientationRightMirrored: return kCGImagePropertyOrientationRightMirrored;
    default: return kCGImagePropertyOrientationUp;
  }
}

@interface ZLSDImageFrame : NSObject

@property (nonatomic, strong) UIImage *image;

@property (nonatomic, assign) NSTimeInterval duration;

+ (instancetype)frameWithImage:(UIImage *)image duration:(NSTimeInterval)duration;

+ (UIImage *)createFrameAtIndex:(NSUInteger)index source:(CGImageSourceRef)source scale:(CGFloat)scale preserveAspectRatio:(BOOL)preserveAspectRatio thumbnailSize:(CGSize)thumbnailSize options:(NSDictionary *)options;

+ (UIImage *)animatedImageWithFrames:(NSArray<ZLSDImageFrame *> *)frames;

@end

@implementation ZLSDImageFrame

+ (instancetype)frameWithImage:(UIImage *)image duration:(NSTimeInterval)duration {
    ZLSDImageFrame *frame = [ZLSDImageFrame new];
    frame.image = image;
    frame.duration = duration;
    return frame;
}

static NSUInteger gcd(NSUInteger a, NSUInteger b) {
    NSUInteger c;
    while (a != 0) {
        c = a;
        a = b % a;
        b = c;
    }
    return b;
}

static NSUInteger gcdArray(size_t const count, NSUInteger const * const values) {
    if (count == 0) {
        return 0;
    }
    NSUInteger result = values[0];
    for (size_t i = 1; i < count; ++i) {
        result = gcd(values[i], result);
    }
    return result;
}

+ (UIImage *)createFrameAtIndex:(NSUInteger)index source:(CGImageSourceRef)source scale:(CGFloat)scale preserveAspectRatio:(BOOL)preserveAspectRatio thumbnailSize:(CGSize)thumbnailSize options:(NSDictionary *)options {
    // Some options need to pass to `CGImageSourceCopyPropertiesAtIndex` before `CGImageSourceCreateImageAtIndex`, or ImageIO will ignore them because they parse once :)
    // Parse the image properties
    NSDictionary *properties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, index, (__bridge CFDictionaryRef)options);
    CGImagePropertyOrientation exifOrientation = (CGImagePropertyOrientation)[properties[(__bridge NSString *)kCGImagePropertyOrientation] unsignedIntegerValue];
    if (!exifOrientation) {
        exifOrientation = kCGImagePropertyOrientationUp;
    }
    
    CFStringRef uttype = CGImageSourceGetType(source);
    // Check vector format
    BOOL isVector = NO;
    if (zl_imageFormatFromUTType(uttype) == ZLImageFormatPDF) {
        isVector = YES;
    }

    NSMutableDictionary *decodingOptions;
    if (options) {
        decodingOptions = [NSMutableDictionary dictionaryWithDictionary:options];
    } else {
        decodingOptions = [NSMutableDictionary dictionary];
    }
    CGImageRef imageRef;
    if (isVector) {
        if (thumbnailSize.width == 0 || thumbnailSize.height == 0) {
            // Provide the default pixel count for vector images, simply just use the screen size
#if SD_WATCH
            thumbnailSize = WKInterfaceDevice.currentDevice.screenBounds.size;
#elif SD_UIKIT
            thumbnailSize = UIScreen.mainScreen.bounds.size;
#elif SD_MAC
            thumbnailSize = NSScreen.mainScreen.frame.size;
#endif
        }
        CGFloat maxPixelSize = MAX(thumbnailSize.width, thumbnailSize.height);
        NSUInteger DPIPerPixel = 2;
        NSUInteger rasterizationDPI = maxPixelSize * DPIPerPixel;
        decodingOptions[@"kSDCGImageSourceRasterizationDPI"] = @(rasterizationDPI);
    }
    imageRef = CGImageSourceCreateImageAtIndex(source, index, (__bridge CFDictionaryRef)[decodingOptions copy]);
    
    UIImageOrientation imgOrientation = UIImageOrientationUp;
    switch (exifOrientation) {
        case kCGImagePropertyOrientationDown:
            imgOrientation = UIImageOrientationDown;
            break;
            
        case kCGImagePropertyOrientationDownMirrored:
            imgOrientation = UIImageOrientationDownMirrored;
            break;
            
        case kCGImagePropertyOrientationUpMirrored:
            imgOrientation = UIImageOrientationUpMirrored;
            break;
            
        case kCGImagePropertyOrientationLeftMirrored:
            imgOrientation = UIImageOrientationLeftMirrored;
            break;
            
        case kCGImagePropertyOrientationRight:
            imgOrientation = UIImageOrientationRight;
            break;
            
        case kCGImagePropertyOrientationRightMirrored:
            imgOrientation = UIImageOrientationRightMirrored;
            break;
            
        case kCGImagePropertyOrientationLeft:
            imgOrientation = UIImageOrientationLeft;
            break;
            
        default:
            break;
    }
#if SD_UIKIT || SD_WATCH
    UIImageOrientation imageOrientation = [SDImageCoderHelper imageOrientationFromEXIFOrientation:exifOrientation];
    UIImage *image = [[UIImage alloc] initWithCGImage:imageRef scale:scale orientation:imageOrientation];
#else
    UIImage *image = [[UIImage alloc] initWithCGImage:imageRef scale:scale orientation:imgOrientation];
#endif
    CGImageRelease(imageRef);
    return image;
}

+ (UIImage *)animatedImageWithFrames:(NSArray<ZLSDImageFrame *> *)frames {
    NSUInteger frameCount = frames.count;
    if (frameCount == 0) {
        return nil;
    }
    
    UIImage *animatedImage;
    
    NSUInteger durations[frameCount];
    for (size_t i = 0; i < frameCount; i++) {
        durations[i] = frames[i].duration * 1000;
    }
    NSUInteger const gcd = gcdArray(frameCount, durations);
    __block NSUInteger totalDuration = 0;
    NSMutableArray<UIImage *> *animatedImages = [NSMutableArray arrayWithCapacity:frameCount];
    [frames enumerateObjectsUsingBlock:^(ZLSDImageFrame * _Nonnull frame, NSUInteger idx, BOOL * _Nonnull stop) {
        UIImage *image = frame.image;
        NSUInteger duration = frame.duration * 1000;
        totalDuration += duration;
        NSUInteger repeatCount;
        if (gcd) {
            repeatCount = duration / gcd;
        } else {
            repeatCount = 1;
        }
        for (size_t i = 0; i < repeatCount; ++i) {
            [animatedImages addObject:image];
        }
    }];
    
    animatedImage = [UIImage animatedImageWithImages:animatedImages duration:totalDuration / 1000.f];
    
    return animatedImage;
}

@end

static void *ZLNetworkingImageISDecodedAssociatedKey = &ZLNetworkingImageISDecodedAssociatedKey;

@implementation UIImage (ZLNet)

- (NSData *)zl_imageDataWithQuality:(float)quality {
    CGImageRef cgImage = self.CGImage;
    if (!cgImage) {
        return nil;
    }
    
    NSMutableDictionary *properties = [NSMutableDictionary dictionaryWithObjectsAndKeys:@(CGImagePropertyOrientationFromUIImageOrientation(self.imageOrientation)), kCGImagePropertyOrientation, nil];
    
    CGImageDestinationRef destination;
    CFMutableDataRef imageData = CFDataCreateMutable(NULL, 0);
    if (ZLImageHasAlpha(cgImage)) {
        // get png data
        destination = CGImageDestinationCreateWithData(imageData, kUTTypePNG, 1, NULL);
    } else {
        // get jpeg data
        destination = CGImageDestinationCreateWithData(imageData, kUTTypeJPEG, 1, NULL);
        [properties setObject:@(quality) forKey:(__bridge  NSString *)kCGImageDestinationLossyCompressionQuality];
    }
    if (!destination) {
        CFRelease(imageData);
        return nil;
    }
    
    CGImageDestinationAddImage(destination, cgImage, (__bridge CFDictionaryRef)properties);
    if (!CGImageDestinationFinalize(destination)) {
        CFRelease(imageData);
        imageData = NULL;
    }
    CFRelease(destination);
    return (__bridge_transfer NSData *)imageData;
}

+ (UIImage *)zl_imageWithData:(NSData *)data {
    if (data == nil) {
        return nil;
    }
    UIImage *image = [UIImage imageWithData:data];
    if (image == nil) {
        return nil;
    }
    ZLImageFormat imgFormat = zl_imageFormatForImageData(data);
    if (imgFormat == ZLImageFormatGIF) {
        return [[ZLAnimatedImage alloc] initWithData:data scale:[UIScreen mainScreen].scale];;
    } else if (imgFormat == ZLImageFormatPDF || imgFormat == ZLImageFormatSVG) {
        return image;
    }
    
    CGImageRef imageRef = CGImageCreateDecoded(image.CGImage, kCGImagePropertyOrientationUp);
    if (!imageRef) {
        return image;
    }
    UIImage *decodedImage = [[UIImage alloc] initWithCGImage:imageRef scale:[UIScreen mainScreen].scale orientation:image.imageOrientation];

    CGImageRelease(imageRef);

    return decodedImage;
}

+ (UIImage *_Nullable)zl_imageWithData:(NSData *_Nullable)data
                            targetSize:(CGSize)targetSize
                                radius:(CGFloat)radius
                           contentMode:(ZLNetImageViewContentMode)contentMode {
    if (data == nil) {
        return nil;
    }
    UIImage *image = [UIImage imageWithData:data];
    if (image == nil) {
        return nil;
    }
    image = [image imageScaleForSize:targetSize withCornerRadius:radius contentMode:contentMode];
    if (image == nil) {
        return nil;
    }
    ZLImageFormat imgFormat = zl_imageFormatForImageData(data);
    if (imgFormat == ZLImageFormatGIF) {
        return [[ZLAnimatedImage alloc] initWithData:data scale:[UIScreen mainScreen].scale];;
    } else if (imgFormat == ZLImageFormatPDF || imgFormat == ZLImageFormatSVG) {
        return image;
    }
    
    CGImageRef imageRef = CGImageCreateDecoded(image.CGImage, kCGImagePropertyOrientationUp);
    if (!imageRef) {
        return image;
    }
    UIImage *decodedImage = [[UIImage alloc] initWithCGImage:imageRef scale:[UIScreen mainScreen].scale orientation:image.imageOrientation];

    CGImageRelease(imageRef);

    return decodedImage;
}

+ (UIImage *)zl_imageWithContentsOfFile:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil) {
        return nil;
    }
    
    return [UIImage zl_imageWithData:data];
}

+ (UIImage *_Nullable)zl_imageWithContentsOfFile:(NSString *_Nullable)path
                                      targetSize:(CGSize)targetSize
                                          radius:(CGFloat)radius
                                     contentMode:(ZLNetImageViewContentMode)contentMode {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil) {
        return nil;
    }
    
    return [UIImage zl_imageWithData:data targetSize:targetSize radius:radius contentMode:contentMode];
}

+ (ZLAnimatedImage *_Nullable)zl_animatedImageWithData:(NSData *_Nullable)data scale:(CGFloat)scale {
    return [[ZLAnimatedImage alloc] initWithData:data scale:scale];
}

+ (ZLAnimatedImage *_Nullable)zl_animatedImageWithData:(NSData *_Nullable)data {
    return [[ZLAnimatedImage alloc] initWithData:data scale:[UIScreen mainScreen].scale];
}

+ (ZLAnimatedImage *_Nullable)zl_animatedImageWithDataWithContentsOfFile:(NSString *_Nullable)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil) {
        return nil;
    }
    
    return [[ZLAnimatedImage alloc] initWithData:data scale:[UIScreen mainScreen].scale];
}

+ (UIImage *_Nullable)zl_animatedImageSDWithData:(NSData *_Nullable)data {
    if (!data) {
        return nil;
    }
    CGFloat scale = 1;
    
    CGSize thumbnailSize = CGSizeZero;
    
    BOOL preserveAspectRatio = YES;
    
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) {
        return nil;
    }
    size_t count = CGImageSourceGetCount(source);
    UIImage *animatedImage;
    
    if (count <= 1) {
        animatedImage = [ZLSDImageFrame createFrameAtIndex:0 source:source scale:scale preserveAspectRatio:preserveAspectRatio thumbnailSize:thumbnailSize options:nil];
    } else {
        NSMutableArray<ZLSDImageFrame *> *frames = [NSMutableArray array];
        
        for (size_t i = 0; i < count; i++) {
            UIImage *image = [ZLSDImageFrame createFrameAtIndex:i source:source scale:scale preserveAspectRatio:preserveAspectRatio thumbnailSize:thumbnailSize options:nil];
            if (!image) {
                continue;
            }
            
            NSTimeInterval duration = [ZLAnimatedImage frameDurationAtIndex:i source:source];
            
            ZLSDImageFrame *frame = [ZLSDImageFrame frameWithImage:image duration:duration];
            [frames addObject:frame];
        }
        
        animatedImage = [ZLSDImageFrame animatedImageWithFrames:frames];
    }
    CFRelease(source);
    
    return animatedImage;
}

- (UIImage *_Nullable)imageScaleForSize:(CGSize)targetSize
                       withCornerRadius:(CGFloat)radius
                            contentMode:(ZLNetImageViewContentMode)contentMode {
    if (CGSizeEqualToSize(targetSize, CGSizeZero) || CGSizeEqualToSize(targetSize, self.size)) {
        if (radius <= 0) {
            return self;
        }
        
        CGRect finalRect = (CGRect){.origin=CGPointZero, .size=self.size};
        UIGraphicsBeginImageContextWithOptions(self.size, NO, [UIScreen mainScreen].scale);
        // 根据矩形画带圆角的曲线
        [[UIBezierPath bezierPathWithRoundedRect:finalRect cornerRadius:radius] addClip];

        [self drawInRect:finalRect];
        // 图片缩放，是非线程安全的
        UIImage * image = UIGraphicsGetImageFromCurrentImageContext();
        // 关闭上下文
        UIGraphicsEndImageContext();
        return image;
    }
    
    CGFloat finalWidth = 0, finalHeight = 0;
    if (contentMode == ZLNetImageViewContentModeScaleAspectFill) {
        double factor = fmax(targetSize.width / self.size.width, targetSize.height / self.size.height);
        finalWidth = self.size.width * factor;
        finalHeight = self.size.height * factor;
    } else if (contentMode == ZLNetImageViewContentModeScaleAspectFit) {
        double factor = fmin(targetSize.width / self.size.width, targetSize.height / self.size.height);
        finalWidth = self.size.width * factor;
        finalHeight = self.size.height * factor;
    } else if (contentMode == ZLNetImageViewContentModeCenter) {
        double factor = 1.0 / [UIScreen mainScreen].scale;
        finalWidth = self.size.width * factor;
        finalHeight = self.size.height * factor;
    }
    
    CGRect finalRect = CGRectMake((targetSize.width - finalWidth) * 0.5, (targetSize.height - finalHeight) * 0.5, finalWidth, finalHeight);

    UIGraphicsBeginImageContextWithOptions(targetSize, NO, [UIScreen mainScreen].scale);
    if (radius > 0) {
        // 根据矩形画带圆角的曲线
        [[UIBezierPath bezierPathWithRoundedRect:(CGRect){.origin=CGPointZero, .size=targetSize} cornerRadius:radius] addClip];
    }
    [self drawInRect:finalRect];
    // 图片缩放，是非线程安全的
    UIImage * image = UIGraphicsGetImageFromCurrentImageContext();
    // 关闭上下文
    UIGraphicsEndImageContext();
    return image;
}

@end

@interface ZLImageMemoryCacheNode : NSObject

@property (nonatomic, strong) UIImage *image;

@property (nonatomic, copy) NSString *identifier;

@property (nonatomic, assign) NSInteger memoryCost;

@property (nonatomic, assign) NSTimeInterval timestamp;

@property (nonatomic, strong) ZLImageMemoryCacheNode *prev;

@property (nonatomic, strong) ZLImageMemoryCacheNode *next;

@end

@implementation ZLImageMemoryCacheNode

- (instancetype)initWithImage:(UIImage *)image identifier:(NSString *)identifier {
    if (self = [super init]) {
        self.image = image;
        self.identifier = identifier;
        self.timestamp = [NSDate date].timeIntervalSince1970;
        _memoryCost = -1;
    }
    return self;
}

- (NSInteger)memoryCost {
    if (_memoryCost == -1) {
        _memoryCost = [[self class] memoryCacheCostForImage:self.image];
    }
    return _memoryCost;
}

+ (NSUInteger)memoryCacheCostForImage:(UIImage *)image {
    CGImageRef imageRef = image.CGImage;
    if (!imageRef) {
        return 0;
    }
    NSUInteger bytesPerFrame = CGImageGetBytesPerRow(imageRef) * CGImageGetHeight(imageRef);
    NSUInteger frameCount = image.images.count > 0 ? image.images.count : 1;

    NSUInteger cost = bytesPerFrame * frameCount;
    return cost;
}

@end

@interface ZLImageCacheManager ()

@property (nonatomic, copy, readwrite) NSString *workspacePath;

@property (nonatomic, strong) dispatch_queue_t workQueue;
@property (nonatomic, strong) dispatch_queue_t serialQueue;

@property (nonatomic, strong) ZLImageMemoryCacheNode *header;
@property (nonatomic, strong) ZLImageMemoryCacheNode *footer;
@property (nonatomic, assign) NSInteger memoryCachedBytes;

@property (nonatomic, strong) NSMutableSet<NSString *> *cacheIdentifiers;

- (void)getCacheWithURL:(NSURL *)url
             targetSize:(CGSize)targetSize
                 radius:(CGFloat)radius
            contentMode:(ZLNetImageViewContentMode)contentMode
               progress:(void (^)(float progress))progressBlock
              completed:(void (^)(UIImage * _Nullable image, NSError * _Nullable error))completedBlock;

@end

@implementation ZLImageCacheManager

- (void)addCacheImage:(UIImage *)image identifier:(NSString *)identifier {
    dispatch_sync(self.serialQueue, ^{
        if ([self.cacheIdentifiers containsObject:identifier]) {
            return;
        }
        [self.cacheIdentifiers addObject:identifier];
        
        ZLImageMemoryCacheNode *node = [[ZLImageMemoryCacheNode alloc] initWithImage:image identifier:identifier];
        
        if (self.header == nil) {
            if (node.memoryCost >= self.maxMemoryCacheBytes) {
                return;
            }
            
            self.header = node;
            self.footer = node;
            self.memoryCachedBytes = node.memoryCost;
        } else {
            if (node.memoryCost >= self.maxMemoryCacheBytes) {
                return;
            }
            
            NSInteger preMemoryCachedBytes = self.memoryCachedBytes + node.memoryCost;
            if (preMemoryCachedBytes >= self.maxMemoryCacheBytes) {
                ZLImageMemoryCacheNode *lastNode = self.footer;
                preMemoryCachedBytes -= lastNode.memoryCost;
                while (preMemoryCachedBytes >= self.maxMemoryCacheBytes) {
                    [self.cacheIdentifiers removeObject:lastNode.identifier];
                    lastNode = lastNode.prev;
                    lastNode.next.prev = nil;
                    lastNode.next = nil;
                    preMemoryCachedBytes -= lastNode.memoryCost;
                }
                self.footer = lastNode;
            }
            
            self.footer.next = node;
            node.prev = self.footer;
            self.footer = node;
            
            self.memoryCachedBytes = preMemoryCachedBytes;
        }
    });
}

- (void)updateCacheNode:(ZLImageMemoryCacheNode *)node {
    dispatch_sync(self.serialQueue, ^{
        node.timestamp = [NSDate date].timeIntervalSince1970;
        if (node == self.header) {
            return;
        } else if (node == self.footer) {
            node.prev.next = nil;
            self.footer = node.prev;
            
            self.header.prev = node;
            node.next = self.header;
            node.prev = nil;
            self.header = node;
            return;
        }

        node.prev.next = node.next;
        node.next.prev = node.prev;

        self.header.prev = node;
        node.next = self.header;
        node.prev = nil;
        self.header = node;
    });
}

- (ZLImageMemoryCacheNode *)findMemoryCacheByIdentifier:(NSString *)identifier {
    __block ZLImageMemoryCacheNode *resultNode = nil;
    dispatch_sync(self.serialQueue, ^{
        ZLImageMemoryCacheNode *headerNode = self.header;
        ZLImageMemoryCacheNode *footerNode = self.footer;
        
        while (headerNode != footerNode) {
            if ([headerNode.identifier isEqualToString:identifier]) {
                resultNode = headerNode;
            }
            
            if ([footerNode.identifier isEqualToString:identifier]) {
                resultNode = footerNode;
            }
            
            headerNode = headerNode.next;
            footerNode = footerNode.prev;
        }
        
        if (resultNode == nil && headerNode && [headerNode.identifier isEqualToString:identifier]) {
            resultNode = headerNode;
        }
    });
    return resultNode;
}

- (void)didReceiveMemoryWarning:(NSNotification *)notification {
    dispatch_sync(self.serialQueue, ^{
        ZLImageMemoryCacheNode *headerNode = self.header;
        while (headerNode) {
            ZLImageMemoryCacheNode *next = headerNode.next;
            headerNode.next = nil;
            next.prev = nil;
            headerNode = next;
        }
        self.header = nil;
        self.footer = nil;
        [self.cacheIdentifiers removeAllObjects];
    });
}

+ (instancetype)shared {
    static ZLImageCacheManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [ZLImageCacheManager new];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _workspacePath = [[ZLURLSessionManager shared].workspaceDirURLString stringByAppendingPathComponent:@"caches"];
        
        BOOL isDir = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:_workspacePath isDirectory:&isDir] || !isDir) {
            if (![[NSFileManager defaultManager] createDirectoryAtPath:_workspacePath withIntermediateDirectories:YES attributes:nil error:nil]) {
                NSLog(@"file system error");
            }
        }
        
        _workQueue = dispatch_queue_create("com.richie.zlnetimage", DISPATCH_QUEUE_CONCURRENT);
        _serialQueue = dispatch_queue_create("com.richie.zlnetimage.sync", DISPATCH_QUEUE_SERIAL);
        
        _maxMemoryCacheBytes = ZLDeviceTotalMemory() / 4;
        
        self.cacheIdentifiers = [NSMutableSet set];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveMemoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}

- (BOOL)cacheFileExists:(NSString *)destPath {
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:destPath isDirectory:&isDir] && !isDir) {
        return YES;
    }
    return NO;
}

- (NSString *)identifierWithURL:(NSURL *)url {
    return ZLSha256HashFor(url.absoluteString);
}

- (void)getCacheWithURL:(NSURL *)url
             targetSize:(CGSize)targetSize
                 radius:(CGFloat)radius
            contentMode:(ZLNetImageViewContentMode)contentMode
               progress:(void (^)(float progress))progressBlock
              completed:(void (^)(UIImage * _Nullable image, NSError * _Nullable error))completedBlock {
    
    NSString *identifier = [self identifierWithURL:url];
    NSString *memoryIdentifier = [identifier stringByAppendingFormat:@"_%.2f_%.2f_%.2f", targetSize.width, targetSize.height, radius];
    NSString *destPath = [_workspacePath stringByAppendingPathComponent:identifier];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        ZLImageMemoryCacheNode *node = [self findMemoryCacheByIdentifier:memoryIdentifier];
        if (node != nil) {
            [self updateCacheNode:node];
            dispatch_async(dispatch_get_main_queue(), ^{
                completedBlock(node.image, nil);
            });
            return;
        }
        
        NSURL *desURL = [NSURL fileURLWithPath:destPath];
        
        void (^downloadBlock)(void) = ^{
            [[ZLURLSessionManager shared] downloadWithRequest:[NSURLRequest requestWithURL:url] headers:nil destination:desURL progress:progressBlock completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
                if (error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completedBlock(nil, error);
                    });
                    return;
                }
                
                __block UIImage *image = [UIImage zl_imageWithContentsOfFile:destPath targetSize:targetSize radius:radius contentMode:contentMode];
                [self addCacheImage:image identifier:memoryIdentifier];
                dispatch_async(dispatch_get_main_queue(), ^{
                    completedBlock(image, nil);
                });
            }];
        };
        
        if ([self cacheFileExists:destPath]) {
            dispatch_async(self.workQueue, ^{
                __block UIImage *image = [UIImage zl_imageWithContentsOfFile:destPath  targetSize:targetSize radius:radius contentMode:contentMode];
                if (image == nil) {
                    [[NSFileManager defaultManager] removeItemAtURL:desURL error:nil];
                    
                    downloadBlock();
                    return;
                }
                [self addCacheImage:image identifier:memoryIdentifier];
                dispatch_async(dispatch_get_main_queue(), ^{
                    completedBlock(image, nil);
                });
            });
            return;
        }
        
        downloadBlock();
    });
}

- (void)clearDiskCache {
    [ZLURLSessionManager deleteDirPath:_workspacePath];
    [[NSFileManager defaultManager] createDirectoryAtPath:_workspacePath withIntermediateDirectories:YES attributes:nil error:nil];
}

@end

static void *ZLNetImageViewConfigAKey = &ZLNetImageViewConfigAKey;

@interface ZLNetImageViewConfig : NSObject

@property (nonatomic, assign) CGSize renderSize;

@property (nonatomic, assign) CGFloat renderCornerRadius;

@property (nonatomic, assign) ZLNetImageViewContentMode renderContentMode;

@end

@implementation ZLNetImageViewConfig

- (instancetype)init {
    self = [super init];
    if (self) {
        _renderSize = CGSizeZero;
        _renderCornerRadius = 0;
        _renderContentMode = ZLNetImageViewContentModeScaleAspectFill;
    }
    return self;
}

@end

@implementation UIImageView (ZLNet)

- (ZLNetImageViewConfig *)getZLRenderConfig {
    ZLNetImageViewConfig *value = objc_getAssociatedObject(self, ZLNetImageViewConfigAKey);
    if (value == nil) {
        value = [ZLNetImageViewConfig new];
        objc_setAssociatedObject(self, ZLNetImageViewConfigAKey, value, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    return value;
}

- (void)setRenderSize:(CGSize)renderSize {
    ZLNetImageViewConfig *config = [self getZLRenderConfig];
    config.renderSize = renderSize;
}

- (CGSize)renderSize {
    ZLNetImageViewConfig *config = [self getZLRenderConfig];
    return config.renderSize;
}

- (void)setRenderCornerRadius:(CGFloat)renderCornerRadius {
    ZLNetImageViewConfig *config = [self getZLRenderConfig];
    config.renderCornerRadius = renderCornerRadius;
}

- (CGFloat)renderCornerRadius {
    ZLNetImageViewConfig *config = [self getZLRenderConfig];
    return config.renderCornerRadius;
}

- (void)setRenderContentMode:(ZLNetImageViewContentMode)renderContentMode {
    ZLNetImageViewConfig *config = [self getZLRenderConfig];
    config.renderContentMode = renderContentMode;
}

- (ZLNetImageViewContentMode)renderContentMode {
    ZLNetImageViewConfig *config = [self getZLRenderConfig];
    return config.renderContentMode;
}

- (void)zl_setImageWithURL:(nullable NSURL *)url
          placeholderImage:(nullable UIImage *)placeholder
                  progress:(nullable void (^)(float progress))progressBlock
completed:(nullable void (^)(UIImage * _Nullable image, NSError * _Nullable error))completedBlock {
    if ([NSThread isMainThread]) {
        self.image = placeholder ?: [UIImage new];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.image = placeholder ?: [UIImage new];
        });
    }
    
    [[ZLImageCacheManager shared] getCacheWithURL:url
                                       targetSize:self.renderSize
                                           radius:self.renderCornerRadius
                                      contentMode:self.renderContentMode
                                         progress:progressBlock
                                        completed:^(UIImage * _Nullable image, NSError * _Nullable error) {
        if (image != nil) {
            [self setImage:image];
        }
        if (completedBlock) {
            completedBlock(image, error);
        }
    }];
}

- (void)zl_setImageWithURL:(nullable NSURL *)url
          placeholderImage:(nullable UIImage *)placeholder {
    [self zl_setImageWithURL:url placeholderImage:placeholder progress:nil completed:nil];
}

- (void)zl_setImageWithURL:(nullable NSURL *)url {
    [self zl_setImageWithURL:url placeholderImage:nil progress:nil completed:nil];
}

@end
