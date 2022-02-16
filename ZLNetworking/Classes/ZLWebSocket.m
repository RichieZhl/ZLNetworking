//
//  ZLWebSocket.m
//  ZLNetworking_Example
//
//  Created by lylaut on 2022/2/15.
//

#import "ZLWebSocket.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

typedef NS_ENUM(uint8_t, ZLOpCode) {
    ZLOpCodeTextFrame = 0x1,
    ZLOpCodeBinaryFrame = 0x2,
    // 3-7 reserved.
    ZLOpCodeConnectionClose = 0x8,
    ZLOpCodePing = 0x9,
    ZLOpCodePong = 0xA,
    // B-F reserved.
};

typedef struct {
    BOOL fin;
    //  BOOL rsv1;
    //  BOOL rsv2;
    //  BOOL rsv3;
    uint8_t opcode;
    BOOL masked;
    uint64_t payload_length;
} frame_header;

static NSString *const ZLWebSocketAppendToSecKeyString = @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

static uint8_t const ZLWebSocketProtocolVersion = 13;

NSString *const ZLWebSocketErrorDomain = @"ZLWebSocketErrorDomain";
NSString *const ZLHTTPResponseErrorKey = @"HTTPResponseStatusCode";

static size_t ZLDefaultBufferSize(void) {
    static size_t size;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        size = getpagesize();
    });
    return size;
}

#if TARGET_OS_IPHONE
#import <unicode/utf8.h>

static inline int32_t validate_dispatch_data_partial_string(NSData *data) {
    if ([data length] > INT32_MAX) {
        // INT32_MAX is the limit so long as this Framework is using 32 bit ints everywhere.
        return -1;
    }

    int32_t size = (int32_t)[data length];

    const void * contents = [data bytes];
    const uint8_t *str = (const uint8_t *)contents;

    UChar32 codepoint = 1;
    int32_t offset = 0;
    int32_t lastOffset = 0;
    while(offset < size && codepoint > 0)  {
        lastOffset = offset;
        U8_NEXT(str, offset, size, codepoint);
    }

    if (codepoint == -1) {
        // Check to see if the last byte is valid or whether it was just continuing
        if (!U8_IS_LEAD(str[lastOffset]) || U8_COUNT_TRAIL_BYTES(str[lastOffset]) + lastOffset < (int32_t)size) {

            size = -1;
        } else {
            uint8_t leadByte = str[lastOffset];
            U8_MASK_LEAD_BYTE(leadByte, U8_COUNT_TRAIL_BYTES(leadByte));

            for (int i = lastOffset + 1; i < offset; i++) {
                if (U8_IS_SINGLE(str[i]) || U8_IS_LEAD(str[i]) || !U8_IS_TRAIL(str[i])) {
                    size = -1;
                }
            }

            if (size != -1) {
                size = lastOffset;
            }
        }
    }

    if (size != -1 && ![[NSString alloc] initWithBytesNoCopy:(char *)[data bytes] length:size encoding:NSUTF8StringEncoding freeWhenDone:NO]) {
        size = -1;
    }

    return size;
}

#else

// This is a hack, and probably not optimal
static inline int32_t validate_dispatch_data_partial_string(NSData *data) {
    static const int maxCodepointSize = 3;

    for (int i = 0; i < maxCodepointSize; i++) {
        NSString *str = [[NSString alloc] initWithBytesNoCopy:(char *)data.bytes length:data.length - i encoding:NSUTF8StringEncoding freeWhenDone:NO];
        if (str) {
            return (int32_t)data.length - i;
        }
    }

    return -1;
}

#endif

static NSData *ZLSHA1HashFromBytes(const char *bytes, size_t length) {
    uint8_t outputLength = CC_SHA1_DIGEST_LENGTH;
    unsigned char output[outputLength];
    CC_SHA1(bytes, (CC_LONG)length, output);

    return [NSData dataWithBytes:output length:outputLength];
}

static NSData *ZLSHA1HashFromString(NSString *string) {
    size_t length = [string lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    return ZLSHA1HashFromBytes(string.UTF8String, length);
}

static NSString *ZLBase64EncodedStringFromData(NSData *data) {
    return [data base64EncodedStringWithOptions:0];
}

static NSData *ZLRandomData(NSUInteger length) {
    NSMutableData *data = [NSMutableData dataWithLength:length];
    int result = SecRandomCopyBytes(kSecRandomDefault, data.length, data.mutableBytes);
    if (result != 0) {
        [NSException raise:NSInternalInconsistencyException format:@"Failed to generate random bytes with OSStatus: %d", result];
    }
    return data;
}

static BOOL ZLURLRequiresSSL(NSURL *url) {
    NSString *scheme = url.scheme.lowercaseString;
    return ([scheme isEqualToString:@"wss"] || [scheme isEqualToString:@"https"]);
}

static NSString *ZLURLOrigin(NSURL *url) {
    NSMutableString *origin = [NSMutableString string];

    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"wss"]) {
        scheme = @"https";
    } else if ([scheme isEqualToString:@"ws"]) {
        scheme = @"http";
    }
    [origin appendFormat:@"%@://%@", scheme, url.host];

    NSNumber *port = url.port;
    BOOL portIsDefault = (!port ||
                          ([scheme isEqualToString:@"http"] && port.integerValue == 80) ||
                          ([scheme isEqualToString:@"https"] && port.integerValue == 443));
    if (!portIsDefault) {
        [origin appendFormat:@":%@", port.stringValue];
    }
    return origin;
}

static NSString *_Nullable SRStreamNetworkServiceTypeFromURLRequest(NSURLRequest *request) {
    NSString *networkServiceType = nil;
    switch (request.networkServiceType) {
        case NSURLNetworkServiceTypeDefault:
        case NSURLNetworkServiceTypeResponsiveData:
        case NSURLNetworkServiceTypeAVStreaming:
        case NSURLNetworkServiceTypeResponsiveAV:
            break;
        case NSURLNetworkServiceTypeVoIP:
            networkServiceType = NSStreamNetworkServiceTypeVoIP;
            break;
        case NSURLNetworkServiceTypeVideo:
            networkServiceType = NSStreamNetworkServiceTypeVideo;
            break;
        case NSURLNetworkServiceTypeBackground:
            networkServiceType = NSStreamNetworkServiceTypeBackground;
            break;
        case NSURLNetworkServiceTypeVoice:
            networkServiceType = NSStreamNetworkServiceTypeVoice;
            break;
        case NSURLNetworkServiceTypeCallSignaling: {
            if (@available(iOS 10.0, tvOS 10.0, macOS 10.12, *)) {
                networkServiceType = NSStreamNetworkServiceTypeCallSignaling;
            }
        } break;
    }
    return networkServiceType;
}

typedef uint8_t uint8x32_t __attribute__((vector_size(32)));

static void ZLMaskBytesManual(uint8_t *bytes, size_t length, uint8_t *maskKey) {
    for (size_t i = 0; i < length; i++) {
        bytes[i] = bytes[i] ^ maskKey[i % sizeof(uint32_t)];
    }
}

/**
 Right-shift the elements of a vector, circularly.

 @param vector The vector to circular shift.
 @param by     The number of elements to shift by.

 @return A shifted vector.
 */
static uint8x32_t ZLShiftVector(uint8x32_t vector, size_t by) {
    uint8x32_t vectorCopy = vector;
    by = by % _Alignof(uint8x32_t);

    uint8_t *vectorPointer = (uint8_t *)&vector;
    uint8_t *vectorCopyPointer = (uint8_t *)&vectorCopy;

    memmove(vectorPointer + by, vectorPointer, sizeof(vector) - by);
    memcpy(vectorPointer, vectorCopyPointer + (sizeof(vector) - by), by);

    return vector;
}

static void ZLMaskBytesSIMD(uint8_t *bytes, size_t length, uint8_t *maskKey) {
    size_t alignmentBytes = _Alignof(uint8x32_t) - ((uintptr_t)bytes % _Alignof(uint8x32_t));
    if (alignmentBytes == _Alignof(uint8x32_t)) {
        alignmentBytes = 0;
    }

    // If the number of bytes that can be processed after aligning is
    // less than the number of bytes we can put into a vector,
    // then there's no work to do with SIMD, just call the manual version.
    if (alignmentBytes > length || (length - alignmentBytes) < sizeof(uint8x32_t)) {
        ZLMaskBytesManual(bytes, length, maskKey);
        return;
    }

    size_t vectorLength = (length - alignmentBytes) / sizeof(uint8x32_t);
    size_t manualStartOffset = alignmentBytes + (vectorLength * sizeof(uint8x32_t));
    size_t manualLength = length - manualStartOffset;

    uint8x32_t *vector = (uint8x32_t *)(bytes + alignmentBytes);
    uint8x32_t maskVector = { };

    memset_pattern4(&maskVector, maskKey, sizeof(uint8x32_t));
    maskVector = ZLShiftVector(maskVector, alignmentBytes);

    ZLMaskBytesManual(bytes, alignmentBytes, maskKey);

    for (size_t vectorIndex = 0; vectorIndex < vectorLength; vectorIndex++) {
        vector[vectorIndex] = vector[vectorIndex] ^ maskVector;
    }

    // Use the shifted mask for the final manual part.
    ZLMaskBytesManual(bytes + manualStartOffset, manualLength, (uint8_t *) &maskVector);
}

