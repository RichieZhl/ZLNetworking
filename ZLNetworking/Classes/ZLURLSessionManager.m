//
//  ZLURLSessionManager.m
//  ZLNetworking_Example
//
//  Created by lylaut on 2021/9/30.
//  Copyright © 2021 richiezhl. All rights reserved.
//

#import "ZLURLSessionManager.h"
#import "ZLXMLDictionary.h"
#import <sys/sysctl.h>
#import <CoreServices/CoreServices.h>
#import <CommonCrypto/CommonDigest.h>

static inline unsigned int countOfCores(void) {
    unsigned int ncpu;
    size_t len = sizeof(ncpu);
    sysctlbyname("hw.ncpu", &ncpu, &len, NULL, 0);
    
    return ncpu;
}

static NSString * ZLCreateMultipartFormBoundary() {
    return [NSString stringWithFormat:@"Boundary+%08X%08X", arc4random(), arc4random()];
}

static NSString * const kZLMultipartFormCRLF = @"\r\n";

/**
 Returns a percent-escaped string following RFC 3986 for a query string key or value.
 RFC 3986 states that the following characters are "reserved" characters.
    - General Delimiters: ":", "#", "[", "]", "@", "?", "/"
    - Sub-Delimiters: "!", "$", "&", "'", "(", ")", "*", "+", ",", ";", "="

 In RFC 3986 - Section 3.4, it states that the "?" and "/" characters should not be escaped to allow
 query strings to include a URL. Therefore, all "reserved" characters with the exception of "?" and "/"
 should be percent-escaped in the query string.
    - parameter string: The string to be percent-escaped.
    - returns: The percent-escaped string.
 */
static NSString * ZLPercentEscapedStringFromString(NSString *string) {
    static NSString * const kAFCharactersGeneralDelimitersToEncode = @":#[]@"; // does not include "?" or "/" due to RFC 3986 - Section 3.4
    static NSString * const kAFCharactersSubDelimitersToEncode = @"!$&'()*+,;=";

    NSMutableCharacterSet * allowedCharacterSet = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    [allowedCharacterSet removeCharactersInString:[kAFCharactersGeneralDelimitersToEncode stringByAppendingString:kAFCharactersSubDelimitersToEncode]];

    // FIXME: https://github.com/AFNetworking/AFNetworking/pull/3028
    // return [string stringByAddingPercentEncodingWithAllowedCharacters:allowedCharacterSet];

    static NSUInteger const batchSize = 50;

    NSUInteger index = 0;
    NSMutableString *escaped = @"".mutableCopy;

    while (index < string.length) {
        NSUInteger length = MIN(string.length - index, batchSize);
        NSRange range = NSMakeRange(index, length);

        // To avoid breaking up character sequences such as 👴🏻👮🏽
        range = [string rangeOfComposedCharacterSequencesForRange:range];

        NSString *substring = [string substringWithRange:range];
        NSString *encoded = [substring stringByAddingPercentEncodingWithAllowedCharacters:allowedCharacterSet];
        [escaped appendString:encoded];

        index += range.length;
    }

    return escaped;
}

static inline NSString * ZLContentTypeForPathExtension(NSString *extension) {
    NSString *UTI = (__bridge_transfer NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)extension, NULL);
    NSString *contentType = (__bridge_transfer NSString *)UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)UTI, kUTTagClassMIMEType);
    if (!contentType) {
        return @"application/octet-stream";
    } else {
        return contentType;
    }
}

NSString *ZLSha256HashFor(NSString *input) {
    const char *str = [input UTF8String];
    unsigned char result[CC_SHA256_DIGEST_LENGTH + 1];
    CC_SHA256(str, (CC_LONG)strlen(str), result);
    
    NSMutableString *ret = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [ret appendFormat:@"%02x", result[i]];
    }

    return ret;
}

static id ZLParseResponseBody(ZLResponseBodyType type, NSData *data) {
    if (type == ZLResponseBodyTypeJson) {
        NSError *error = nil;
        id result = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableLeaves error:&error];
        if (error) {
            NSLog(@"%@", error);
            return data;
        }
        return result;
    } else if (type == ZLResponseBodyTypeXml) {
        NSDictionary *result = [NSDictionary dictionaryWithXMLData:data];
        if ([result isKindOfClass:[NSDictionary class]]) {
            return result;
        }
        
        return data;
    }
    
    return data;
}


