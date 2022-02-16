//
//  ZLWebSocket.h
//  ZLNetworking_Example
//
//  Created by lylaut on 2022/2/15.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class ZLWebSocket;
@protocol ZLWebSocketDelegate <NSObject>

@optional

/**
 Called when reconnect.
 */
- (NSURL *)webSocketReConnectURL;
- (NSURLRequest *)webSocketReConnectRequest;

#pragma mark Receive Messages

/**
 Called when a frame was received from a web socket.

 @param webSocket An instance of `ZLWebSocket` that received a message.
 @param string    Received text in a form of UTF-8 `String`.
 */
- (void)webSocket:(ZLWebSocket *)webSocket didReceiveMessageWithString:(NSString *)string;

/**
 Called when a frame was received from a web socket.

 @param webSocket An instance of `ZLWebSocket` that received a message.
 @param data      Received data in a form of `NSData`.
 */
- (void)webSocket:(ZLWebSocket *)webSocket didReceiveMessageWithData:(NSData *)data;

#pragma mark Status & Connection

/**
 Called when a given web socket was open and authenticated.

 @param webSocket An instance of `ZLWebSocket` that was open.
 */
- (void)webSocketDidOpen:(ZLWebSocket *)webSocket;

/**
 Called when a given web socket encountered an error.

 @param webSocket An instance of `ZLWebSocket` that failed with an error.
 @param error     An instance of `NSError`.
 */
- (void)webSocket:(ZLWebSocket *)webSocket didFailWithError:(NSError *)error;

/**
 Called when a given web socket was closed.

 @param webSocket An instance of `ZLWebSocket` that was closed.
 @param code      Code reported by the server.
 @param reason    Reason in a form of a String that was reported by the server or `nil`.
 @param wasClean  Boolean value indicating whether a socket was closed in a clean state.
 */