static CFHTTPMessageRef ZLHTTPConnectMessageCreate(NSURLRequest *request,
                                                   NSString *securityKey,
                                                   uint8_t webSocketProtocolVersion,
                                                   NSArray<NSHTTPCookie *> *_Nullable cookies,
                                                   NSArray<NSString *> *_Nullable requestedProtocols) {
    NSURL *url = request.URL;

    CFHTTPMessageRef message = CFHTTPMessageCreateRequest(NULL, CFSTR("GET"), (__bridge CFURLRef)url, kCFHTTPVersion1_1);

    NSString *host = url.host;
    if (url.port) {
        host = [host stringByAppendingFormat:@":%@", url.port];
    }
    // Set host first so it defaults
    CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Host"), (__bridge CFStringRef)host);

    NSMutableData *keyBytes = [[NSMutableData alloc] initWithLength:16];
    int result = SecRandomCopyBytes(kSecRandomDefault, keyBytes.length, keyBytes.mutableBytes);
    if (result != 0) {
        //TODO: (nlutsenko) Check if there was an error.
    }

    // Apply cookies if any have been provided
    if (cookies) {
        NSDictionary<NSString *, NSString *> *messageCookies = [NSHTTPCookie requestHeaderFieldsWithCookies:cookies];
        [messageCookies enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
            if (key.length && obj.length) {
                CFHTTPMessageSetHeaderFieldValue(message, (__bridge CFStringRef)key, (__bridge CFStringRef)obj);
            }
        }];
    }

    // set header for http basic auth
    NSString *basicAuthorizationString = [NSString stringWithFormat:@"Basic %@", ZLBase64EncodedStringFromData([[NSString stringWithFormat:@"%@:%@", url.user, url.password] dataUsingEncoding:NSUTF8StringEncoding])];
    if (basicAuthorizationString) {
        CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Authorization"), (__bridge CFStringRef)basicAuthorizationString);
    }

    CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Upgrade"), CFSTR("websocket"));
    CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Connection"), CFSTR("Upgrade"));
    CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Sec-WebSocket-Key"), (__bridge CFStringRef)securityKey);
    CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Sec-WebSocket-Version"), (__bridge CFStringRef)@(webSocketProtocolVersion).stringValue);

    CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Origin"), (__bridge CFStringRef)ZLURLOrigin(url));

    if (requestedProtocols.count) {
        CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Sec-WebSocket-Protocol"),
                                         (__bridge CFStringRef)[requestedProtocols componentsJoinedByString:@", "]);
    }

    [request.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        CFHTTPMessageSetHeaderFieldValue(message, (__bridge CFStringRef)key, (__bridge CFStringRef)obj);
    }];

    return message;
}

typedef size_t (^stream_scanner)(NSData *collected_data);
typedef void (^data_callback)(ZLWebSocket *webSocket,  NSData *data);

@interface ZLIOConsumer : NSObject {
    stream_scanner _scanner;
    data_callback _handler;
    size_t _bytesNeeded;
    BOOL _readToCurrentFrame;
    BOOL _unmaskBytes;
}
@property (nonatomic, copy, readonly) stream_scanner consumer;
@property (nonatomic, copy, readonly) data_callback handler;
@property (nonatomic, assign) size_t bytesNeeded;
@property (nonatomic, assign, readonly) BOOL readToCurrentFrame;
@property (nonatomic, assign, readonly) BOOL unmaskBytes;

- (void)resetWithScanner:(stream_scanner)scanner
                 handler:(data_callback)handler
             bytesNeeded:(size_t)bytesNeeded
      readToCurrentFrame:(BOOL)readToCurrentFrame
             unmaskBytes:(BOOL)unmaskBytes;

@end

@implementation ZLIOConsumer

@synthesize bytesNeeded = _bytesNeeded;
@synthesize consumer = _scanner;
@synthesize handler = _handler;
@synthesize readToCurrentFrame = _readToCurrentFrame;
@synthesize unmaskBytes = _unmaskBytes;

- (void)resetWithScanner:(stream_scanner)scanner
                 handler:(data_callback)handler
             bytesNeeded:(size_t)bytesNeeded
      readToCurrentFrame:(BOOL)readToCurrentFrame
             unmaskBytes:(BOOL)unmaskBytes {
    _scanner = [scanner copy];
    _handler = [handler copy];
    _bytesNeeded = bytesNeeded;
    _readToCurrentFrame = readToCurrentFrame;
    _unmaskBytes = unmaskBytes;
    assert(_scanner || _bytesNeeded);
}

@end

@interface ZLIOConsumerPool : NSObject

- (instancetype)initWithBufferCapacity:(NSUInteger)poolSize;

- (ZLIOConsumer *)consumerWithScanner:(stream_scanner)scanner
                              handler:(data_callback)handler
                          bytesNeeded:(size_t)bytesNeeded
                   readToCurrentFrame:(BOOL)readToCurrentFrame
                          unmaskBytes:(BOOL)unmaskBytes;
- (void)returnConsumer:(ZLIOConsumer *)consumer;

@end

@implementation ZLIOConsumerPool {
    NSUInteger _poolSize;
    NSMutableArray<ZLIOConsumer *> *_bufferedConsumers;
}

- (instancetype)initWithBufferCapacity:(NSUInteger)poolSize {
    self = [super init];
    if (self) {
        _poolSize = poolSize;
        _bufferedConsumers = [NSMutableArray arrayWithCapacity:poolSize];
    }
    return self;
}

- (instancetype)init {
    return [self initWithBufferCapacity:8];
}

- (ZLIOConsumer *)consumerWithScanner:(stream_scanner)scanner
                              handler:(data_callback)handler
                          bytesNeeded:(size_t)bytesNeeded
                   readToCurrentFrame:(BOOL)readToCurrentFrame
                          unmaskBytes:(BOOL)unmaskBytes {
    ZLIOConsumer *consumer = nil;
    if (_bufferedConsumers.count) {
        consumer = [_bufferedConsumers lastObject];
        [_bufferedConsumers removeLastObject];
    } else {
        consumer = [[ZLIOConsumer alloc] init];
    }

    [consumer resetWithScanner:scanner
                       handler:handler
                   bytesNeeded:bytesNeeded
            readToCurrentFrame:readToCurrentFrame
                   unmaskBytes:unmaskBytes];

    return consumer;
}

- (void)returnConsumer:(ZLIOConsumer *)consumer {
    if (_bufferedConsumers.count < _poolSize) {
        [_bufferedConsumers addObject:consumer];
    }
}

@end

@interface ZLSecurityPolicy ()

@property (nonatomic, assign, readonly) BOOL certificateChainValidationEnabled;

@end

@implementation ZLSecurityPolicy

+ (instancetype)defaultPolicy {
    return [self new];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _certificateChainValidationEnabled = YES;
    }

    return self;
}

- (void)updateSecurityOptionsInStream:(NSStream *)stream {
    // Enforce TLS 1.2
    [stream setProperty:(__bridge id)CFSTR("kCFStreamSocketSecurityLevelTLSv1_2") forKey:(__bridge id)kCFStreamPropertySocketSecurityLevel];

    // Validate certificate chain for this stream if enabled.
    NSDictionary<NSString *, id> *sslOptions = @{ (__bridge NSString *)kCFStreamSSLValidatesCertificateChain : @(self.certificateChainValidationEnabled) };
    [stream setProperty:sslOptions forKey:(__bridge NSString *)kCFStreamPropertySSLSettings];
}

- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust forDomain:(NSString *)domain {
    // No further evaluation happens in the default policy.
    return YES;
}

@end

@interface ZLRunLoopThread : NSThread

@property (nonatomic, strong) NSRunLoop *runLoop;

+ (instancetype)sharedThread;

@end

@interface ZLRunLoopThread () {
    dispatch_group_t _waitGroup;
}

@end

@implementation ZLRunLoopThread

+ (instancetype)sharedThread {
    static ZLRunLoopThread *thread;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        thread = [[ZLRunLoopThread alloc] init];
        thread.name = @"com.richie.ZLWebSocket.NetworkThread";
        [thread start];
    });
    return thread;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _waitGroup = dispatch_group_create();
        dispatch_group_enter(_waitGroup);
    }
    return self;
}

- (void)main {
    @autoreleasepool {
        _runLoop = [NSRunLoop currentRunLoop];
        dispatch_group_leave(_waitGroup);

        // Add an empty run loop source to prevent runloop from spinning.
        CFRunLoopSourceContext sourceCtx = {
            .version = 0,
            .info = NULL,
            .retain = NULL,
            .release = NULL,
            .copyDescription = NULL,
            .equal = NULL,
            .hash = NULL,
            .schedule = NULL,
            .cancel = NULL,
            .perform = NULL
        };
        CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &sourceCtx);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
        CFRelease(source);

        while ([_runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]) {

        }
        assert(NO);
    }
}

- (NSRunLoop *)runLoop {
    dispatch_group_wait(_waitGroup, DISPATCH_TIME_FOREVER);
    return _runLoop;
}

@end

typedef void(^ZLProxyConnectCompletion)(NSError *_Nullable error,
                                        NSInputStream *_Nullable readStream,
                                        NSOutputStream *_Nullable writeStream);

@interface ZLProxyConnect : NSObject

- (instancetype)initWithURL:(NSURL *)url;

- (void)openNetworkStreamWithCompletion:(ZLProxyConnectCompletion)completion;

@end

@interface ZLProxyConnect() <NSStreamDelegate> {
    ZLProxyConnectCompletion _completion;

    NSString *_httpProxyHost;
    uint32_t _httpProxyPort;

    CFHTTPMessageRef _receivedHTTPHeaders;

    NSString *_socksProxyHost;
    uint32_t _socksProxyPort;
    NSString *_socksProxyUsername;
    NSString *_socksProxyPassword;

    BOOL _connectionRequiresSSL;

    NSMutableArray<NSData *> *_inputQueue;
    dispatch_queue_t _writeQueue;
}

@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;

@end

@implementation ZLProxyConnect

///--------------------------------------
#pragma mark - Init
///--------------------------------------

-(instancetype)initWithURL:(NSURL *)url {
    self = [super init];
    if (!self) return self;

    _url = url;
    _connectionRequiresSSL = ZLURLRequiresSSL(url);

    _writeQueue = dispatch_queue_create("com.richie.ZLWebSocket.proxyconnect.write", DISPATCH_QUEUE_SERIAL);
    _inputQueue = [NSMutableArray arrayWithCapacity:2];

    return self;
}

- (void)dealloc {
    // If we get deallocated before the socket open finishes - we need to cleanup everything.

    [self.inputStream removeFromRunLoop:[ZLRunLoopThread sharedThread].runLoop forMode:NSDefaultRunLoopMode];
    self.inputStream.delegate = nil;
    [self.inputStream close];
    self.inputStream = nil;

    self.outputStream.delegate = nil;
    [self.outputStream close];
    self.outputStream = nil;
}

///--------------------------------------
#pragma mark - Open
///--------------------------------------

- (void)openNetworkStreamWithCompletion:(ZLProxyConnectCompletion)completion {
    _completion = completion;
    [self _configureProxy];
}

///--------------------------------------
#pragma mark - Flow
///--------------------------------------

- (void)_didConnect {
    if (_connectionRequiresSSL) {
        if (_httpProxyHost) {
            // Must set the real peer name before turning on SSL
            [self.outputStream setProperty:self.url.host forKey:@"_kCFStreamPropertySocketPeerName"];
        }
    }
    if (_receivedHTTPHeaders) {
        CFRelease(_receivedHTTPHeaders);
        _receivedHTTPHeaders = NULL;
    }

    NSInputStream *inputStream = self.inputStream;
    NSOutputStream *outputStream = self.outputStream;

    self.inputStream = nil;
    self.outputStream = nil;

    [inputStream removeFromRunLoop:[ZLRunLoopThread sharedThread].runLoop forMode:NSDefaultRunLoopMode];
    inputStream.delegate = nil;
    outputStream.delegate = nil;

    _completion(nil, inputStream, outputStream);
}