@interface ZLMultipartFormDataItem : NSObject

@property (nonatomic, strong) NSURL *url;

@property (nonatomic, strong) NSData *data;

@property (nonatomic, copy) NSString *filename;

@property (nonatomic, copy) NSString *name;

@property (nonatomic, copy) NSString *mimetype;

- (instancetype)initWithURL:(NSURL *)url
                   filename:(NSString *)filename
                       name:(NSString *)name
                   mimetype:(NSString *)mimetype;

- (instancetype)initWithData:(NSData *)data
                   filename:(NSString *)filename
                       name:(NSString *)name
                   mimetype:(NSString *)mimetype;

@end

@implementation ZLMultipartFormDataItem

- (instancetype)initWithURL:(NSURL *)url
                   filename:(NSString *)filename
                       name:(NSString *)name
                   mimetype:(NSString *)mimetype {
    if (self = [super init]) {
        NSParameterAssert(url);
        NSParameterAssert(name);
        
        self.url = url;
        self.name = name;
        
        if (filename == nil || filename.length == 0) {
            self.filename = url.lastPathComponent;
        } else {
            self.filename = filename;
        }
        
        if (mimetype == nil || mimetype.length == 0) {
            self.mimetype = ZLContentTypeForPathExtension([url pathExtension]);
        } else {
            self.mimetype = mimetype;
        }
    }
    return self;
}

- (instancetype)initWithData:(NSData *)data
                   filename:(NSString *)filename
                       name:(NSString *)name
                   mimetype:(NSString *)mimetype {
    if (self = [super init]) {
        NSParameterAssert(data);
        NSParameterAssert(name);
        
        self.data = data;
        self.name = name;
        
        if (filename == nil || filename.length == 0) {
            self.filename = [NSString stringWithFormat:@"iOS_%08X%lX", arc4random(), (long)([[NSDate date] timeIntervalSince1970] * 1000)];
        } else {
            self.filename = filename;
        }
        
        if (mimetype == nil || mimetype.length == 0) {
            self.mimetype = @"application/octet-stream";
        } else {
            self.mimetype = mimetype;
        }
    }
    return self;
}

- (NSData *)data {
    if (_data == nil) {
        _data = [NSData dataWithContentsOfURL:self.url];
    }
    return _data;
}

@end


@interface ZLMultipartFormData ()

@property (nonatomic, strong) NSMutableData *data;

@property (nonatomic, strong) NSString *boundary;

- (void)finalData;

@end

@implementation ZLMultipartFormData

- (instancetype)init {
    if (self = [super init]) {
        _data = [NSMutableData data];
    }
    return self;
}

- (void)finalData {
    NSString *finalStr = [self.boundary stringByAppendingFormat:@"--%@", kZLMultipartFormCRLF];
    [self.data appendData:[finalStr dataUsingEncoding:NSUTF8StringEncoding]];
}

