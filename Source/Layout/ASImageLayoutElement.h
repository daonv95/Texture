//
//  ASImageLayoutElement.h
//  DemoCalculateLayoutASDK
//
//  Created by Do Le Duy on 11/19/19.
//  Copyright © 2019 Do Le Duy. All rights reserved.
//

#import <AsyncDisplayKit/ASLayoutMappingElement.h>

NS_ASSUME_NONNULL_BEGIN

@interface ASImageLayoutElement : ASLayoutMappingElement

@property (atomic, nullable) UIImage *image;

+ (instancetype)layoutElementWithImage:(UIImage *)image
                            mappingKey:(ASMappingKey)mappingKey
                          mappingBlock:(ASMappingElementBlock)mappingBlock;

@end

NS_ASSUME_NONNULL_END
