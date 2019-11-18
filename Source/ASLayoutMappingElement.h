//
//  ASLayoutMappingElement.h
//  AsyncDisplayKit
//
//  Created by Dao Nguyen Van on 11/4/19.
//  Copyright © 2019 Pinterest. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AsyncDisplayKit/ASLayoutElement.h>

NS_ASSUME_NONNULL_BEGIN

@class ASLayoutMappingElement;

typedef NSString* ASMappingKey;
typedef id<ASDisplayElement> _Nullable(^ASMappingElementBlock)(ASMappingKey mappingKey);
typedef ASLayoutSpec * _Nonnull(^ASMappingElementLayoutSpecBlock)(__kindof ASLayoutMappingElement *element, ASSizeRange constrainedSize);

#define ASMappingKeyMake(mappingKey) \
        static _Nonnull ASMappingKey mappingKey = SHADER_STRING(mappingKey);

#define ASLayoutMappingElementMake(mappingKey, mappingBlock) \
        [ASLayoutMappingElement mappingElementWithKey:mappingKey mappingElementBlock:mappingBlock];

AS_SUBCLASSING_RESTRICTED
@interface ASLayoutMappingElement : NSObject <ASLayoutElement>

@property (nonatomic, readonly) ASMappingKey mappingKey;
@property (nonatomic, readonly, copy) ASMappingElementBlock mappingElementBlock;

+ (instancetype)mappingElementWithKey:(ASMappingKey)mappingKey;
+ (instancetype)mappingElementWithKey:(ASMappingKey)mappingKey
                  mappingElementBlock:(ASMappingElementBlock)mappingElementBlock;

@end

@interface ASLayoutMappingElement (ASLayoutSpec)

@property (nullable) ASMappingElementLayoutSpecBlock layoutSpecBlock;

- (ASLayout *)calculateLayoutLayoutSpec:(ASSizeRange)constrainedSize;

@end

NS_ASSUME_NONNULL_END