- (BOOL)appendItem:(ZLMultipartFormDataItem *)item {
    NSData *data = item.data;
    if (data == nil || data.length == 0) {
        return NO;
    }
    
    NSString *headerStr = [self.boundary stringByAppendingFormat:@"%@Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"%@Content-Type: %@%@%@", kZLMultipartFormCRLF, item.name, item.filename, kZLMultipartFormCRLF, item.mimetype, kZLMultipartFormCRLF, kZLMultipartFormCRLF];
    [self.data appendData:[headerStr dataUsingEncoding:NSUTF8StringEncoding]];
    [self.data appendData:data];
    [self.data appendData:[kZLMultipartFormCRLF dataUsingEncoding:NSUTF8StringEncoding]];
    return YES;
}

- (BOOL)appendPartWithFileURL:(NSURL *)fileURL
                         name:(NSString *)name {
    ZLMultipartFormDataItem *item = [[ZLMultipartFormDataItem alloc] initWithURL:fileURL filename:nil name:name mimetype:nil];
    return [self appendItem:item];
}

- (BOOL)appendPartWithFileURL:(NSURL *)fileURL
                         name:(NSString *)name
                     fileName:(NSString *)fileName
                     mimeType:(NSString *)mimeType {
    ZLMultipartFormDataItem *item = [[ZLMultipartFormDataItem alloc] initWithURL:fileURL filename:fileName name:name mimetype:mimeType];
    return [self appendItem:item];
}

- (void)appendPartWithFileData:(NSData *)data
                          name:(NSString *)name
                      fileName:(NSString *)fileName
                      mimeType:(NSString *)mimeType {
    ZLMultipartFormDataItem *item = [[ZLMultipartFormDataItem alloc] initWithData:data filename:fileName name:name mimetype:mimeType];
    [self appendItem:item];
}

@end

@interface ZLDownloadOperation : NSOperation <NSURLSessionDataDelegate> {
    BOOL _isCancelled;
    BOOL _isExecuting;
    BOOL _isFinished;
    unsigned long contentLength;
    unsigned long receivedLength;
}

@property (nonatomic, strong) NSMutableDictionary<NSURL *, ZLDownloadOperation *> *mainDownloadItems;

@property (nonatomic, strong) NSURLSession *urlSession;

@property (nonatomic, strong) NSMutableURLRequest *urlRequest;

@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *headers;

@property (nonatomic, strong) NSURLResponse *response;

@property (nonatomic, copy) NSString *filePath;

@property (nonatomic, strong) NSURL *destinationURL;

@property (nonatomic, strong) NSFileHandle *fileHandle;

@property (nonatomic, copy) void (^downloadProgressBlock)(float downloadProgress);

@property (nonatomic, copy) void (^completionHandler)(NSURLResponse *response, NSURL *filePath, NSError *error);

@end

@implementation ZLDownloadOperation

- (BOOL)isCancelled {
    return _isCancelled;
}

- (BOOL)isFinished {
    return _isFinished;
}

- (BOOL)isExecuting {
    return _isExecuting;
}

- (void)cancel {
    [super cancel];
    
    [self willChangeValueForKey:@"cancelled"];
    _isCancelled = YES;
    [self didChangeValueForKey:@"cancelled"];
}

- (void)main {
    if (self.isCancelled) {
        [self handleCancelAction];
        return;
    }
    
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = 1;
        
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.HTTPShouldSetCookies = YES;
    configuration.HTTPShouldUsePipelining = NO;
    
    configuration.timeoutIntervalForRequest = 3600;
    configuration.allowsCellularAccess = YES;
    
    self.urlRequest.timeoutInterval = 3600;
    
    self.urlSession = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:queue];
    
    if (self.headers != nil) {
        for (NSString *headerField in self.headers.keyEnumerator) {
            [self.urlRequest setValue:self.headers[headerField] forHTTPHeaderField:headerField];
        }
    }
    
    NSString *downloadTemp = [[ZLURLSessionManager shared].workspaceDirURLString stringByAppendingPathComponent:@"temp"];
    NSString *fileName = ZLSha256HashFor(self.urlRequest.URL.absoluteString);
    self.filePath = [downloadTemp stringByAppendingPathComponent:fileName];
    
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:downloadTemp isDirectory:&isDir] || !isDir) {
        if (![[NSFileManager defaultManager] createDirectoryAtPath:downloadTemp withIntermediateDirectories:YES attributes:nil error:nil]) {
            NSLog(@"file system error");
        }
    }
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.filePath isDirectory:&isDir] && !isDir) {
        NSDictionary *fileDic = [[NSFileManager defaultManager] attributesOfItemAtPath:self.filePath error:nil];//获取文件的属性
        unsigned long size = [[fileDic objectForKey:NSFileSize] longLongValue];
        NSString *range = [NSString stringWithFormat:@"bytes=%ld-", size];
        [self.urlRequest setValue:range forHTTPHeaderField:@"Range"];
        receivedLength = size;
    } else {
        [[NSFileManager defaultManager] createFileAtPath:self.filePath contents:[NSData data] attributes:nil];
        receivedLength = 0;
    }
    
    if (self.isCancelled) {
        [self handleCancelAction];
        return;
    }
    
    NSURLSessionDataTask *task = [self.urlSession dataTaskWithRequest:self.urlRequest];
    [task resume];
    [self.urlSession finishTasksAndInvalidate];
    
    [self willChangeValueForKey:@"executing"];
    _isExecuting = YES;
    [self didChangeValueForKey:@"executing"];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
                                 didReceiveResponse:(NSURLResponse *)response
                                  completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    if (self.isCancelled) {
        completionHandler(NSURLSessionResponseCancel);
    } else {
        self.response = response;
        
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *rp = (NSHTTPURLResponse *)response;
            unsigned long remoteContentLength = (unsigned long)[rp.allHeaderFields[@"Content-Length"] longLongValue];
            contentLength = remoteContentLength + receivedLength;
            
            self.fileHandle = [NSFileHandle fileHandleForWritingAtPath:self.filePath];
            [self.fileHandle seekToEndOfFile];
        }
        
        completionHandler(NSURLSessionResponseAllow);
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    if (self.isCancelled) {
        [dataTask cancel];
        
        [self willChangeValueForKey:@"cancelled"];
        _isCancelled = YES;
        [self didChangeValueForKey:@"cancelled"];
        
        return;
    }
    
    [self.fileHandle writeData:data];
    receivedLength += data.length;
    
    if (self.downloadProgressBlock) {
        self.downloadProgressBlock(1.0 * receivedLength / contentLength);
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didCompleteWithError:(nullable NSError *)error {
    if (self.fileHandle != nil) {
        [self.fileHandle closeFile];
    }
    
    if (error) {
        if (error.code == NSURLErrorCancelled) {
            [self handleCancelAction];
        }
        
        if (self.completionHandler) {
            self.completionHandler(self.response, self.destinationURL, error);
        }
    } else {
        if (receivedLength >= contentLength) {
            NSError *error = nil;
            [[NSFileManager defaultManager] moveItemAtURL:[NSURL fileURLWithPath:self.filePath] toURL:self.destinationURL error:&error];
            
            if (self.completionHandler) {
                self.completionHandler(self.response, self.destinationURL, error);
            }
        } else {
            if (self.completionHandler) {
                self.completionHandler(self.response, self.destinationURL, [NSError errorWithDomain:@"FILE IO Error" code:NSURLErrorCannotMoveFile userInfo:nil]);
            }
        }
    }
    
    [self.mainDownloadItems removeObjectForKey:self.urlRequest.URL];
    
    [self willChangeValueForKey:@"executing"];
    _isExecuting = NO;
    [self didChangeValueForKey:@"executing"];
    
    [self willChangeValueForKey:@"finished"];
    _isFinished = YES;
    [self didChangeValueForKey:@"finished"];
}

- (void)handleCancelAction {
//    NSLog(@"%s", __FUNCTION__);
}

@end

@interface ZLURLSessionManager ()

@property (nonatomic, strong) NSURLSessionConfiguration *configuration;

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSURLSession *> *urlSessionCaches;

@property (nonatomic, strong) NSOperationQueue *responseQueue;

@property (nonatomic, strong) NSOperationQueue *downloadQueue;

@property (nonatomic, strong) NSMutableDictionary<NSURL *, ZLDownloadOperation *> *downloadItems;

@property (nonatomic, copy, readwrite) NSString *workspaceDirURLString;

@end

@implementation ZLURLSessionManager

+ (instancetype)shared {
    static ZLURLSessionManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [self new];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _timeoutIntervalForRequest = 10;
        _urlSessionCaches = [NSMutableDictionary dictionary];
        _responseQueue = [[NSOperationQueue alloc] init];
        _responseQueue.maxConcurrentOperationCount = countOfCores();
        _downloadQueue = [[NSOperationQueue alloc] init];
        _downloadQueue.maxConcurrentOperationCount = _responseQueue.maxConcurrentOperationCount;
        _reachablity = [ZHLReachability reachabilityWithHostName:@"www.apple.com"];
        _workspaceDirURLString = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"ZHLNetworking"];
        
        NSString *downloadTemp = [_workspaceDirURLString stringByAppendingPathComponent:@"temp"];
        
        BOOL isDir = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:downloadTemp isDirectory:&isDir] || !isDir) {
            if (![[NSFileManager defaultManager] createDirectoryAtPath:downloadTemp withIntermediateDirectories:YES attributes:nil error:nil]) {
                NSLog(@"file system error");
            }
        }
    }
    return self;
}

