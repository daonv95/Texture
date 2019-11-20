//
//  ASTextLayoutElement.h
//  DemoCalculateLayoutASDK
//
//  Created by Do Le Duy on 11/19/19.
//  Copyright © 2019 Do Le Duy. All rights reserved.
//

#import <AsyncDisplayKit/ASLayoutMappingElement.h>

NS_ASSUME_NONNULL_BEGIN

@interface ASTextLayoutElement : ASLayoutMappingElement

@property (nullable, copy) NSAttributedString *attributedText;

+ (instancetype)layoutElementWithAttributedString:(NSAttributedString *)attributedText
                                       mappingKey:(ASMappingKey)mappingKey;

@end

NS_ASSUME_NONNULL_END