- (void)_failWithError:(NSError *)error {
    if (!error) {
        error = [NSError errorWithDomain:ZLWebSocketErrorDomain
                                    code:500
                                userInfo:@{NSLocalizedDescriptionKey: @"Proxy Error",
                                            ZLHTTPResponseErrorKey: @(2132) }];
    }

    if (_receivedHTTPHeaders) {
        CFRelease(_receivedHTTPHeaders);
        _receivedHTTPHeaders = NULL;
    }

    self.inputStream.delegate = nil;
    self.outputStream.delegate = nil;

    [self.inputStream removeFromRunLoop:[ZLRunLoopThread sharedThread].runLoop
                                forMode:NSDefaultRunLoopMode];
    [self.inputStream close];
    [self.outputStream close];
    self.inputStream = nil;
    self.outputStream = nil;
    _completion(error, nil, nil);
}

// get proxy setting from device setting
- (void)_configureProxy {
    NSDictionary *proxySettings = CFBridgingRelease(CFNetworkCopySystemProxySettings());

    // CFNetworkCopyProxiesForURL doesn't understand ws:// or wss://
    NSURL *httpURL;
    if (_connectionRequiresSSL) {
        httpURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@", _url.host]];
    } else {
        httpURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@", _url.host]];
    }

    NSArray *proxies = CFBridgingRelease(CFNetworkCopyProxiesForURL((__bridge CFURLRef)httpURL, (__bridge CFDictionaryRef)proxySettings));
    if (proxies.count == 0) {
        [self _openConnection];
        return;                 // no proxy
    }
    NSDictionary *settings = [proxies objectAtIndex:0];
    NSString *proxyType = settings[(NSString *)kCFProxyTypeKey];
    if ([proxyType isEqualToString:(NSString *)kCFProxyTypeAutoConfigurationURL]) {
        NSURL *pacURL = settings[(NSString *)kCFProxyAutoConfigurationURLKey];
        if (pacURL) {
            [self _fetchPAC:pacURL withProxySettings:proxySettings];
            return;
        }
    }
    if ([proxyType isEqualToString:(__bridge NSString *)kCFProxyTypeAutoConfigurationJavaScript]) {
        NSString *script = settings[(__bridge NSString *)kCFProxyAutoConfigurationJavaScriptKey];
        if (script) {
            [self _runPACScript:script withProxySettings:proxySettings];
            return;
        }
    }
    [self _readProxySettingWithType:proxyType settings:settings];

    [self _openConnection];
}

- (void)_readProxySettingWithType:(NSString *)proxyType settings:(NSDictionary *)settings {
    if ([proxyType isEqualToString:(NSString *)kCFProxyTypeHTTP] ||
        [proxyType isEqualToString:(NSString *)kCFProxyTypeHTTPS]) {
        _httpProxyHost = settings[(NSString *)kCFProxyHostNameKey];
        NSNumber *portValue = settings[(NSString *)kCFProxyPortNumberKey];
        if (portValue) {
            _httpProxyPort = [portValue intValue];
        }
    }
    if ([proxyType isEqualToString:(NSString *)kCFProxyTypeSOCKS]) {
        _socksProxyHost = settings[(NSString *)kCFProxyHostNameKey];
        NSNumber *portValue = settings[(NSString *)kCFProxyPortNumberKey];
        if (portValue)
            _socksProxyPort = [portValue intValue];
        _socksProxyUsername = settings[(NSString *)kCFProxyUsernameKey];
        _socksProxyPassword = settings[(NSString *)kCFProxyPasswordKey];
    }
}

- (void)_fetchPAC:(NSURL *)PACurl withProxySettings:(NSDictionary *)proxySettings {
    if ([PACurl isFileURL]) {
        NSError *error = nil;
        NSString *script = [NSString stringWithContentsOfURL:PACurl
                                                usedEncoding:NULL
                                                       error:&error];

        if (error) {
            [self _openConnection];
        } else {
            [self _runPACScript:script withProxySettings:proxySettings];
        }
        return;
    }

    NSString *scheme = [PACurl.scheme lowercaseString];
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        // Don't know how to read data from this URL, we'll have to give up
        // We'll simply assume no proxies, and start the request as normal
        [self _openConnection];
        return;
    }
    __weak typeof(self) wself = self;
    NSURLRequest *request = [NSURLRequest requestWithURL:PACurl];
    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(wself) sself = wself;
        if (!error) {
            NSString *script = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            [sself _runPACScript:script withProxySettings:proxySettings];
        } else {
            [sself _openConnection];
        }
    }] resume];
}

- (void)_runPACScript:(NSString *)script withProxySettings:(NSDictionary *)proxySettings {
    if (!script) {
        [self _openConnection];
        return;
    }
    // From: http://developer.apple.com/samplecode/CFProxySupportTool/listing1.html
    // Work around <rdar://problem/5530166>.  This dummy call to
    // CFNetworkCopyProxiesForURL initialise some state within CFNetwork
    // that is required by CFNetworkCopyProxiesForAutoConfigurationScript.
    CFBridgingRelease(CFNetworkCopyProxiesForURL((__bridge CFURLRef)_url, (__bridge CFDictionaryRef)proxySettings));

    // Obtain the list of proxies by running the autoconfiguration script
    CFErrorRef err = NULL;

    // CFNetworkCopyProxiesForAutoConfigurationScript doesn't understand ws:// or wss://
    NSURL *httpURL;
    if (_connectionRequiresSSL)
        httpURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://%@", _url.host]];
    else
        httpURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@", _url.host]];

    NSArray *proxies = CFBridgingRelease(CFNetworkCopyProxiesForAutoConfigurationScript((__bridge CFStringRef)script,(__bridge CFURLRef)httpURL, &err));
    if (!err && [proxies count] > 0) {
        NSDictionary *settings = [proxies objectAtIndex:0];
        NSString *proxyType = settings[(NSString *)kCFProxyTypeKey];
        [self _readProxySettingWithType:proxyType settings:settings];
    }
    [self _openConnection];
}

- (void)_openConnection {
    [self _initializeStreams];

    [self.inputStream scheduleInRunLoop:[ZLRunLoopThread sharedThread].runLoop
                                forMode:NSDefaultRunLoopMode];
//    [self.outputStream scheduleInRunLoop:[ZLRunLoopThread sharedThread].runLoop
//                               forMode:NSDefaultRunLoopMode];
    [self.outputStream open];
    [self.inputStream open];
}

- (void)_initializeStreams {
    assert(_url.port.unsignedIntValue <= UINT32_MAX);
    uint32_t port = _url.port.unsignedIntValue;
    if (port == 0) {
        port = (_connectionRequiresSSL ? 443 : 80);
    }
    NSString *host = _url.host;

    if (_httpProxyHost) {
        host = _httpProxyHost;
        port = (_httpProxyPort ?: 80);
    }

    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;

    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)host, port, &readStream, &writeStream);

    self.outputStream = CFBridgingRelease(writeStream);
    self.inputStream = CFBridgingRelease(readStream);

    if (_socksProxyHost) {
        NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithCapacity:4];
        settings[NSStreamSOCKSProxyHostKey] = _socksProxyHost;
        if (_socksProxyPort) {
            settings[NSStreamSOCKSProxyPortKey] = @(_socksProxyPort);
        }
        if (_socksProxyUsername) {
            settings[NSStreamSOCKSProxyUserKey] = _socksProxyUsername;
        }
        if (_socksProxyPassword) {
            settings[NSStreamSOCKSProxyPasswordKey] = _socksProxyPassword;
        }
        [self.inputStream setProperty:settings forKey:NSStreamSOCKSProxyConfigurationKey];
        [self.outputStream setProperty:settings forKey:NSStreamSOCKSProxyConfigurationKey];
    }
    self.inputStream.delegate = self;
    self.outputStream.delegate = self;
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode; {
    switch (eventCode) {
        case NSStreamEventOpenCompleted: {
            if (aStream == self.inputStream) {
                if (_httpProxyHost) {
                    [self _proxyDidConnect];
                } else {
                    [self _didConnect];
                }
            }
        }  break;
        case NSStreamEventErrorOccurred: {
            [self _failWithError:aStream.streamError];
        } break;
        case NSStreamEventEndEncountered: {
            [self _failWithError:aStream.streamError];
        } break;
        case NSStreamEventHasBytesAvailable: {
            if (aStream == _inputStream) {
                [self _processInputStream];
            }
        } break;
        case NSStreamEventHasSpaceAvailable:
        case NSStreamEventNone:
            break;
    }
}

- (void)_proxyDidConnect {
    uint32_t port = _url.port.unsignedIntValue;
    if (port == 0) {
        port = (_connectionRequiresSSL ? 443 : 80);
    }
    // Send HTTP CONNECT Request
    NSString *connectRequestStr = [NSString stringWithFormat:@"CONNECT %@:%u HTTP/1.1\r\nHost: %@\r\nConnection: keep-alive\r\nProxy-Connection: keep-alive\r\n\r\n", _url.host, port, _url.host];

    NSData *message = [connectRequestStr dataUsingEncoding:NSUTF8StringEncoding];

    [self _writeData:message];
}

///handles the incoming bytes and sending them to the proper processing method
- (void)_processInputStream {
    NSMutableData *buf = [NSMutableData dataWithCapacity:ZLDefaultBufferSize()];
    uint8_t *buffer = buf.mutableBytes;
    NSInteger length = [_inputStream read:buffer maxLength:ZLDefaultBufferSize()];

    if (length <= 0) {
        return;
    }

    BOOL process = (_inputQueue.count == 0);
    [_inputQueue addObject:[NSData dataWithBytes:buffer length:length]];

    if (process) {
        [self _dequeueInput];
    }
}

// dequeue the incoming input so it is processed in order

- (void)_dequeueInput {
    while (_inputQueue.count > 0) {
        NSData *data = _inputQueue.firstObject;
        [_inputQueue removeObjectAtIndex:0];

        // No need to process any data further, we got the full header data.
        if ([self _proxyProcessHTTPResponseWithData:data]) {
            break;
        }
    }
}
//handle checking the proxy  connection status
- (BOOL)_proxyProcessHTTPResponseWithData:(NSData *)data {
    if (_receivedHTTPHeaders == NULL) {
        _receivedHTTPHeaders = CFHTTPMessageCreateEmpty(NULL, NO);
    }

    CFHTTPMessageAppendBytes(_receivedHTTPHeaders, (const UInt8 *)data.bytes, data.length);
    if (CFHTTPMessageIsHeaderComplete(_receivedHTTPHeaders)) {
        [self _proxyHTTPHeadersDidFinish];
        return YES;
    }

    return NO;
}