- (NSURLSessionConfiguration *)configuration {
    if (_configuration == nil) {
        @synchronized (self) {
            if (_configuration == nil) {
                _configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
                _configuration.timeoutIntervalForResource = 10;
                
                _configuration.allowsCellularAccess = YES;
                
                if (@available(iOS 11.0, *)) {
                    _configuration.waitsForConnectivity = YES;
                } else {
                    // Fallback on earlier versions
                }
            }
        }
    }
    
    _configuration.connectionProxyDictionary = self.connectionProxyDictionary;
    
    _configuration.timeoutIntervalForRequest = self.timeoutIntervalForRequest;
    
    return _configuration;
}

- (NSURLSession *)getAvaliableURLSessionWithURL:(NSURL *)url {
    NSURLSession *urlSession = self.urlSessionCaches[url.host];
    if (urlSession == nil) {
        @synchronized (self) {
            if (urlSession == nil) {
                NSOperationQueue *queue = [[NSOperationQueue alloc] init];
                queue.maxConcurrentOperationCount = 1;
                urlSession = [NSURLSession sessionWithConfiguration:self.configuration delegate:nil delegateQueue:queue];
                self.urlSessionCaches[url.host] = urlSession;
            }
        }
    }
    return urlSession;
}

- (NSMutableURLRequest *)createURLRequestWithURL:(NSURL *)url
                                         headers:(nullable NSDictionary <NSString *, NSString *> *)headers {
    NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:url];
    if (self.commonHeader != nil) {
        for (NSString *headerField in self.commonHeader.keyEnumerator) {
            [urlRequest setValue:self.commonHeader[headerField] forHTTPHeaderField:headerField];
        }
    }
    if (headers != nil) {
        for (NSString *headerField in headers.keyEnumerator) {
            [urlRequest setValue:headers[headerField] forHTTPHeaderField:headerField];
        }
    }
    return urlRequest;
}

