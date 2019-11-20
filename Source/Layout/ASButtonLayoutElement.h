//
//  ASButtonLayoutElement.h
//  DemoCalculateLayoutASDK
//
//  Created by Do Le Duy on 11/19/19.
//  Copyright © 2019 Do Le Duy. All rights reserved.
//

#import <AsyncDisplayKit/ASLayoutMappingElement.h>
#import <AsyncDisplayKit/ASImageLayoutElement.h>
#import <AsyncDisplayKit/ASTextLayoutElement.h>
#import <AsyncDisplayKit/ASButtonNode.h>

NS_ASSUME_NONNULL_BEGIN

@interface ASButtonLayoutElement : ASLayoutMappingElement

@property ASTextLayoutElement *titleElement;
@property ASImageLayoutElement *imageElement;

// Layout properties
@property (atomic, assign) CGFloat contentSpacing;
@property (atomic, assign) BOOL laysOutHorizontally;
@property (atomic, assign) ASHorizontalAlignment contentHorizontalAlignment;
@property (atomic, assign) ASVerticalAlignment contentVerticalAlignment;
@property (atomic, assign) UIEdgeInsets contentEdgeInsets;
@property (atomic, assign) ASButtonNodeImageAlignment imageAlignment;

+ (instancetype)layoutElementWithImage:(UIImage *)imageNode
                                 title:(NSAttributedString *)title
                            mappingKey:(ASMappingKey)mappingKey;

@end

NS_ASSUME_NONNULL_END