- (void)_proxyHTTPHeadersDidFinish {
    NSInteger responseCode = CFHTTPMessageGetResponseStatusCode(_receivedHTTPHeaders);

    if (responseCode >= 299) {
        NSError *error = [NSError errorWithDomain:ZLWebSocketErrorDomain
                                             code:responseCode
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Received bad response code from proxy server: %d.",
                                                    (int)responseCode],
                                                     ZLHTTPResponseErrorKey: @(2132) }];
        [self _failWithError:error];
        return;
    }
    [self _didConnect];
}

static NSTimeInterval const SRProxyConnectWriteTimeout = 5.0;

- (void)_writeData:(NSData *)data {
    const uint8_t * bytes = data.bytes;
    __block NSInteger timeout = (NSInteger)(SRProxyConnectWriteTimeout * 1000000); // wait timeout before giving up
    __weak typeof(self) wself = self;
    dispatch_async(_writeQueue, ^{
        __strong typeof(wself) sself = self;
        if (!sself) {
            return;
        }
        NSOutputStream *outStream = sself.outputStream;
        if (!outStream) {
            return;
        }
        while (![outStream hasSpaceAvailable]) {
            usleep(100); //wait until the socket is ready
            timeout -= 100;
            if (timeout < 0) {
                NSError *error = [NSError errorWithDomain:ZLWebSocketErrorDomain
                                                     code:408
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Proxy timeout",
                                                             ZLHTTPResponseErrorKey: @(2132)}];;
                [sself _failWithError:error];
            } else if (outStream.streamError != nil) {
                [sself _failWithError:outStream.streamError];
            }
        }
        [outStream write:bytes maxLength:data.length];
    });
}

@end

@interface ZLWebSocket () <NSStreamDelegate> {
    NSRecursiveLock *_kvoLock;

    dispatch_queue_t _workQueue;
    dispatch_queue_t _dispatchQueue;
    NSMutableArray<ZLIOConsumer *> *_consumers;

    NSInputStream *_inputStream;
    NSOutputStream *_outputStream;

    dispatch_data_t _readBuffer;
    NSUInteger _readBufferOffset;

    dispatch_data_t _outputBuffer;
    NSUInteger _outputBufferOffset;

    uint8_t _currentFrameOpcode;
    size_t _currentFrameCount;
    size_t _readOpCount;
    uint32_t _currentStringScanPosition;
    NSMutableData *_currentFrameData;

    NSString *_closeReason;

    NSString *_secKey;

    ZLSecurityPolicy *_securityPolicy;
    BOOL _requestRequiresSSL;
    BOOL _streamSecurityValidated;

    uint8_t _currentReadMaskKey[4];
    size_t _currentReadMaskOffset;

    BOOL _closeWhenFinishedWriting;
    BOOL _failed;

    NSURLRequest *_urlRequest;

    BOOL _sentClose;
    BOOL _didFail;
    BOOL _cleanupScheduled;
    int _closeCode;

    BOOL _isPumping;

    NSMutableSet<NSArray *> *_scheduledRunloops; // Set<[RunLoop, Mode]>. TODO: (nlutsenko) Fix clowntown

    NSArray<NSString *> *_requestedProtocols;
    ZLIOConsumerPool *_consumerPool;

    // proxy support
    ZLProxyConnect *_proxyConnect;
    
    BOOL _awaitingPong;
    unsigned long _sentPingCount;
    NSTimer *_pingTimer;
    
    NSTimeInterval _reconnectInterval;
    unsigned int _reconnectCount;
    NSTimer *_reconnectTimer;
}

@property (atomic, assign, readwrite) ZLReadyState readyState;

// Specifies whether SSL trust chain should NOT be evaluated.
// By default this flag is set to NO, meaning only secure SSL connections are allowed.
// For DEBUG builds this flag is ignored, and SSL connections are allowed regardless
// of the certificate trust configuration
@property (nonatomic, assign, readwrite) BOOL allowsUntrustedSSLCertificates;

@end

@implementation ZLWebSocket

@synthesize readyState = _readyState;

- (instancetype)initWithURLRequest:(NSURLRequest *)request {
    return [self initWithURLRequest:request protocols:nil securityPolicy:[ZLSecurityPolicy defaultPolicy]];
}

- (instancetype)initWithURLRequest:(NSURLRequest *)request securityPolicy:(ZLSecurityPolicy *)securityPolicy {
    return [self initWithURLRequest:request protocols:nil securityPolicy:securityPolicy];
}

- (instancetype)initWithURLRequest:(NSURLRequest *)request protocols:(nullable NSArray<NSString *> *)protocols {
    return [self initWithURLRequest:request protocols:protocols securityPolicy:[ZLSecurityPolicy defaultPolicy]];
}

- (instancetype)initWithURLRequest:(NSURLRequest *)request protocols:(nullable NSArray<NSString *> *)protocols securityPolicy:(ZLSecurityPolicy *)securityPolicy {
    self = [super init];
    if (!self) return self;

    assert(request.URL);
    _url = request.URL;
    _urlRequest = request;
    _requestedProtocols = [protocols copy];
    _securityPolicy = securityPolicy;
    _requestRequiresSSL = ZLURLRequiresSSL(_url);

    _readyState = ZL_UNKNOWN;

    _kvoLock = [[NSRecursiveLock alloc] init];
    _workQueue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
    _dispatchQueue = dispatch_queue_create("com.richie.ZLWebSocket.dispatchQ", DISPATCH_QUEUE_SERIAL);

    // Going to set a specific on the queue so we can validate we're on the work queue
    dispatch_queue_set_specific(_workQueue, (__bridge void *)self, (__bridge void *)(_workQueue), NULL);

    _readBuffer = dispatch_data_empty;
    _outputBuffer = dispatch_data_empty;

    _currentFrameData = [[NSMutableData alloc] init];

    _consumers = [[NSMutableArray alloc] init];

    _consumerPool = [[ZLIOConsumerPool alloc] init];

    _scheduledRunloops = [[NSMutableSet alloc] init];
    
    _pingInterval = 5;
    
    _reconnectInterval = 1.5;
    
    _reconnectCount = 0;

    return self;
}

- (instancetype)initWithURL:(NSURL *)url {
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    return [self initWithURLRequest:request protocols:nil securityPolicy:[ZLSecurityPolicy defaultPolicy]];
}

- (instancetype)initWithURL:(NSURL *)url protocols:(nullable NSArray<NSString *> *)protocols {
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    return [self initWithURLRequest:request protocols:protocols securityPolicy:[ZLSecurityPolicy defaultPolicy]];
}

- (instancetype)initWithURL:(NSURL *)url securityPolicy:(ZLSecurityPolicy *)securityPolicy {
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    return [self initWithURLRequest:request protocols:nil securityPolicy:securityPolicy];
}

///--------------------------------------
#pragma mark - Dealloc
///--------------------------------------

- (void)dealloc {
    _inputStream.delegate = nil;
    _outputStream.delegate = nil;

    [_inputStream close];
    [_outputStream close];

    if (_receivedHTTPHeaders) {
        CFRelease(_receivedHTTPHeaders);
        _receivedHTTPHeaders = NULL;
    }

    _kvoLock = nil;
}

#pragma mark - Ping
- (void)initPingTimer {
    if (_pingTimer) {
        if (_pingTimer.isValid) {
            if ([_pingTimer.fireDate isEqualToDate:[NSDate distantFuture]]) {
                _pingTimer.fireDate = [NSDate date];
                return;
            }
            return;
        }
        
        _pingTimer = nil;
    }
    __weak typeof(self) weakSelf = self;
    _pingTimer = [NSTimer timerWithTimeInterval:self.pingInterval repeats:YES block:^(NSTimer * _Nonnull timer) {
        __strong typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        [strongSelf writePingFrame];
    }];
    [[ZLRunLoopThread sharedThread].runLoop addTimer:_pingTimer forMode:NSRunLoopCommonModes];
}

- (void)pausePingTimer {
    if (_pingTimer && _pingTimer.isValid) {
        _pingTimer.fireDate = [NSDate distantFuture];
    }
}

- (void)writePingFrame {
    if (self.readyState == ZL_OPEN) {
        if (_awaitingPong) {
            // TODO
            [self close];
            return;
        }
        [self sendPing:nil error:nil];
        _awaitingPong = YES;
    }
}

#pragma mark readyState

- (void)setReadyState:(ZLReadyState)readyState {
    @try {
        [_kvoLock lock];
        if (_readyState != readyState) {
            [self willChangeValueForKey:@"readyState"];
            _readyState = readyState;
            [self didChangeValueForKey:@"readyState"];
        }
    }
    @finally {
        [_kvoLock unlock];
    }
}

- (ZLReadyState)readyState {
    ZLReadyState state = 0;
    [_kvoLock lock];
    state = _readyState;
    [_kvoLock unlock];
    return state;
}

- (void)open {
    if (self.readyState == ZL_CONNECTING || self.readyState == ZL_OPEN) {
        return;
    }
    self.readyState = ZL_CONNECTING;
    
    if (_urlRequest.timeoutInterval > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_urlRequest.timeoutInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.readyState == ZL_CONNECTING) {
                NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:@{NSLocalizedDescriptionKey: @"Timed out connecting to server."}];
                [self _failWithError:error];
            }
        });
    }

    _proxyConnect = [[ZLProxyConnect alloc] initWithURL:_url];

    __weak typeof(self) wself = self;
    [_proxyConnect openNetworkStreamWithCompletion:^(NSError *error, NSInputStream *readStream, NSOutputStream *writeStream) {
        [wself _connectionDoneWithError:error readStream:readStream writeStream:writeStream];
    }];
}