- (NSString *)getURLQueryWithParameters:(nullable id)parameters {
    if ([parameters isKindOfClass:[NSString class]]) {
        return parameters;
    } else if ([parameters isKindOfClass:[NSDictionary class]]) {
        NSMutableString *queryString = [NSMutableString string];
        for (NSString *key in [parameters keyEnumerator]) {
            id result = [parameters objectForKey:key];
            [queryString appendFormat:@"%@=%@&", ZLPercentEscapedStringFromString(key), ZLPercentEscapedStringFromString([result description])];
        }
        
        if (queryString.length > 0) {
            [queryString deleteCharactersInRange:NSMakeRange(queryString.length - 1, 1)];
        }
        
        return queryString.copy;
    }
    
    return @"";
}

- (NSURLSessionDataTask *)privateHandleRequestExceptPOST:(NSString *)httpMethod
                                               urlString:(NSString *)URLString
                                              parameters:(id)parameters
                                                 headers:(NSDictionary <NSString *, NSString *> *)headers
                                        responseBodyType:(ZLResponseBodyType)responseBodyType
                                                 success:(void (^)(NSHTTPURLResponse *urlResponse, id responseObject))success
                                                 failure:(void (^)(NSError *error))failure {
    NSURL *url = nil;
    if (parameters != nil) {
        NSString *queryString = [self getURLQueryWithParameters:parameters];
        if (queryString.length > 0) {
            if ([URLString containsString:@"?"]) {
                if ([URLString hasSuffix:@"?"] || [URLString hasSuffix:@"&"]) {
                    url = [NSURL URLWithString:[URLString stringByAppendingString:queryString]];
                } else {
                    url = [NSURL URLWithString:[URLString stringByAppendingFormat:@"&%@", queryString]];
                }
            } else {
                url = [NSURL URLWithString:[URLString stringByAppendingFormat:@"?%@", queryString]];
            }
        }
    } else {
        url = [NSURL URLWithString:URLString];
    }
    
    NSParameterAssert(url != nil);
    
    NSURLSession *urlSession = [self getAvaliableURLSessionWithURL:url];
    
    NSMutableURLRequest *urlRequest = [self createURLRequestWithURL:url headers:headers];
    urlRequest.HTTPMethod = httpMethod;
    
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [urlSession dataTaskWithRequest:urlRequest completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        [weakSelf.responseQueue addOperationWithBlock:^{
            if (error != nil) {
                failure(error);
                return;
            }
            
            success((NSHTTPURLResponse *)response, ZLParseResponseBody(responseBodyType, data));
        }];
    }];
    [task resume];
    return task;
}

