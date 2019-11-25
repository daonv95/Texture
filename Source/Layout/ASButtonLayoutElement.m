//
//  ASButtonLayoutElement.m
//  DemoCalculateLayoutASDK
//
//  Created by Do Le Duy on 11/19/19.
//  Copyright © 2019 Do Le Duy. All rights reserved.
//

#import <AsyncDisplayKit/ASButtonLayoutElement.h>
#import <AsyncDisplayKit/AsyncDisplayKit.h>

ASMappingKeyMake(ASButton_TitleElement)
ASMappingKeyMake(ASButton_ImageElement)

@interface ASButtonLayoutElement()

@end

@implementation ASButtonLayoutElement

- (instancetype)initWithMappingKey:(ASMappingKey)mappingKey {
  self = [super initWithMappingKey:mappingKey];
  if (self) {
    _contentSpacing = 8.0;
    _laysOutHorizontally = YES;
    _contentHorizontalAlignment = ASHorizontalAlignmentMiddle;
    _contentVerticalAlignment = ASVerticalAlignmentCenter;
    _contentEdgeInsets = UIEdgeInsetsZero;
    _imageAlignment = ASButtonNodeImageAlignmentBeginning;
  }
  return self;
}

+ (instancetype)layoutElementWithImage:(UIImage *)image
                                 title:(NSAttributedString *)title
                            mappingKey:(ASMappingKey)mappingKey {
  
  ASButtonLayoutElement *element = [ASButtonLayoutElement mappingElementWithKey:mappingKey];
  
  element.titleElement = [ASTextLayoutElement layoutElementWithAttributedString:title mappingKey:ASButton_TitleElement];
  element.imageElement = [ASImageLayoutElement layoutElementWithImage:image mappingKey:ASButton_ImageElement];
  
  return element;
}

- (ASLayoutSpec *)layoutSpecThatFits:(ASSizeRange)constrainedSize {
  
  UIEdgeInsets contentEdgeInsets;
  ASButtonNodeImageAlignment imageAlignment;
  ASLayoutSpec *spec;
  ASStackLayoutSpec *stack = [[ASStackLayoutSpec alloc] init];
  {
    ASLockScopeSelf();
    stack.direction = _laysOutHorizontally ? ASStackLayoutDirectionHorizontal : ASStackLayoutDirectionVertical;
    stack.spacing = _contentSpacing;
    stack.horizontalAlignment = _contentHorizontalAlignment;
    stack.verticalAlignment = _contentVerticalAlignment;
    
    contentEdgeInsets = _contentEdgeInsets;
    imageAlignment = _imageAlignment;
  }
  
  NSMutableArray *children = [[NSMutableArray alloc] initWithCapacity:2];
  if (self.imageElement.image) {
    [children addObject:self.imageElement];
  }
  
  if (self.titleElement.attributedText.length > 0) {
    if (imageAlignment == ASButtonNodeImageAlignmentBeginning) {
      [children addObject:self.titleElement];
    } else {
      [children insertObject:self.titleElement atIndex:0];
    }
  }
  
  stack.children = children;
  
  spec = stack;
  
  if (UIEdgeInsetsEqualToEdgeInsets(UIEdgeInsetsZero, contentEdgeInsets) == NO) {
    spec = [ASInsetLayoutSpec insetLayoutSpecWithInsets:contentEdgeInsets child:spec];
  }
  
  return spec;
}

@end
