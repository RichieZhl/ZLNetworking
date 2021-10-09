//
//  ZLURLSessionManager.h
//  ZLNetworking_Example
//
//  Created by lylaut on 2021/9/30.
//  Copyright © 2021 richiezhl. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ZLReachability.h"

typedef NS_ENUM(NSInteger, ZLRequestBodyType) {
    ZLRequestBodyTypeDefault = 0,
    ZLRequestBodyTypeURLEncoding,
    ZLRequestBodyTypeJson,
    ZLRequestBodyTypeXml
};

typedef NS_ENUM(NSInteger, ZLResponseBodyType) {
    ZLResponseBodyTypeDefault = 0,
    ZLResponseBodyTypeJson,
    ZLResponseBodyTypeXml
};


@interface ZLMultipartFormData : NSObject

/**
 Appends the HTTP header `Content-Disposition: file; filename=#{generated filename}; name=#{name}"` and `Content-Type: #{generated mimeType}`, followed by the encoded file data and the multipart form boundary.

 The filename and MIME type for this data in the form will be automatically generated, using the last path component of the `fileURL` and system associated MIME type for the `fileURL` extension, respectively.

 @param fileURL The URL corresponding to the file whose content will be appended to the form. This parameter must not be `nil`.
 @param name The name to be associated with the specified data. This parameter must not be `nil`.

 @return `YES` if the file data was successfully appended, otherwise `NO`.
 */
- (BOOL)appendPartWithFileURL:(NSURL *)fileURL
                         name:(NSString *)name;

/**
 Appends the HTTP header `Content-Disposition: file; filename=#{filename}; name=#{name}"` and `Content-Type: #{mimeType}`, followed by the encoded file data and the multipart form boundary.

 @param fileURL The URL corresponding to the file whose content will be appended to the form. This parameter must not be `nil`.
 @param name The name to be associated with the specified data. This parameter must not be `nil`.
 @param fileName The file name to be used in the `Content-Disposition` header. This parameter must not be `nil`.
 @param mimeType The declared MIME type of the file data. This parameter must not be `nil`.

 @return `YES` if the file data was successfully appended otherwise `NO`.
 */
- (BOOL)appendPartWithFileURL:(NSURL *)fileURL
                         name:(NSString *)name
                     fileName:(NSString *)fileName
                     mimeType:(NSString *)mimeType;

/**
 Appends the HTTP header `Content-Disposition: file; filename=#{filename}; name=#{name}"` and `Content-Type: #{mimeType}`, followed by the encoded file data and the multipart form boundary.

 @param data The data to be encoded and appended to the form data.
 @param name The name to be associated with the specified data. This parameter must not be `nil`.
 @param fileName The filename to be associated with the specified data. This parameter must not be `nil`.
 @param mimeType The MIME type of the specified data. (For example, the MIME type for a JPEG image is image/jpeg.) For a list of valid MIME types, see http://www.iana.org/assignments/media-types/. This parameter must not be `nil`.
 */
- (void)appendPartWithFileData:(NSData *)data
                          name:(NSString *)name
                      fileName:(NSString *)fileName
                      mimeType:(NSString *)mimeType;

@end

@interface ZLURLSessionManager : NSObject

/// 代理设置 nil 使用系统代理 @ {} 禁止代理 @ {....} 使用自定义代理
///  @{
///     (NSString *)kCFNetworkProxiesHTTPEnable  : [NSNumber numberWithInt:1],
///     (NSString *)kCFNetworkProxiesHTTPProxy: proxyHost,
///     (NSString *)kCFNetworkProxiesHTTPProxyPort: proxyPort,
///
///     (NSString *)kCFNetworkProxiesHTTPSEnable : [NSNumber numberWithInt:1],
///     (NSString *)kCFNetworkProxiesHTTPSProxy: proxyHost,
///     (NSString *)kCFNetworkProxiesHTTPSProxyPort: proxyPort,
/// }
@property (nonatomic, copy) NSDictionary *connectionProxyDictionary;

/// 请求超时时间
@property (nonatomic, assign) NSInteger timeoutIntervalForRequest;

/// 通用请求头，如鉴权
@property (nonatomic, copy) NSDictionary *commonHeader;