- (NSURLSessionDataTask *)GET:(NSString *)URLString
                   parameters:(id)parameters
                      headers:(NSDictionary <NSString *, NSString *> *)headers
             responseBodyType:(ZLResponseBodyType)responseBodyType
                      success:(void (^)(NSHTTPURLResponse *urlResponse, id responseObject))success
                      failure:(void (^)(NSError *error))failure {
    return [self privateHandleRequestExceptPOST:@"GET"
                                      urlString:URLString
                                     parameters:parameters
                                        headers:headers
                               responseBodyType:responseBodyType
                                        success:success
                                        failure:failure];
}

- (NSURLSessionDataTask *)HEAD:(NSString *)URLString
                     parameters:(id)parameters
                        headers:(NSDictionary <NSString *, NSString *> *)headers
               responseBodyType:(ZLResponseBodyType)responseBodyType
                        success:(void (^)(NSHTTPURLResponse *urlResponse, id responseObject))success
                        failure:(void (^)(NSError *error))failure {
    return [self privateHandleRequestExceptPOST:@"HEAD"
                                      urlString:URLString
                                     parameters:parameters
                                        headers:headers
                               responseBodyType:responseBodyType
                                        success:success
                                        failure:failure];
}

- (NSURLSessionDataTask *)PUT:(NSString *)URLString
                   parameters:(id)parameters
                      headers:(NSDictionary <NSString *, NSString *> *)headers
             responseBodyType:(ZLResponseBodyType)responseBodyType
                      success:(void (^)(NSHTTPURLResponse *urlResponse, id responseObject))success
                      failure:(void (^)(NSError *error))failure {
    return [self privateHandleRequestExceptPOST:@"PUT"
                                      urlString:URLString
                                     parameters:parameters
                                        headers:headers
                               responseBodyType:responseBodyType
                                        success:success
                                        failure:failure];
}

- (NSURLSessionDataTask *)PATCH:(NSString *)URLString
                     parameters:(id)parameters
                        headers:(NSDictionary <NSString *, NSString *> *)headers
               responseBodyType:(ZLResponseBodyType)responseBodyType
                        success:(void (^)(NSHTTPURLResponse *urlResponse, id responseObject))success
                        failure:(void (^)(NSError *error))failure {
    return [self privateHandleRequestExceptPOST:@"PATCH"
                                      urlString:URLString
                                     parameters:parameters
                                        headers:headers
                               responseBodyType:responseBodyType
                                        success:success
                                        failure:failure];
}

- (NSURLSessionDataTask *)DELETE:(NSString *)URLString
                      parameters:(id)parameters
                         headers:(NSDictionary <NSString *, NSString *> *)headers
                responseBodyType:(ZLResponseBodyType)responseBodyType
                         success:(void (^)(NSHTTPURLResponse *urlResponse, id responseObject))success
                         failure:(void (^)(NSError *error))failure {
    return [self privateHandleRequestExceptPOST:@"DELETE"
                                      urlString:URLString
                                     parameters:parameters
                                        headers:headers
                               responseBodyType:responseBodyType
                                        success:success
                                        failure:failure];
}

- (NSURLSessionDataTask *)CONNECT:(NSString *)URLString
                       parameters:(id)parameters
                          headers:(NSDictionary <NSString *, NSString *> *)headers
                 responseBodyType:(ZLResponseBodyType)responseBodyType
                          success:(void (^)(NSHTTPURLResponse *urlResponse, id responseObject))success
                          failure:(void (^)(NSError *error))failure {
    return [self privateHandleRequestExceptPOST:@"CONNECT"
                                      urlString:URLString
                                     parameters:parameters
                                        headers:headers
                               responseBodyType:responseBodyType
                                        success:success
                                        failure:failure];
}

- (NSURLSessionDataTask *)OPTIONS:(NSString *)URLString
                       parameters:(id)parameters
                          headers:(NSDictionary <NSString *, NSString *> *)headers
                 responseBodyType:(ZLResponseBodyType)responseBodyType
                          success:(void (^)(NSHTTPURLResponse *urlResponse, id responseObject))success
                          failure:(void (^)(NSError *error))failure {
    return [self privateHandleRequestExceptPOST:@"OPTIONS"
                                      urlString:URLString
                                     parameters:parameters
                                        headers:headers
                               responseBodyType:responseBodyType
                                        success:success
                                        failure:failure];
}

