//
//  ZLXMLDictionary.h
//
//  Version 1.4.1
//
//  Created by Nick Lockwood on 15/11/2010.
//  Copyright 2010 Charcoal Design. All rights reserved.
//
//  Get the latest version of ZLXMLDictionary from here:
//
//  https://github.com/nicklockwood/ZLXMLDictionary
//
//  This software is provided 'as-is', without any express or implied
//  warranty.  In no event will the authors be held liable for any damages
//  arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//  claim that you wrote the original software. If you use this software
//  in a product, an acknowledgment in the product documentation would be
//  appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be
//  misrepresented as being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.
//

#import <Foundation/Foundation.h>
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wobjc-missing-property-synthesis"


NS_ASSUME_NONNULL_BEGIN


typedef NS_ENUM(NSInteger, ZLXMLDictionaryAttributesMode)
{
    ZLXMLDictionaryAttributesModePrefixed = 0, //default
    ZLXMLDictionaryAttributesModeDictionary,
    ZLXMLDictionaryAttributesModeUnprefixed,
    ZLXMLDictionaryAttributesModeDiscard
};


typedef NS_ENUM(NSInteger, ZLXMLDictionaryNodeNameMode)
{
    ZLXMLDictionaryNodeNameModeRootOnly = 0, //default
    ZLXMLDictionaryNodeNameModeAlways,
    ZLXMLDictionaryNodeNameModeNever
};


@interface ZLXMLDictionaryParser : NSObject <NSCopying>

+ (ZLXMLDictionaryParser *)sharedInstance;

@property (nonatomic, assign) BOOL collapseTextNodes; // defaults to YES
@property (nonatomic, assign) BOOL stripEmptyNodes;   // defaults to YES
@property (nonatomic, assign) BOOL trimWhiteSpace;    // defaults to YES
@property (nonatomic, assign) BOOL alwaysUseArrays;   // defaults to NO
@property (nonatomic, assign) BOOL preserveComments;  // defaults to NO
@property (nonatomic, assign) BOOL wrapRootNode;      // defaults to NO

@property (nonatomic, assign) ZLXMLDictionaryAttributesMode attributesMode;
@property (nonatomic, assign) ZLXMLDictionaryNodeNameMode nodeNameMode;

- (nullable NSDictionary<NSString *, id> *)dictionaryWithParser:(NSXMLParser *)parser;
- (nullable NSDictionary<NSString *, id> *)dictionaryWithData:(NSData *)data;
- (nullable NSDictionary<NSString *, id> *)dictionaryWithString:(NSString *)string;
- (nullable NSDictionary<NSString *, id> *)dictionaryWithFile:(NSString *)path;

@end


@interface NSDictionary (ZLXMLDictionary)

+ (nullable NSDictionary<NSString *, id> *)dictionaryWithXMLParser:(NSXMLParser *)parser;
+ (nullable NSDictionary<NSString *, id> *)dictionaryWithXMLData:(NSData *)data;
+ (nullable NSDictionary<NSString *, id> *)dictionaryWithXMLString:(NSString *)string;
+ (nullable NSDictionary<NSString *, id> *)dictionaryWithXMLFile:(NSString *)path;

@property (nonatomic, readonly, copy, nullable) NSDictionary<NSString *, NSString *> *attributes;
@property (nonatomic, readonly, copy, nullable) NSDictionary<NSString *, id> *childNodes;
@property (nonatomic, readonly, copy, nullable) NSArray<NSString *> *comments;
@property (nonatomic, readonly, copy, nullable) NSString *nodeName;
@property (nonatomic, readonly, copy, nullable) NSString *innerText;
@property (nonatomic, readonly, copy) NSString *innerXML;
@property (nonatomic, readonly, copy) NSString *XMLString;

- (nullable NSArray *)arrayValueForKeyPath:(NSString *)keyPath;
- (nullable NSString *)stringValueForKeyPath:(NSString *)keyPath;
- (nullable NSDictionary<NSString *, id> *)dictionaryValueForKeyPath:(NSString *)keyPath;

@end


NS_ASSUME_NONNULL_END


#pragma GCC diagnostic pop
