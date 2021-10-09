//
//  ZLURLSessionManager.m
//  ZLNetworking_Example
//
//  Created by lylaut on 2021/9/30.
//  Copyright © 2021 richiezhl. All rights reserved.
//

#import "ZLURLSessionManager.h"
#import "XMLDictionary.h"
#import <sys/sysctl.h>
#import <CoreServices/CoreServices.h>

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

@interface ZLURLSessionManager ()

@property (nonatomic, strong) NSURLSessionConfiguration *configuration;

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSURLSession *> *urlSessionCaches;

@property (nonatomic, strong) NSOperationQueue *responseQueue;

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
        _responseQueue.maxConcurrentOperationCount = countOfCores() * 2;
        _reachablity = [ZLReachability reachabilityWithHostName:@"www.apple.com"];
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

@end
