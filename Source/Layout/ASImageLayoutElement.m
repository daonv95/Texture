//
//  ASImageLayoutElement.m
//  DemoCalculateLayoutASDK
//
//  Created by Do Le Duy on 11/19/19.
//  Copyright © 2019 Do Le Duy. All rights reserved.
//

#import "ASImageLayoutElement.h"

@implementation ASImageLayoutElement

+ (instancetype)layoutElementWithImage:(UIImage *)image
                            mappingKey:(ASMappingKey)mappingKey
                          mappingBlock:(ASMappingElementBlock)mappingBlock {
  
  ASImageLayoutElement *element = [ASImageLayoutElement mappingElementWithKey:mappingKey
                                                          mappingElementBlock:mappingBlock];
  element.image = image;
  element.style.flexShrink = 1.0;
  element.style.flexGrow = 0.0;
  
  return element;
}

- (CGSize)calculateSizeThatFits:(CGSize)constrainedSize {
  if (self.image == nil) {
    return [super calculateSizeThatFits:constrainedSize];
  }
  return self.image.size;
}

@end