@property (nonatomic, strong) ZLReachability *reachablity;

+ (instancetype)shared;

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)new NS_UNAVAILABLE;

- (NSURLSessionDataTask *)GET:(NSString *)URLString
                   parameters:(id)parameters
                      headers:(NSDictionary <NSString *, NSString *> *)headers
             responseBodyType:(ZLResponseBodyType)responseBodyType
                      success:(void (^)(NSHTTPURLResponse *urlResponse, id responseObject))success
                      failure:(void (^)(NSError *error))failure;

- (NSURLSessionDataTask *)HEAD:(NSString *)URLString
                     parameters:(id)parameters
                        headers:(NSDictionary <NSString *, NSString *> *)headers
               responseBodyType:(ZLResponseBodyType)responseBodyType
                        success:(void (^)(NSHTTPURLResponse *urlResponse, id responseObject))success
                        failure:(void (^)(NSError *error))failure;

- (NSURLSessionDataTask *)PUT:(NSString *)URLString
                   parameters:(id)parameters
                      headers:(NSDictionary <NSString *, NSString *> *)headers
             responseBodyType:(ZLResponseBodyType)responseBodyType
                      success:(void (^)(NSHTTPURLResponse *urlResponse, id responseObject))success
                      failure:(void (^)(NSError *error))failure;

- (NSURLSessionDataTask *)PATCH:(NSString *)URLString
                     parameters:(id)parameters
                        headers:(NSDictionary <NSString *, NSString *> *)headers
               responseBodyType:(ZLResponseBodyType)responseBodyType
                        success:(void (^)(NSHTTPURLResponse *urlResponse, id responseObject))success
                        failure:(void (^)(NSError *error))failure;

- (NSURLSessionDataTask *)DELETE:(NSString *)URLString
                      parameters:(id)parameters
                         headers:(NSDictionary <NSString *, NSString *> *)headers
                responseBodyType:(ZLResponseBodyType)responseBodyType
                         success:(void (^)(NSHTTPURLResponse *urlResponse, id responseObject))success
                         failure:(void (^)(NSError *error))failure;

- (NSURLSessionDataTask *)CONNECT:(NSString *)URLString
                       parameters:(id)parameters
                          headers:(NSDictionary <NSString *, NSString *> *)headers
                 responseBodyType:(ZLResponseBodyType)responseBodyType
                          success:(void (^)(NSHTTPURLResponse *urlResponse, id responseObject))success
                          failure:(void (^)(NSError *error))failure;

- (NSURLSessionDataTask *)OPTIONS:(NSString *)URLString
                       parameters:(id)parameters
                          headers:(NSDictionary <NSString *, NSString *> *)headers
                 responseBodyType:(ZLResponseBodyType)responseBodyType
                          success:(void (^)(NSHTTPURLResponse *urlResponse, id responseObject))success
                          failure:(void (^)(NSError *error))failure;

- (NSURLSessionDataTask *)TRACE:(NSString *)URLString
                     parameters:(id)parameters
                        headers:(NSDictionary <NSString *, NSString *> *)headers
               responseBodyType:(ZLResponseBodyType)responseBodyType
                        success:(void (^)(NSHTTPURLResponse *urlResponse, id responseObject))success
                        failure:(void (^)(NSError *error))failure;

- (NSURLSessionDataTask *)POST:(NSString *)URLString
                    parameters:(id)parameters
               requestBodyType:(ZLRequestBodyType)requestBodyType
                bodyParameters:(id)bodyParameters
                       headers:(NSDictionary <NSString *, NSString *> *)headers
              responseBodyType:(ZLResponseBodyType)responseBodyType
                       success:(void (^)(NSHTTPURLResponse *urlResponse, id responseObject))success
                       failure:(void (^)(NSError *error))failure;

- (void)POST:(NSString *)URLString
  parameters:(id)parameters
constructingBodyWithBlock:(void (^)(ZLMultipartFormData *formData))block
     headers:(NSDictionary <NSString *, NSString *> *)headers
responseBodyType:(ZLResponseBodyType)responseBodyType
     success:(void (^)(NSHTTPURLResponse *urlResponse, id responseObject))success
     failure:(void (^)(NSError *error))failure;

@end