- (void)reconnect {
    if (self.delegate == nil || !([self.delegate respondsToSelector:@selector(webSocketReConnectURL)] || [self.delegate respondsToSelector:@selector(webSocketReConnectRequest)])) {
        return;
    }
    if (self.readyState == ZL_RECONNECT) {
        return;
    }
    self.readyState = ZL_RECONNECT;
    _reconnectCount++;
    
    _closeWhenFinishedWriting = NO;
    _failed = NO;
    _sentClose = NO;
    _didFail = NO;
    _cleanupScheduled = NO;
    _isPumping = NO;
    
    _readBufferOffset = 0;
    _outputBufferOffset = 0;
    _currentFrameOpcode = 0;
    _currentFrameCount = 0;
    _readOpCount = 0;
    _currentStringScanPosition = 0;
    _currentReadMaskOffset = 0;
    
    _readBuffer = dispatch_data_empty;
    _outputBuffer = dispatch_data_empty;
    _currentFrameData = [[NSMutableData alloc] init];
    
    if (_receivedHTTPHeaders) {
        CFRelease(_receivedHTTPHeaders);
        _receivedHTTPHeaders = NULL;
    }
    
    if ([self.delegate respondsToSelector:@selector(webSocketReConnectURL)]) {
        _url = [self.delegate webSocketReConnectURL];
        _urlRequest = [NSURLRequest requestWithURL:_url];
    } else {
        _urlRequest = [self.delegate webSocketReConnectRequest];
        _url = _urlRequest.URL;
    }
    [self open];
}