- (NSURLSessionDataTask *)TRACE:(NSString *)URLString
                     parameters:(id)parameters
                        headers:(NSDictionary <NSString *, NSString *> *)headers
               responseBodyType:(ZLResponseBodyType)responseBodyType
                        success:(void (^)(NSHTTPURLResponse *urlResponse, id responseObject))success
                        failure:(void (^)(NSError *error))failure {
    return [self privateHandleRequestExceptPOST:@"TRACE"
                                      urlString:URLString
                                     parameters:parameters
                                        headers:headers
                               responseBodyType:responseBodyType
                                        success:success
                                        failure:failure];
}

- (NSURLSessionDataTask *)POST:(NSString *)URLString
                    parameters:(id)parameters
               requestBodyType:(ZLRequestBodyType)requestBodyType
                bodyParameters:(id)bodyParameters
                       headers:(NSDictionary <NSString *, NSString *> *)headers
              responseBodyType:(ZLResponseBodyType)responseBodyType
                       success:(void (^)(NSHTTPURLResponse *urlResponse, id responseObject))success
                       failure:(void (^)(NSError *error))failure {
    NSURL *url = nil;
    if (parameters != nil) {
        NSString *queryString = [self getURLQueryWithParameters:parameters];
        if (queryString.length > 0) {
            if ([URLString containsString:@"?"]) {
                if ([URLString hasSuffix:@"?"] || [URLString hasSuffix:@"&"]) {
                    url = [NSURL URLWithString:[URLString stringByAppendingString:queryString]];
                } else {
                    url = [NSURL URLWithString:[URLString stringByAppendingFormat:@"&%@", queryString]];
                }
            } else {
                url = [NSURL URLWithString:[URLString stringByAppendingFormat:@"?%@", queryString]];
            }
        }
    } else {
        url = [NSURL URLWithString:URLString];
    }
    
    NSParameterAssert(url != nil);
    
    NSURLSession *urlSession = [self getAvaliableURLSessionWithURL:url];
    
    NSMutableURLRequest *urlRequest = [self createURLRequestWithURL:url headers:headers];
    urlRequest.HTTPMethod = @"POST";
    if (bodyParameters != nil) {
        if (requestBodyType == ZLRequestBodyTypeDefault) {
            if ([bodyParameters isKindOfClass:[NSData class]]) {
                urlRequest.HTTPBody = bodyParameters;
            } else if ([bodyParameters isKindOfClass:[NSString class]]) {
                urlRequest.HTTPBody = [(NSString *)bodyParameters dataUsingEncoding:NSUTF8StringEncoding];
            }
        } else if (requestBodyType == ZLRequestBodyTypeURLEncoding) {
            if ([bodyParameters isKindOfClass:[NSDictionary class]]) {
                NSString *str = [self getURLQueryWithParameters:bodyParameters];
                if (str) {
                    urlRequest.HTTPBody = [str dataUsingEncoding:NSUTF8StringEncoding];
                    [urlRequest setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
                }
            }
        } else if (requestBodyType == ZLRequestBodyTypeJson) {
            if ([bodyParameters isKindOfClass:[NSDictionary class]] ||
                [bodyParameters isKindOfClass:[NSArray class]] ||
                [bodyParameters isKindOfClass:[NSSet class]]) {
                NSError *error = nil;
                urlRequest.HTTPBody = [NSJSONSerialization dataWithJSONObject:bodyParameters options:0 error:&error];
                if (error == nil) {
                    [urlRequest setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
                }
            }
        } else if (requestBodyType == ZLRequestBodyTypeXml) {
            if ([bodyParameters isKindOfClass:[NSDictionary class]]) {
                NSString *str = [bodyParameters XMLString];
                if (str) {
                    urlRequest.HTTPBody = [str dataUsingEncoding:NSUTF8StringEncoding];
                    [urlRequest setValue:@"application/xml" forHTTPHeaderField:@"Content-Type"];
                }
            }
        }
    }
    
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [urlSession dataTaskWithRequest:urlRequest completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        [weakSelf.responseQueue addOperationWithBlock:^{
            if (error != nil) {
                failure(error);
                return;
            }
            
            success((NSHTTPURLResponse *)response, ZLParseResponseBody(responseBodyType, data));
        }];
    }];
    [task resume];
    return task;
}

- (void)POST:(NSString *)URLString
  parameters:(id)parameters
constructingBodyWithBlock:(void (^)(ZLMultipartFormData *formData))block
     headers:(NSDictionary <NSString *, NSString *> *)headers
responseBodyType:(ZLResponseBodyType)responseBodyType
     success:(void (^)(NSHTTPURLResponse *urlResponse, id responseObject))success
     failure:(void (^)(NSError *error))failure {
    NSURL *url = nil;
    if (parameters != nil) {
        NSString *queryString = [self getURLQueryWithParameters:parameters];
        if (queryString.length > 0) {
            if ([URLString containsString:@"?"]) {
                if ([URLString hasSuffix:@"?"] || [URLString hasSuffix:@"&"]) {
                    url = [NSURL URLWithString:[URLString stringByAppendingString:queryString]];
                } else {
                    url = [NSURL URLWithString:[URLString stringByAppendingFormat:@"&%@", queryString]];
                }
            } else {
                url = [NSURL URLWithString:[URLString stringByAppendingFormat:@"?%@", queryString]];
            }
        }
    } else {
        url = [NSURL URLWithString:URLString];
    }
    
    NSParameterAssert(url != nil);
    
    NSURLSession *urlSession = [self getAvaliableURLSessionWithURL:url];
    
    __block NSMutableURLRequest *urlRequest = [self createURLRequestWithURL:url headers:headers];
    urlRequest.HTTPMethod = @"POST";
    
    __weak typeof(self) weakSelf = self;
    [self.responseQueue addOperationWithBlock:^{
        NSString *boundary = ZLCreateMultipartFormBoundary();
        ZLMultipartFormData *formData = [[ZLMultipartFormData alloc] init];
        formData.boundary = [@"--" stringByAppendingString:boundary];
        block(formData);
        
        [formData finalData];
        urlRequest.HTTPBody = formData.data;
        
        [urlRequest setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary]
          forHTTPHeaderField:@"Content-Type"];
        [urlRequest setValue:@(urlRequest.HTTPBody.length).stringValue
          forHTTPHeaderField:@"Content-Length"];
                        
        NSURLSessionDataTask *task = [urlSession dataTaskWithRequest:urlRequest completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            [weakSelf.responseQueue addOperationWithBlock:^{
                if (error != nil) {
                    failure(error);
                    return;
                }
                
                success((NSHTTPURLResponse *)response, ZLParseResponseBody(responseBodyType, data));
            }];
        }];
        [task resume];
    }];
}

