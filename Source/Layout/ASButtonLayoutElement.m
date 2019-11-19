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

- (instancetype)initWithMappingKey:(ASMappingKey)mappingKey mappingElementBlock:(ASMappingElementBlock)mappingElementBlock {
  self = [super initWithMappingKey:mappingKey mappingElementBlock:mappingElementBlock];
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
                            mappingKey:(ASMappingKey)mappingKey
                          mappingBlock:(ASMappingElementBlock)mappingBlock {
  
  ASButtonLayoutElement *element = [ASButtonLayoutElement mappingElementWithKey:mappingKey mappingElementBlock:mappingBlock];
  
  __weak typeof(element) weakElement = element;
  element.titleElement = [ASTextLayoutElement layoutElementWithAttributedString:title mappingKey:ASButton_TitleElement mappingBlock:^id<ASDisplayElement> _Nullable(ASMappingKey  _Nonnull mappingKey) {
    return ((ASButtonNode *)weakElement.displayElement).titleNode;
  }];
  element.imageElement = [ASImageLayoutElement layoutElementWithImage:image mappingKey:ASButton_ImageElement mappingBlock:^id<ASDisplayElement> _Nullable(ASMappingKey  _Nonnull mappingKey) {
    return ((ASButtonNode *)weakElement.displayElement).imageNode;
  }];
  
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