- (void)privateReconnect {
    if (_reconnectTimer != NULL) {
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    _reconnectTimer = [NSTimer timerWithTimeInterval:(_reconnectCount + 1) * _reconnectInterval repeats:NO block:^(NSTimer * _Nonnull timer) {
        __strong typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        [strongSelf reconnect];
        [strongSelf->_reconnectTimer invalidate];
        strongSelf->_reconnectTimer = nil;
    }];
    [[ZLRunLoopThread sharedThread].runLoop addTimer:_reconnectTimer forMode:NSRunLoopCommonModes];
}

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode {
    [_outputStream scheduleInRunLoop:aRunLoop forMode:mode];
    [_inputStream scheduleInRunLoop:aRunLoop forMode:mode];

    [_scheduledRunloops addObject:@[aRunLoop, mode]];
}

- (void)unscheduleFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode {
    [_outputStream removeFromRunLoop:aRunLoop forMode:mode];
    [_inputStream removeFromRunLoop:aRunLoop forMode:mode];

    [_scheduledRunloops removeObject:@[aRunLoop, mode]];
}

- (void)close {
    [self closeWithCode:ZLStatusCodeNormal reason:nil];
}

- (void)closeWithCode:(NSInteger)code reason:(NSString *)reason {
    assert(code);
    dispatch_async(_workQueue, ^{
        if (self.readyState == ZL_CLOSING || self.readyState == ZL_CLOSED) {
            return;
        }

        BOOL wasConnecting = self.readyState == ZL_CONNECTING;

        self.readyState = ZL_CLOSING;

        if (wasConnecting) {
            [self closeConnection];
            return;
        }

        size_t maxMsgSize = [reason maximumLengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        NSMutableData *mutablePayload = [[NSMutableData alloc] initWithLength:sizeof(uint16_t) + maxMsgSize];
        NSData *payload = mutablePayload;

        ((uint16_t *)mutablePayload.mutableBytes)[0] = CFSwapInt16BigToHost((uint16_t)code);

        if (reason) {
            NSRange remainingRange = {0};

            NSUInteger usedLength = 0;

            BOOL success = [reason getBytes:(char *)mutablePayload.mutableBytes + sizeof(uint16_t) maxLength:payload.length - sizeof(uint16_t) usedLength:&usedLength encoding:NSUTF8StringEncoding options:NSStringEncodingConversionExternalRepresentation range:NSMakeRange(0, reason.length) remainingRange:&remainingRange];
#pragma unused (success)

            assert(success);
            assert(remainingRange.length == 0);

            if (usedLength != maxMsgSize) {
                payload = [payload subdataWithRange:NSMakeRange(0, usedLength + sizeof(uint16_t))];
            }
        }


        [self _sendFrameWithOpcode:ZLOpCodeConnectionClose data:payload];
    });
}

- (BOOL)sendString:(NSString *)string error:(NSError **)error {
    if (self.readyState != ZL_OPEN) {
        NSString *message = @"Invalid State: Cannot call `sendString:error:` until connection is open.";
        if (error) {
            *error = [NSError errorWithDomain:ZLWebSocketErrorDomain code:2134 userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return NO;
    }

    string = [string copy];
    dispatch_async(_workQueue, ^{
        [self _sendFrameWithOpcode:ZLOpCodeTextFrame data:[string dataUsingEncoding:NSUTF8StringEncoding]];
    });
    return YES;
}

- (BOOL)sendData:(nullable NSData *)data error:(NSError **)error {
    data = [data copy];
    return [self sendDataNoCopy:data error:error];
}

- (BOOL)sendDataNoCopy:(nullable NSData *)data error:(NSError **)error {
    if (self.readyState != ZL_OPEN) {
        NSString *message = @"Invalid State: Cannot call `sendDataNoCopy:error:` until connection is open.";
        if (error) {
            *error = [NSError errorWithDomain:ZLWebSocketErrorDomain code:2134 userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return NO;
    }

    dispatch_async(_workQueue, ^{
        if (data) {
            [self _sendFrameWithOpcode:ZLOpCodeBinaryFrame data:data];
        } else {
            [self _sendFrameWithOpcode:ZLOpCodeTextFrame data:nil];
        }
    });
    return YES;
}

- (BOOL)sendPing:(nullable NSData *)data error:(NSError **)error {
    if (self.readyState != ZL_OPEN) {
        NSString *message = @"Invalid State: Cannot call `sendPing:error:` until connection is open.";
        if (error) {
            *error = [NSError errorWithDomain:ZLWebSocketErrorDomain code:2134 userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return NO;
    }

    data = [data copy] ?: [NSData data]; // It's okay for a ping to be empty
    dispatch_async(_workQueue, ^{
        [self _sendFrameWithOpcode:ZLOpCodePing data:data];
    });
    return YES;
}

- (void)didConnect {
    _secKey = ZLBase64EncodedStringFromData(ZLRandomData(16));
    assert([_secKey length] == 24);

    CFHTTPMessageRef message = ZLHTTPConnectMessageCreate(_urlRequest,
                                                          _secKey,
                                                          ZLWebSocketProtocolVersion,
                                                          self.requestCookies,
                                                          _requestedProtocols);

    NSData *messageData = CFBridgingRelease(CFHTTPMessageCopySerializedMessage(message));

    CFRelease(message);

    [self _writeData:messageData];
    [self _readHTTPHeader];
}

- (void)closeConnection {
    [self assertOnWorkQueue];
    _closeWhenFinishedWriting = YES;
    [self _pumpWriting];
}

- (void)_readHTTPHeader {
    if (_receivedHTTPHeaders == NULL) {
        _receivedHTTPHeaders = CFHTTPMessageCreateEmpty(NULL, NO);
    }

    [self _readUntilHeaderCompleteWithCallback:^(ZLWebSocket *socket,  NSData *data) {
        CFHTTPMessageRef receivedHeaders = self->_receivedHTTPHeaders;
        CFHTTPMessageAppendBytes(receivedHeaders, (const UInt8 *)data.bytes, data.length);

        if (CFHTTPMessageIsHeaderComplete(receivedHeaders)) {
            [self _HTTPHeadersDidFinish];
        } else {
            [self _readHTTPHeader];
        }
    }];
}

- (BOOL)_checkHandshake:(CFHTTPMessageRef)httpMessage {
    NSString *acceptHeader = CFBridgingRelease(CFHTTPMessageCopyHeaderFieldValue(httpMessage, CFSTR("Sec-WebSocket-Accept")));

    if (acceptHeader == nil) {
        return NO;
    }

    NSString *concattedString = [_secKey stringByAppendingString:ZLWebSocketAppendToSecKeyString];
    NSData *hashedString = ZLSHA1HashFromString(concattedString);
    NSString *expectedAccept = ZLBase64EncodedStringFromData(hashedString);
    return [acceptHeader isEqualToString:expectedAccept];
}

- (void)_HTTPHeadersDidFinish {
    NSInteger responseCode = CFHTTPMessageGetResponseStatusCode(_receivedHTTPHeaders);
    if (responseCode >= 400) {
        NSError *error = [NSError errorWithDomain:ZLWebSocketErrorDomain
                                             code:responseCode
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Received bad response code from server: %d.",
                                                    (int)responseCode],
                                                     ZLHTTPResponseErrorKey: @(2132)}];
        [self _failWithError:error];
        return;
    }

    if(![self _checkHandshake:_receivedHTTPHeaders]) {
        NSError *error = [NSError errorWithDomain:ZLWebSocketErrorDomain code:2133 userInfo:@{NSLocalizedDescriptionKey: @"Invalid Sec-WebSocket-Accept response."}];
        [self _failWithError:error];
        return;
    }

    NSString *negotiatedProtocol = CFBridgingRelease(CFHTTPMessageCopyHeaderFieldValue(_receivedHTTPHeaders, CFSTR("Sec-WebSocket-Protocol")));
    if (negotiatedProtocol) {
        // Make sure we requested the protocol
        if ([_requestedProtocols indexOfObject:negotiatedProtocol] == NSNotFound) {
            NSError *error = [NSError errorWithDomain:ZLWebSocketErrorDomain code:2133 userInfo:@{NSLocalizedDescriptionKey: @"Server specified Sec-WebSocket-Protocol that wasn't requested."}];
            [self _failWithError:error];
            return;
        }

        _protocol = negotiatedProtocol;
    }

    self.readyState = ZL_OPEN;

    if (!_didFail) {
        [self _readFrameNew];
    }

    [self performDelegateBlock:^(ZLWebSocket *webSocket) {
        // 初始化ping
        webSocket->_reconnectCount = 0;
        [webSocket initPingTimer];
        
        if (webSocket.delegate && [webSocket.delegate respondsToSelector:@selector(webSocketDidOpen:)]) {
            [webSocket.delegate webSocketDidOpen:webSocket];
        }
    }];
}

- (void)_failWithError:(NSError *)error {
    dispatch_async(_workQueue, ^{
        if (self.readyState != ZL_CLOSED) {
            self->_failed = YES;
            [self performDelegateBlock:^(ZLWebSocket *webSocket) {                
                if (webSocket.delegate && [webSocket.delegate respondsToSelector:@selector(webSocket:didFailWithError:)]) {
                    [webSocket.delegate webSocket:webSocket didFailWithError:error];
                }
                
                [webSocket privateReconnect];
            }];

            self.readyState = ZL_CLOSED;

            [self closeConnection];
            [self _scheduleCleanup];
        }
    });
}

- (void)_updateSecureStreamOptions {
    if (_requestRequiresSSL) {
        [_securityPolicy updateSecurityOptionsInStream:_inputStream];
        [_securityPolicy updateSecurityOptionsInStream:_outputStream];
    }

    NSString *networkServiceType = SRStreamNetworkServiceTypeFromURLRequest(_urlRequest);
    if (networkServiceType != nil) {
        [_inputStream setProperty:networkServiceType forKey:NSStreamNetworkServiceType];
        [_outputStream setProperty:networkServiceType forKey:NSStreamNetworkServiceType];
    }
}

- (void)_connectionDoneWithError:(NSError *)error readStream:(NSInputStream *)readStream writeStream:(NSOutputStream *)writeStream {
    if (error != nil) {
        [self _failWithError:error];
    } else {
        _outputStream = writeStream;
        _inputStream = readStream;

        _inputStream.delegate = self;
        _outputStream.delegate = self;
        [self _updateSecureStreamOptions];

        if (!_scheduledRunloops.count) {
            [self scheduleInRunLoop:[ZLRunLoopThread sharedThread].runLoop forMode:NSDefaultRunLoopMode];
        }

        // If we don't require SSL validation - consider that we connected.
        // Otherwise `didConnect` is called when SSL validation finishes.
        if (!_requestRequiresSSL) {
            dispatch_async(_workQueue, ^{
                [self didConnect];
            });
        }
    }
    // Schedule to run on a work queue, to make sure we don't run this inline and deallocate `self` inside `SRProxyConnect`.
    // TODO: (nlutsenko) Find a better structure for this, maybe Bolts Tasks?
    dispatch_async(_workQueue, ^{
        self->_proxyConnect = nil;
    });
}

- (void)assertOnWorkQueue {
    assert(dispatch_get_specific((__bridge void *)self) == (__bridge void *)_workQueue);
}

- (void)_scheduleCleanup {
    @synchronized(self) {
        if (_cleanupScheduled) {
            return;
        }

        _cleanupScheduled = YES;

        // Cleanup NSStream delegate's in the same RunLoop used by the streams themselves:
        // This way we'll prevent race conditions between handleEvent and ZLWebSocket's dealloc
        NSTimer *timer = [NSTimer timerWithTimeInterval:(0.0f) target:self selector:@selector(_cleanupSelfReference:) userInfo:nil repeats:NO];
        [[ZLRunLoopThread sharedThread].runLoop addTimer:timer forMode:NSDefaultRunLoopMode];
    }
}

- (void)_cleanupSelfReference:(NSTimer *)timer {
    @synchronized(self) {
        // Nuke NSStream delegate's
        _inputStream.delegate = nil;
        _outputStream.delegate = nil;

        // Remove the streams, right now, from the networkRunLoop
        [_inputStream close];
        [_outputStream close];
    }
}

- (void)_pumpWriting; {
    [self assertOnWorkQueue];

    NSUInteger dataLength = dispatch_data_get_size(_outputBuffer);
    if (dataLength - _outputBufferOffset > 0 && _outputStream.hasSpaceAvailable) {
        __block NSInteger bytesWritten = 0;
        __block BOOL streamFailed = NO;

        dispatch_data_t dataToSend = dispatch_data_create_subrange(_outputBuffer, _outputBufferOffset, dataLength - _outputBufferOffset);
        dispatch_data_apply(dataToSend, ^bool(dispatch_data_t region, size_t offset, const void *buffer, size_t size) {
            NSInteger sentLength = [_outputStream write:buffer maxLength:size];
            if (sentLength == -1) {
                streamFailed = YES;
                return false;
            }
            bytesWritten += sentLength;
            return (sentLength >= (NSInteger)size); // If we can't write all the data into the stream - bail-out early.
        });
        if (streamFailed) {
            NSInteger code = 2145;
            NSString *description = @"Error writing to stream.";
            NSError *streamError = _outputStream.streamError;
            NSError *error = [NSError errorWithDomain:ZLWebSocketErrorDomain
                                                 code:code
                                             userInfo:streamError ? @{NSLocalizedDescriptionKey: description,
                                                   NSUnderlyingErrorKey: streamError} : @{NSLocalizedDescriptionKey: description}];
            [self _failWithError:error];
            return;
        }

        _outputBufferOffset += bytesWritten;

        if (_outputBufferOffset > ZLDefaultBufferSize() && _outputBufferOffset > dataLength / 2) {
            _outputBuffer = dispatch_data_create_subrange(_outputBuffer, _outputBufferOffset, dataLength - _outputBufferOffset);
            _outputBufferOffset = 0;
        }
    }

    if (_closeWhenFinishedWriting &&
        (dispatch_data_get_size(_outputBuffer) - _outputBufferOffset) == 0 &&
        (_inputStream.streamStatus != NSStreamStatusNotOpen &&
         _inputStream.streamStatus != NSStreamStatusClosed) &&
        !_sentClose) {
        _sentClose = YES;

        @synchronized(self) {
            [_outputStream close];
            [_inputStream close];


            for (NSArray *runLoop in [_scheduledRunloops copy]) {
                [self unscheduleFromRunLoop:[runLoop objectAtIndex:0] forMode:[runLoop objectAtIndex:1]];
            }
        }

        if (!_failed) {
            [self performDelegateBlock:^(ZLWebSocket *webSocket) {
                if (webSocket.delegate && [webSocket.delegate respondsToSelector:@selector(webSocket:didCloseWithCode:reason:wasClean:)]) {
                    [webSocket.delegate webSocket:webSocket didCloseWithCode:webSocket->_closeCode reason:webSocket->_closeReason wasClean:YES];
                }
                
                if (webSocket->_closeCode == ZLStatusCodeGoingAway) {
                    [webSocket privateReconnect];
                }
            }];
        }

        [self _scheduleCleanup];
    }
}

- (void)_writeData:(NSData *)data {
    [self assertOnWorkQueue];

    if (_closeWhenFinishedWriting) {
        return;
    }

    __block NSData *strongData = data;
    dispatch_data_t newData = dispatch_data_create(data.bytes, data.length, nil, ^{
        strongData = nil;
    });
    _outputBuffer = dispatch_data_create_concat(_outputBuffer, newData);
    [self _pumpWriting];
}

static const char CRLFCRLFBytes[] = {'\r', '\n', '\r', '\n'};

- (void)_readUntilHeaderCompleteWithCallback:(data_callback)dataHandler {
    [self _readUntilBytes:CRLFCRLFBytes length:sizeof(CRLFCRLFBytes) callback:dataHandler];
}

- (void)_readUntilBytes:(const void *)bytes length:(size_t)length callback:(data_callback)dataHandler {
    // TODO optimize so this can continue from where we last searched
    stream_scanner consumer = ^size_t(NSData *data) {
        __block size_t found_size = 0;
        __block size_t match_count = 0;

        size_t size = data.length;
        const unsigned char *buffer = data.bytes;
        for (size_t i = 0; i < size; i++) {
            if (((const unsigned char *)buffer)[i] == ((const unsigned char *)bytes)[match_count]) {
                match_count += 1;
                if (match_count == length) {
                    found_size = i + 1;
                    break;
                }
            } else {
                match_count = 0;
            }
        }
        return found_size;
    };
    [self _addConsumerWithScanner:consumer callback:dataHandler];
}

- (void)_addConsumerWithScanner:(stream_scanner)consumer callback:(data_callback)callback {
    [self assertOnWorkQueue];
    [self _addConsumerWithScanner:consumer callback:callback dataLength:0];
}

- (void)_addConsumerWithDataLength:(size_t)dataLength callback:(data_callback)callback readToCurrentFrame:(BOOL)readToCurrentFrame unmaskBytes:(BOOL)unmaskBytes {
    [self assertOnWorkQueue];
    assert(dataLength);

    [_consumers addObject:[_consumerPool consumerWithScanner:nil handler:callback bytesNeeded:dataLength readToCurrentFrame:readToCurrentFrame unmaskBytes:unmaskBytes]];
    [self _pumpScanner];
}

- (void)_addConsumerWithScanner:(stream_scanner)consumer callback:(data_callback)callback dataLength:(size_t)dataLength {
    [self assertOnWorkQueue];
    [_consumers addObject:[_consumerPool consumerWithScanner:consumer handler:callback bytesNeeded:dataLength readToCurrentFrame:NO unmaskBytes:NO]];
    [self _pumpScanner];
}

// Returns true if did work
- (BOOL)_innerPumpScanner {
    BOOL didWork = NO;

    if (self.readyState >= ZL_CLOSED) {
        return didWork;
    }

    size_t readBufferSize = dispatch_data_get_size(_readBuffer);

    if (!_consumers.count) {
        return didWork;
    }

    size_t curSize = readBufferSize - _readBufferOffset;
    if (!curSize) {
        return didWork;
    }

    ZLIOConsumer *consumer = [_consumers objectAtIndex:0];

    size_t bytesNeeded = consumer.bytesNeeded;

    size_t foundSize = 0;
    if (consumer.consumer) {
        NSData *subdata = (NSData *)dispatch_data_create_subrange(_readBuffer, _readBufferOffset, readBufferSize - _readBufferOffset);
        foundSize = consumer.consumer(subdata);
    } else {
        assert(consumer.bytesNeeded);
        if (curSize >= bytesNeeded) {
            foundSize = bytesNeeded;
        } else if (consumer.readToCurrentFrame) {
            foundSize = curSize;
        }
    }

    if (consumer.readToCurrentFrame || foundSize) {
        dispatch_data_t slice = dispatch_data_create_subrange(_readBuffer, _readBufferOffset, foundSize);

        _readBufferOffset += foundSize;

        if (_readBufferOffset > ZLDefaultBufferSize() && _readBufferOffset > readBufferSize / 2) {
            _readBuffer = dispatch_data_create_subrange(_readBuffer, _readBufferOffset, readBufferSize - _readBufferOffset);
            _readBufferOffset = 0;
        }

        if (consumer.unmaskBytes) {
            __block NSMutableData *mutableSlice = [slice mutableCopy];

            NSUInteger len = mutableSlice.length;
            uint8_t *bytes = mutableSlice.mutableBytes;

            for (NSUInteger i = 0; i < len; i++) {
                bytes[i] = bytes[i] ^ _currentReadMaskKey[_currentReadMaskOffset % sizeof(_currentReadMaskKey)];
                _currentReadMaskOffset += 1;
            }

            slice = dispatch_data_create(bytes, len, nil, ^{
                mutableSlice = nil;
            });
        }

        if (consumer.readToCurrentFrame) {
            dispatch_data_apply(slice, ^bool(dispatch_data_t region, size_t offset, const void *buffer, size_t size) {
                [_currentFrameData appendBytes:buffer length:size];
                return true;
            });

            _readOpCount += 1;

            if (_currentFrameOpcode == ZLOpCodeTextFrame) {
                // Validate UTF8 stuff.
                size_t currentDataSize = _currentFrameData.length;
                if (_currentFrameOpcode == ZLOpCodeTextFrame && currentDataSize > 0) {
                    // TODO: Optimize the crap out of this.  Don't really have to copy all the data each time

                    size_t scanSize = currentDataSize - _currentStringScanPosition;

                    NSData *scan_data = [_currentFrameData subdataWithRange:NSMakeRange(_currentStringScanPosition, scanSize)];
                    int32_t valid_utf8_size = validate_dispatch_data_partial_string(scan_data);

                    if (valid_utf8_size == -1) {
                        [self closeWithCode:ZLStatusCodeInvalidUTF8 reason:@"Text frames must be valid UTF-8"];
                        dispatch_async(_workQueue, ^{
                            [self closeConnection];
                        });
                        return didWork;
                    } else {
                        _currentStringScanPosition += valid_utf8_size;
                    }
                }

            }

            consumer.bytesNeeded -= foundSize;

            if (consumer.bytesNeeded == 0) {
                [_consumers removeObjectAtIndex:0];
                consumer.handler(self, nil);
                [_consumerPool returnConsumer:consumer];
                didWork = YES;
            }
        } else if (foundSize) {
            [_consumers removeObjectAtIndex:0];
            consumer.handler(self, (NSData *)slice);
            [_consumerPool returnConsumer:consumer];
            didWork = YES;
        }
    }
    return didWork;
}


- (void)_pumpScanner {
    [self assertOnWorkQueue];

    if (!_isPumping) {
        _isPumping = YES;
    } else {
        return;
    }

    while ([self _innerPumpScanner]) {

    }

    _isPumping = NO;
}

- (void)_handleFrameWithData:(NSData *)frameData opCode:(ZLOpCode)opcode {
    // Check that the current data is valid UTF8

    BOOL isControlFrame = (opcode == ZLOpCodePing || opcode == ZLOpCodePong || opcode == ZLOpCodeConnectionClose);
    if (isControlFrame) {
        //frameData will be copied before passing to handlers
        //otherwise there can be misbehaviours when value at the pointer is changed
        frameData = [frameData copy];

        dispatch_async(_workQueue, ^{
            [self _readFrameContinue];
        });
    } else {
        [self _readFrameNew];
    }

    switch (opcode) {
        case ZLOpCodeTextFrame: {
            NSString *string = [[NSString alloc] initWithData:frameData encoding:NSUTF8StringEncoding];
            if (!string && frameData) {
                [self closeWithCode:ZLStatusCodeInvalidUTF8 reason:@"Text frames must be valid UTF-8."];
                dispatch_async(_workQueue, ^{
                    [self closeConnection];
                });
                return;
            }
            [self performDelegateBlock:^(ZLWebSocket *webSocket) {
                if (webSocket.delegate && [webSocket.delegate respondsToSelector:@selector(webSocket:didReceiveMessageWithString:)]) {
                    [webSocket.delegate webSocket:webSocket didReceiveMessageWithString:string];
                }
            }];
            break;
        }
        case ZLOpCodeBinaryFrame: {
            [self performDelegateBlock:^(ZLWebSocket *webSocket) {
                if (webSocket.delegate && [webSocket.delegate respondsToSelector:@selector(webSocket:didReceiveMessageWithData:)]) {
                    [webSocket.delegate webSocket:webSocket didReceiveMessageWithData:frameData];
                }
            }];
        }
            break;
        case ZLOpCodeConnectionClose:
            [self handleCloseWithData:frameData];
            break;
        case ZLOpCodePing:
            [self _handlePingWithData:frameData];
            break;
        case ZLOpCodePong:
            [self handlePong:frameData];
            break;
        default:
            [self _closeWithProtocolError:[NSString stringWithFormat:@"Unknown opcode %ld", (long)opcode]];
            // TODO: Handle invalid opcode
            break;
    }
}

- (void)performDelegateBlock:(void (^)(ZLWebSocket *webSocket))block {
    __weak typeof(self) weakSelf = self;
    dispatch_async(_dispatchQueue, ^{
        __strong typeof(weakSelf) strongSelf = self;
        if (strongSelf == nil) {
            return;
        }
        block(strongSelf);
    });
}

- (void)_handlePingWithData:(nullable NSData *)data {
    // Need to pingpong this off _callbackQueue first to make sure messages happen in order
    [self performDelegateBlock:^(ZLWebSocket *webSocket) {
        if (webSocket.delegate && [webSocket.delegate respondsToSelector:@selector(webSocket:didReceivePingWithData:)]) {
            [webSocket.delegate webSocket:webSocket didReceivePingWithData:data];
        }
        dispatch_async(webSocket->_workQueue, ^{
            [webSocket _sendFrameWithOpcode:ZLOpCodePong data:data];
        });
    }];
}

- (void)handlePong:(NSData *)pongData {
    _awaitingPong = NO;
    [self performDelegateBlock:^(ZLWebSocket *webSocket) {
        if (webSocket.delegate && [webSocket.delegate respondsToSelector:@selector(webSocket:didReceivePong:)]) {
            [webSocket.delegate webSocket:webSocket didReceivePong:pongData];
        }
    }];
}


static const size_t ZLFrameHeaderOverhead = 32;

- (void)_sendFrameWithOpcode:(ZLOpCode)opCode data:(NSData *)data {
    [self assertOnWorkQueue];

    if (!data) {
        return;
    }

    size_t payloadLength = data.length;

    NSMutableData *frameData = [[NSMutableData alloc] initWithLength:payloadLength + ZLFrameHeaderOverhead];
    if (!frameData) {
        [self closeWithCode:ZLStatusCodeMessageTooBig reason:@"Message too big"];
        return;
    }
    uint8_t *frameBuffer = (uint8_t *)frameData.mutableBytes;

    // set fin
    frameBuffer[0] = SRFinMask | opCode;

    // set the mask and header
    frameBuffer[1] |= SRMaskMask;

    size_t frameBufferSize = 2;

    if (payloadLength < 126) {
        frameBuffer[1] |= payloadLength;
    } else {
        uint64_t declaredPayloadLength = 0;
        size_t declaredPayloadLengthSize = 0;

        if (payloadLength <= UINT16_MAX) {
            frameBuffer[1] |= 126;

            declaredPayloadLength = CFSwapInt16BigToHost((uint16_t)payloadLength);
            declaredPayloadLengthSize = sizeof(uint16_t);
        } else {
            frameBuffer[1] |= 127;

            declaredPayloadLength = CFSwapInt64BigToHost((uint64_t)payloadLength);
            declaredPayloadLengthSize = sizeof(uint64_t);
        }

        memcpy((frameBuffer + frameBufferSize), &declaredPayloadLength, declaredPayloadLengthSize);
        frameBufferSize += declaredPayloadLengthSize;
    }

    const uint8_t *unmaskedPayloadBuffer = (uint8_t *)data.bytes;
    uint8_t *maskKey = frameBuffer + frameBufferSize;

    size_t randomBytesSize = sizeof(uint32_t);
    int result = SecRandomCopyBytes(kSecRandomDefault, randomBytesSize, maskKey);
    if (result != 0) {
        //TODO: (nlutsenko) Check if there was an error.
    }
    frameBufferSize += randomBytesSize;

    // Copy and unmask the buffer
    uint8_t *frameBufferPayloadPointer = frameBuffer + frameBufferSize;

    memcpy(frameBufferPayloadPointer, unmaskedPayloadBuffer, payloadLength);
    ZLMaskBytesSIMD(frameBufferPayloadPointer, payloadLength, maskKey);
    frameBufferSize += payloadLength;

    assert(frameBufferSize <= frameData.length);
    frameData.length = frameBufferSize;

    [self _writeData:frameData];
}

static inline BOOL closeCodeIsValid(int closeCode) {
    if (closeCode < 1000) {
        return NO;
    }

    if (closeCode >= 1000 && closeCode <= 1011) {
        if (closeCode == 1004 ||
            closeCode == 1005 ||
            closeCode == 1006) {
            return NO;
        }
        return YES;
    }

    if (closeCode >= 3000 && closeCode <= 3999) {
        return YES;
    }

    if (closeCode >= 4000 && closeCode <= 4999) {
        return YES;
    }

    return NO;
}
//  Note from RFC:
//
//  If there is a body, the first two
//  bytes of the body MUST be a 2-byte unsigned integer (in network byte
//  order) representing a status code with value /code/ defined in
//  Section 7.4.  Following the 2-byte integer the body MAY contain UTF-8
//  encoded data with value /reason/, the interpretation of which is not
//  defined by this specification.

- (void)handleCloseWithData:(NSData *)data {
    size_t dataSize = data.length;
    __block uint16_t closeCode = 0;

    if (dataSize == 1) {
        // TODO handle error
        [self _closeWithProtocolError:@"Payload for close must be larger than 2 bytes"];
        return;
    } else if (dataSize >= 2) {
        [data getBytes:&closeCode length:sizeof(closeCode)];
        _closeCode = CFSwapInt16BigToHost(closeCode);
        if (!closeCodeIsValid(_closeCode)) {
            [self _closeWithProtocolError:[NSString stringWithFormat:@"Cannot have close code of %d", _closeCode]];
            return;
        }
        if (dataSize > 2) {
            _closeReason = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(2, dataSize - 2)] encoding:NSUTF8StringEncoding];
            if (!_closeReason) {
                [self _closeWithProtocolError:@"Close reason MUST be valid UTF-8"];
                return;
            }
        }
    } else {
        _closeCode = ZLStatusNoStatusReceived;
    }

    [self assertOnWorkQueue];

    if (self.readyState == ZL_OPEN) {
        [self closeWithCode:1000 reason:nil];
    }
    dispatch_async(_workQueue, ^{
        [self closeConnection];
    });
}

- (void)_handleFrameHeader:(frame_header)frame_header curData:(NSData *)curData {
    assert(frame_header.opcode != 0);

    if (self.readyState == ZL_CLOSED) {
        return;
    }


    BOOL isControlFrame = (frame_header.opcode == ZLOpCodePing || frame_header.opcode == ZLOpCodePong || frame_header.opcode == ZLOpCodeConnectionClose);

    if (isControlFrame && !frame_header.fin) {
        [self _closeWithProtocolError:@"Fragmented control frames not allowed"];
        return;
    }

    if (isControlFrame && frame_header.payload_length >= 126) {
        [self _closeWithProtocolError:@"Control frames cannot have payloads larger than 126 bytes"];
        return;
    }

    if (!isControlFrame) {
        _currentFrameOpcode = frame_header.opcode;
        _currentFrameCount += 1;
    }

    if (frame_header.payload_length == 0) {
        if (isControlFrame) {
            [self _handleFrameWithData:curData opCode:frame_header.opcode];
        } else {
            if (frame_header.fin) {
                [self _handleFrameWithData:_currentFrameData opCode:frame_header.opcode];
            } else {
                // TODO add assert that opcode is not a control;
                [self _readFrameContinue];
            }
        }
    } else {
        assert(frame_header.payload_length <= SIZE_T_MAX);
        [self _addConsumerWithDataLength:(size_t)frame_header.payload_length callback:^(ZLWebSocket *sself, NSData *newData) {
            if (isControlFrame) {
                [sself _handleFrameWithData:newData opCode:frame_header.opcode];
            } else {
                if (frame_header.fin) {
                    [sself _handleFrameWithData:sself->_currentFrameData opCode:frame_header.opcode];
                } else {
                    // TODO add assert that opcode is not a control;
                    [sself _readFrameContinue];
                }
            }
        } readToCurrentFrame:!isControlFrame unmaskBytes:frame_header.masked];
    }
}
/* From RFC:

 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
 +-+-+-+-+-------+-+-------------+-------------------------------+
 |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
 |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
 |N|V|V|V|       |S|             |   (if payload len==126/127)   |
 | |1|2|3|       |K|             |                               |
 +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
 |     Extended payload length continued, if payload len == 127  |
 + - - - - - - - - - - - - - - - +-------------------------------+
 |                               |Masking-key, if MASK set to 1  |
 +-------------------------------+-------------------------------+
 | Masking-key (continued)       |          Payload Data         |
 +-------------------------------- - - - - - - - - - - - - - - - +
 :                     Payload Data continued ...                :
 + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
 |                     Payload Data continued ...                |
 +---------------------------------------------------------------+
 */

static const uint8_t SRFinMask          = 0x80;
static const uint8_t SROpCodeMask       = 0x0F;
static const uint8_t SRRsvMask          = 0x70;
static const uint8_t SRMaskMask         = 0x80;
static const uint8_t SRPayloadLenMask   = 0x7F;

- (void)_closeWithProtocolError:(NSString *)message {
    // Need to shunt this on the _callbackQueue first to see if they received any messages
    __weak typeof(self) weakSelf = self;
    dispatch_async(_dispatchQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        [strongSelf closeWithCode:ZLStatusCodeProtocolError reason:message];
        dispatch_async(strongSelf->_workQueue, ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            [strongSelf closeConnection];
        });
    });
}

- (void)_readFrameContinue {
    assert((_currentFrameCount == 0 && _currentFrameOpcode == 0) || (_currentFrameCount > 0 && _currentFrameOpcode > 0));

    [self _addConsumerWithDataLength:2 callback:^(ZLWebSocket *sself, NSData *data) {
        __block frame_header header = {0};

        const uint8_t *headerBuffer = data.bytes;
        assert(data.length >= 2);

        if (headerBuffer[0] & SRRsvMask) {
            [sself _closeWithProtocolError:@"Server used RSV bits"];
            return;
        }

        uint8_t receivedOpcode = (SROpCodeMask & headerBuffer[0]);

        BOOL isControlFrame = (receivedOpcode == ZLOpCodePing || receivedOpcode == ZLOpCodePong || receivedOpcode == ZLOpCodeConnectionClose);

        if (!isControlFrame && receivedOpcode != 0 && sself->_currentFrameCount > 0) {
            [sself _closeWithProtocolError:@"all data frames after the initial data frame must have opcode 0"];
            return;
        }

        if (receivedOpcode == 0 && sself->_currentFrameCount == 0) {
            [sself _closeWithProtocolError:@"cannot continue a message"];
            return;
        }

        header.opcode = receivedOpcode == 0 ? sself->_currentFrameOpcode : receivedOpcode;

        header.fin = !!(SRFinMask & headerBuffer[0]);


        header.masked = !!(SRMaskMask & headerBuffer[1]);
        header.payload_length = SRPayloadLenMask & headerBuffer[1];

        headerBuffer = NULL;

        if (header.masked) {
            [sself _closeWithProtocolError:@"Client must receive unmasked data"];
            return;
        }

        size_t extra_bytes_needed = header.masked ? sizeof(sself->_currentReadMaskKey) : 0;

        if (header.payload_length == 126) {
            extra_bytes_needed += sizeof(uint16_t);
        } else if (header.payload_length == 127) {
            extra_bytes_needed += sizeof(uint64_t);
        }

        if (extra_bytes_needed == 0) {
            [sself _handleFrameHeader:header curData:sself->_currentFrameData];
        } else {
            [sself _addConsumerWithDataLength:extra_bytes_needed callback:^(ZLWebSocket *eself, NSData *edata) {
                size_t mapped_size = edata.length;
#pragma unused (mapped_size)
                const void *mapped_buffer = edata.bytes;
                size_t offset = 0;

                if (header.payload_length == 126) {
                    assert(mapped_size >= sizeof(uint16_t));
                    uint16_t payloadLength = 0;
                    memcpy(&payloadLength, mapped_buffer, sizeof(uint16_t));
                    payloadLength = CFSwapInt16BigToHost(payloadLength);

                    header.payload_length = payloadLength;
                    offset += sizeof(uint16_t);
                } else if (header.payload_length == 127) {
                    assert(mapped_size >= sizeof(uint64_t));
                    uint64_t payloadLength = 0;
                    memcpy(&payloadLength, mapped_buffer, sizeof(uint64_t));
                    payloadLength = CFSwapInt64BigToHost(payloadLength);

                    header.payload_length = payloadLength;
                    offset += sizeof(uint64_t);
                } else {
                    assert(header.payload_length < 126 && header.payload_length >= 0);
                }

                if (header.masked) {
                    assert(mapped_size >= sizeof(eself->_currentReadMaskOffset) + offset);
                    memcpy(eself->_currentReadMaskKey, ((uint8_t *)mapped_buffer) + offset, sizeof(eself->_currentReadMaskKey));
                }

                [eself _handleFrameHeader:header curData:eself->_currentFrameData];
            } readToCurrentFrame:NO unmaskBytes:NO];
        }
    } readToCurrentFrame:NO unmaskBytes:NO];
}

- (void)_readFrameNew {
    dispatch_async(_workQueue, ^{
        // Don't reset the length, since Apple doesn't guarantee that this will free the memory (and in tests on
        // some platforms, it doesn't seem to, effectively causing a leak the size of the biggest frame so far).
        self->_currentFrameData = [[NSMutableData alloc] init];

        self->_currentFrameOpcode = 0;
        self->_currentFrameCount = 0;
        self->_readOpCount = 0;
        self->_currentStringScanPosition = 0;

        [self _readFrameContinue];
    });
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    __weak typeof(self) wself = self;

    if (_requestRequiresSSL && !_streamSecurityValidated &&
        (eventCode == NSStreamEventHasBytesAvailable || eventCode == NSStreamEventHasSpaceAvailable)) {
        SecTrustRef trust = (__bridge SecTrustRef)[aStream propertyForKey:(__bridge id)kCFStreamPropertySSLPeerTrust];
        if (trust) {
            _streamSecurityValidated = [_securityPolicy evaluateServerTrust:trust forDomain:_urlRequest.URL.host];
        }
        if (!_streamSecurityValidated) {
            dispatch_async(_workQueue, ^{
                NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorClientCertificateRejected userInfo:@{NSLocalizedDescriptionKey: @"Invalid server certificate."}];
                [wself _failWithError:error];
            });
            return;
        }
        dispatch_async(_workQueue, ^{
            [self didConnect];
        });
    }
    dispatch_async(_workQueue, ^{
        [wself safeHandleEvent:eventCode stream:aStream];
    });
}

- (void)safeHandleEvent:(NSStreamEvent)eventCode stream:(NSStream *)aStream {
    switch (eventCode) {
        case NSStreamEventOpenCompleted: {
            if (self.readyState >= ZL_CLOSING) {
                return;
            }
            assert(_readBuffer);

            if (!_requestRequiresSSL && self.readyState == ZL_CONNECTING && aStream == _inputStream) {
                [self didConnect];
            }

            [self _pumpWriting];
            [self _pumpScanner];

            break;
        }

        case NSStreamEventErrorOccurred: {
            /// TODO specify error better!
            [self _failWithError:aStream.streamError];
            _readBufferOffset = 0;
            _readBuffer = dispatch_data_empty;
            break;

        }

        case NSStreamEventEndEncountered: {
            [self _pumpScanner];
            if (aStream.streamError) {
                [self _failWithError:aStream.streamError];
            } else {
                dispatch_async(_workQueue, ^{
                    if (self.readyState != ZL_CLOSED) {
                        self.readyState = ZL_CLOSED;
                        [self _scheduleCleanup];
                    }

                    if (!self->_sentClose && !self->_failed) {
                        self->_sentClose = YES;
                        // If we get closed in this state it's probably not clean because we should be sending this when we send messages
                        [self performDelegateBlock:^(ZLWebSocket *webSocket) {
                            [webSocket pausePingTimer];
                            
                            if (webSocket.delegate && [webSocket.delegate respondsToSelector:@selector(webSocket:didCloseWithCode:reason:wasClean:)]) {
                                [webSocket.delegate webSocket:webSocket
                                   didCloseWithCode:ZLStatusCodeGoingAway
                                             reason:@"Stream end encountered"
                                           wasClean:NO];
                            }
                            
                            [webSocket privateReconnect];
                        }];
                    }
                });
            }

            break;
        }

        case NSStreamEventHasBytesAvailable: {
            uint8_t buffer[ZLDefaultBufferSize()];

            while (_inputStream.hasBytesAvailable) {
                NSInteger bytesRead = [_inputStream read:buffer maxLength:ZLDefaultBufferSize()];
                if (bytesRead > 0) {
                    dispatch_data_t data = dispatch_data_create(buffer, bytesRead, nil, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
                    if (!data) {
                        NSError *error = [NSError errorWithDomain:ZLWebSocketErrorDomain code:ZLStatusCodeMessageTooBig userInfo:@{ NSLocalizedDescriptionKey: @"Unable to allocate memory to read from socket."}];
                        [self _failWithError:error];
                        return;
                    }
                    _readBuffer = dispatch_data_create_concat(_readBuffer, data);
                } else if (bytesRead == -1) {
                    [self _failWithError:_inputStream.streamError];
                }
            }
            [self _pumpScanner];
            break;
        }

        case NSStreamEventHasSpaceAvailable: {
            [self _pumpWriting];
            break;
        }

        case NSStreamEventNone:
            break;
    }
}

@end