- (void)downloadWithRequest:(NSURLRequest *)request
                    headers:(NSDictionary <NSString *, NSString *> *)headers
                destination:(NSURL *)destinationURL
                   progress:(void (^)(float downloadProgress))downloadProgressBlock
          completionHandler:(void (^)(NSURLResponse *response, NSURL *filePath, NSError *error))completionHandler {
    ZLDownloadOperation *_operation = [self.downloadItems objectForKey:request.URL];
    if (_operation != nil) {
        return;
    }
    
    ZLDownloadOperation *operation = [[ZLDownloadOperation alloc] init];
    operation.mainDownloadItems = self.downloadItems;
    operation.urlRequest = request.mutableCopy;
    operation.headers = headers;
    operation.destinationURL = destinationURL;
    operation.downloadProgressBlock = downloadProgressBlock;
    operation.completionHandler = completionHandler;
    [self.downloadQueue addOperation:operation];
}

- (void)clearDiskCache {
    NSString *downloadTemp = [[ZLURLSessionManager shared].workspaceDirURLString stringByAppendingPathComponent:@"temp"];
    
    [ZLURLSessionManager deleteDirPath:downloadTemp];
    [[NSFileManager defaultManager] createDirectoryAtPath:downloadTemp withIntermediateDirectories:YES attributes:nil error:nil];
}

+ (void)deleteDirPath:(NSString *)dirPath {
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dirPath error:NULL];
    for (NSString *filename in contents) {
        NSString *filePath = [dirPath stringByAppendingPathComponent:filename];
        BOOL isDirectory = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:filePath isDirectory:&isDirectory];
        if (isDirectory) {
            [ZLURLSessionManager deleteDirPath:filePath];
        } else {
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:NULL];
        }
    }
    
    [[NSFileManager defaultManager] removeItemAtPath:dirPath error:NULL];
}

- (void)cancelDownloadForURL:(NSURL *)url {
    ZLDownloadOperation *_operation = [self.downloadItems objectForKey:url];
    if (_operation == nil) {
        return;
    }
    [_operation cancel];
}

@end
