//
//  ASTextLayoutElement.m
//  DemoCalculateLayoutASDK
//
//  Created by Do Le Duy on 11/19/19.
//  Copyright © 2019 Do Le Duy. All rights reserved.
//

#import <AsyncDisplayKit/ASTextLayoutElement.h>

@implementation ASTextLayoutElement

+ (instancetype)layoutElementWithAttributedString:(NSAttributedString *)attributedText
                                       mappingKey:(ASMappingKey)mappingKey
                                     mappingBlock:(ASMappingElementBlock)mappingBlock {
  
  ASTextLayoutElement *element = [ASTextLayoutElement mappingElementWithKey:mappingKey mappingElementBlock:mappingBlock];
  element.attributedText = attributedText;
  element.style.flexShrink = 1.0;
  element.style.flexGrow = 0.0;
  
  return element;
}

- (CGSize)calculateSizeThatFits:(CGSize)constrainedSize {
  
  CGRect boundingRect = [self.attributedText boundingRectWithSize:constrainedSize
                                                          options:NSStringDrawingUsesLineFragmentOrigin
                                                          context:nil];
  return CGSizeMake(ceil(boundingRect.size.width), ceil(boundingRect.size.height));
}

@end