- (void)webSocket:(ZLWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(nullable NSString *)reason wasClean:(BOOL)wasClean;

/**
 Called on receive of a ping message from the server.

 @param webSocket An instance of `ZLWebSocket` that received a ping frame.
 @param data      Payload that was received or `nil` if there was no payload.
 */
- (void)webSocket:(ZLWebSocket *)webSocket didReceivePingWithData:(nullable NSData *)data;

/**
 Called when a pong data was received in response to ping.

 @param webSocket An instance of `ZLWebSocket` that received a pong frame.
 @param pongData  Payload that was received or `nil` if there was no payload.
 */
- (void)webSocket:(ZLWebSocket *)webSocket didReceivePong:(nullable NSData *)pongData;

@end

typedef NS_ENUM(NSInteger, ZLReadyState) {
    ZL_UNKNOWN      = 0,
    ZL_CONNECTING   = 1,
    ZL_OPEN         = 2,
    ZL_CLOSING      = 3,
    ZL_CLOSED       = 4,
    ZL_RECONNECT    = 5,
};

typedef NS_ENUM(NSInteger, ZLStatusCode) {
    // 0-999: Reserved and not used.
    ZLStatusCodeNormal = 1000,
    ZLStatusCodeGoingAway = 1001,
    ZLStatusCodeProtocolError = 1002,
    ZLStatusCodeUnhandledType = 1003,
    // 1004 reserved.
    ZLStatusNoStatusReceived = 1005,
    ZLStatusCodeAbnormal = 1006,
    ZLStatusCodeInvalidUTF8 = 1007,
    ZLStatusCodePolicyViolated = 1008,
    ZLStatusCodeMessageTooBig = 1009,
    ZLStatusCodeMissingExtension = 1010,
    ZLStatusCodeInternalError = 1011,
    ZLStatusCodeServiceRestart = 1012,
    ZLStatusCodeTryAgainLater = 1013,
    // 1014: Reserved for future use by the WebSocket standard.
    ZLStatusCodeTLSHandshake = 1015,
    // 1016-1999: Reserved for future use by the WebSocket standard.
    // 2000-2999: Reserved for use by WebSocket extensions.
    // 3000-3999: Available for use by libraries and frameworks. May not be used by applications. Available for registration at the IANA via first-come, first-serve.
    // 4000-4999: Available for use by applications.
};

/*-------------------------------------------------------------------------------*/
/*-------------------------------------------------------------------------------*/
/*-------------------------------------------------------------------------------*/
@interface ZLSecurityPolicy : NSObject

/**
 A default `SRSecurityPolicy` implementation specifies socket security and
 validates the certificate chain.

 Use a subclass of `SRSecurityPolicy` for more fine grained customization.
 */
+ (instancetype)defaultPolicy;

/**
 Updates all the security options for input and output streams, for example you
 can set your socket security level here.

 @param stream Stream to update the options in.
 */
- (void)updateSecurityOptionsInStream:(NSStream *)stream;

/**
 Whether or not the specified server trust should be accepted, based on the security policy.

 This method should be used when responding to an authentication challenge from
 a server. In the default implemenation, no further validation is done here, but
 you're free to override it in a subclass. See `SRPinningSecurityPolicy.h` for
 an example.

 @param serverTrust The X.509 certificate trust of the server.
 @param domain The domain of serverTrust.

 @return Whether or not to trust the server.
 */
- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust forDomain:(NSString *)domain;

@end


/*-------------------------------------------------------------------------------*/
/*-------------------------------------------------------------------------------*/
/*-------------------------------------------------------------------------------*/
@interface ZLWebSocket : NSObject

/**
 The delegate of the web socket.

 The web socket delegate is notified on all state changes that happen to the web socket.
 */
@property (nonatomic, weak) id <ZLWebSocketDelegate> delegate;

/**
 A dispatch queue for scheduling the delegate calls. The queue doesn't need be a serial queue.

 If `nil` and `delegateOperationQueue` is `nil`, the socket uses main queue for performing all delegate method calls.
 */
@property (nullable, nonatomic, strong) dispatch_queue_t delegateDispatchQueue;

/**
 An operation queue for scheduling the delegate calls.

 If `nil` and `delegateOperationQueue` is `nil`, the socket uses main queue for performing all delegate method calls.
 */
@property (nullable, nonatomic, strong) NSOperationQueue *delegateOperationQueue;

/**
 Current ready state of the socket. Default: `ZL_UNKNOWN`.

 This property is Key-Value Observable and fully thread-safe.
 */
@property (atomic, assign, readonly) ZLReadyState readyState;

/**
 Ping interval. Default:  5s
 */
@property (nonatomic, assign) int pingInterval;

/**
 An instance of `NSURL` that this socket connects to.
 */
@property (nullable, nonatomic, strong, readonly) NSURL *url;

/**
 All HTTP headers that were received by socket or `nil` if none were received so far.
 */
@property (nullable, nonatomic, assign, readonly) CFHTTPMessageRef receivedHTTPHeaders;

/**
 Array of `NSHTTPCookie` cookies to apply to the connection.
 */
@property (nullable, nonatomic, copy) NSArray<NSHTTPCookie *> *requestCookies;

/**
 The negotiated web socket protocol or `nil` if handshake did not yet complete.
 */
@property (nullable, nonatomic, copy, readonly) NSString *protocol;

/**
 A boolean value indicating whether this socket will allow connection without SSL trust chain evaluation.
 For DEBUG builds this flag is ignored, and SSL connections are allowed regardless of the certificate trust configuration
 */
@property (nonatomic, assign, readonly) BOOL allowsUntrustedSSLCertificates;

///--------------------------------------
#pragma mark - Constructors
///--------------------------------------

/**
 Initializes a web socket with a given `NSURLRequest`.

 @param request Request to initialize with.
 */
- (instancetype)initWithURLRequest:(NSURLRequest *)request;

/**
 Initializes a web socket with a given `NSURLRequest`, specifying a transport security policy (e.g. SSL configuration).

 @param request        Request to initialize with.
 @param securityPolicy Policy object describing transport security behavior.
 */
- (instancetype)initWithURLRequest:(NSURLRequest *)request securityPolicy:(ZLSecurityPolicy *)securityPolicy;

/**
 Initializes a web socket with a given `NSURLRequest` and list of sub-protocols.

 @param request   Request to initialize with.
 @param protocols An array of strings that turn into `Sec-WebSocket-Protocol`. Default: `nil`.
 */
- (instancetype)initWithURLRequest:(NSURLRequest *)request protocols:(nullable NSArray<NSString *> *)protocols;

/**
 Initializes a web socket with a given `NSURLRequest`, list of sub-protocols and whether untrusted SSL certificates are allowed.

 @param request        Request to initialize with.
 @param protocols      An array of strings that turn into `Sec-WebSocket-Protocol`. Default: `nil`.
 @param securityPolicy Policy object describing transport security behavior.
 */
- (instancetype)initWithURLRequest:(NSURLRequest *)request protocols:(nullable NSArray<NSString *> *)protocols securityPolicy:(ZLSecurityPolicy *)securityPolicy NS_DESIGNATED_INITIALIZER;

/**
 Initializes a web socket with a given `NSURL`.

 @param url URL to initialize with.
 */
- (instancetype)initWithURL:(NSURL *)url;

/**
 Initializes a web socket with a given `NSURL` and list of sub-protocols.

 @param url       URL to initialize with.
 @param protocols An array of strings that turn into `Sec-WebSocket-Protocol`. Default: `nil`.
 */
- (instancetype)initWithURL:(NSURL *)url protocols:(nullable NSArray<NSString *> *)protocols;

/**
 Initializes a web socket with a given `NSURL`, specifying a transport security policy (e.g. SSL configuration).

 @param url            URL to initialize with.
 @param securityPolicy Policy object describing transport security behavior.
 */
- (instancetype)initWithURL:(NSURL *)url securityPolicy:(ZLSecurityPolicy *)securityPolicy;

/**
 Unavailable initializer. Please use any other initializer.
 */
- (instancetype)init NS_UNAVAILABLE;

/**
 Unavailable constructor. Please use any other initializer.
 */
+ (instancetype)new NS_UNAVAILABLE;

///--------------------------------------
#pragma mark - Schedule
///--------------------------------------

/**
 Schedules a received on a given run loop in a given mode.
 By default, a web socket will schedule itself on `+[NSRunLoop SR_networkRunLoop]` using `NSDefaultRunLoopMode`.

 @param runLoop The run loop on which to schedule the receiver.
 @param mode     The mode for the run loop.
 */
- (void)scheduleInRunLoop:(NSRunLoop *)runLoop forMode:(NSString *)mode NS_SWIFT_NAME(schedule(in:forMode:));

/**
 Removes the receiver from a given run loop running in a given mode.

 @param runLoop The run loop on which the receiver was scheduled.
 @param mode    The mode for the run loop.
 */
- (void)unscheduleFromRunLoop:(NSRunLoop *)runLoop forMode:(NSString *)mode NS_SWIFT_NAME(unschedule(from:forMode:));

///--------------------------------------
#pragma mark - Open / Close
///--------------------------------------

/**
 Opens web socket, which will trigger connection, authentication and start receiving/sending events.
 An instance of `ZLWebSocket` is intended for one-time-use only. This method should be called once and only once.
 */
- (void)open;

/**
 Closes a web socket using `SRStatusCodeNormal` code and no reason.
 */
- (void)close;

/**
 Closes a web socket using a given code and reason.

 @param code   Code to close the socket with.
 @param reason Reason to send to the server or `nil`.
 */
- (void)closeWithCode:(NSInteger)code reason:(nullable NSString *)reason;

///--------------------------------------
#pragma mark Send
///--------------------------------------

/**
 Send a UTF-8 String to the server.

 @param string String to send.
 @param error  On input, a pointer to variable for an `NSError` object.
 If an error occurs, this pointer is set to an `NSError` object containing information about the error.
 You may specify `nil` to ignore the error information.

 @return `YES` if the string was scheduled to send, otherwise - `NO`.
 */
- (BOOL)sendString:(NSString *)string error:(NSError **)error NS_SWIFT_NAME(send(string:));

/**
 Send binary data to the server.

 @param data  Data to send.
 @param error On input, a pointer to variable for an `NSError` object.
 If an error occurs, this pointer is set to an `NSError` object containing information about the error.
 You may specify `nil` to ignore the error information.

 @return `YES` if the string was scheduled to send, otherwise - `NO`.
 */
- (BOOL)sendData:(nullable NSData *)data error:(NSError **)error NS_SWIFT_NAME(send(data:));

/**
 Send binary data to the server, without making a defensive copy of it first.

 @param data  Data to send.
 @param error On input, a pointer to variable for an `NSError` object.
 If an error occurs, this pointer is set to an `NSError` object containing information about the error.
 You may specify `nil` to ignore the error information.

 @return `YES` if the string was scheduled to send, otherwise - `NO`.
 */
- (BOOL)sendDataNoCopy:(nullable NSData *)data error:(NSError **)error NS_SWIFT_NAME(send(dataNoCopy:));

/**
 Send Ping message to the server with optional data.

 @param data  Instance of `NSData` or `nil`.
 @param error On input, a pointer to variable for an `NSError` object.
 If an error occurs, this pointer is set to an `NSError` object containing information about the error.
 You may specify `nil` to ignore the error information.

 @return `YES` if the string was scheduled to send, otherwise - `NO`.
 */
- (BOOL)sendPing:(nullable NSData *)data error:(NSError **)error NS_SWIFT_NAME(sendPing(_:));

@end

NS_ASSUME_NONNULL_END
