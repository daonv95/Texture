//
//  ASCollectionFlowLayoutDelegate.mm
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import <AsyncDisplayKit/ASCollectionFlowLayoutDelegate.h>
#import <AsyncDisplayKit/_ASCollectionFlowLayoutItem.h>

#import <AsyncDisplayKit/ASCellNode+Internal.h>
#import <AsyncDisplayKit/ASCollectionLayoutState.h>
#import <AsyncDisplayKit/ASCollectionElement.h>
#import <AsyncDisplayKit/ASCollectionLayoutContext.h>
#import <AsyncDisplayKit/ASCollectionLayoutDefines.h>
#import <AsyncDisplayKit/ASCollections.h>
#import <AsyncDisplayKit/ASElementMap.h>
#import <AsyncDisplayKit/ASLayout.h>
#import <AsyncDisplayKit/ASStackLayoutSpec.h>

@implementation ASCollectionFlowLayoutDelegate {
  ASScrollDirection _scrollableDirections;
    
    struct {
        unsigned int constrainedSizeForItemAtIndexPath:1;
    } _constraintSizeProviderFlag;
}

- (instancetype)init
{
  return [self initWithScrollableDirections:ASScrollDirectionVerticalDirections];
}

- (instancetype)initWithScrollableDirections:(ASScrollDirection)scrollableDirections
{
  self = [super init];
  if (self) {
    _scrollableDirections = scrollableDirections;
  }
  return self;
}

- (void)setConstraintSizeProvider:(id<ASCollectionFlowLayoutDelegateConstraintSizeProvider>)constraintSizeProvider
{
    ASDisplayNodeAssertMainThread();
    if (constraintSizeProvider == nil) {
        _constraintSizeProvider = nil;
        _constraintSizeProviderFlag = {};
    } else {
        _constraintSizeProvider = constraintSizeProvider;
        _constraintSizeProviderFlag.constrainedSizeForItemAtIndexPath = [_constraintSizeProvider respondsToSelector:@selector(collectionFlowLayoutDelegate:constrainedSizeForItemAtIndexPath:)];
    }
}

- (ASScrollDirection)scrollableDirections
{
  ASDisplayNodeAssertMainThread();
  return _scrollableDirections;
}

- (id)additionalInfoForLayoutWithElements:(ASElementMap *)elements
{
  ASDisplayNodeAssertMainThread();
    if (_constraintSizeProviderFlag.constrainedSizeForItemAtIndexPath) {
        for (ASCollectionElement * element in elements.itemElements) {
            NSIndexPath * indexPath = [elements indexPathForElement:element];
            ASSizeRange sizeRange = [_constraintSizeProvider collectionFlowLayoutDelegate:self constrainedSizeForItemAtIndexPath:indexPath];
            if (ASSizeRangeHasSignificantArea(sizeRange)) {
                element.constrainedSize = sizeRange;
            }
        }
    }
  return nil;
}

+ (ASCollectionLayoutState *)calculateLayoutWithContext:(ASCollectionLayoutContext *)context
{
  ASElementMap *elements = context.elements;
  NSArray<ASCellNode *> *children = ASArrayByFlatMapping(elements.itemElements, ASCollectionElement *element, element.node);
  if (children.count == 0) {
    return [[ASCollectionLayoutState alloc] initWithContext:context];
  }
  
  ASStackLayoutSpec *stackSpec = [ASStackLayoutSpec stackLayoutSpecWithDirection:ASStackLayoutDirectionHorizontal
                                                                         spacing:0
                                                                  justifyContent:ASStackLayoutJustifyContentStart
                                                                      alignItems:ASStackLayoutAlignItemsStart
                                                                        flexWrap:ASStackLayoutFlexWrapWrap
                                                                    alignContent:ASStackLayoutAlignContentStart
                                                                        children:children];
  stackSpec.concurrent = YES;

  ASSizeRange sizeRange = ASSizeRangeForCollectionLayoutThatFitsViewportSize(context.viewportSize, context.scrollableDirections);
  ASLayout *layout = [stackSpec layoutThatFits:sizeRange];

  return [[ASCollectionLayoutState alloc] initWithContext:context layout:layout getElementBlock:^ASCollectionElement * _Nullable(ASLayout * _Nonnull sublayout) {
    _ASFlowLayoutItem *item = ASDynamicCast(sublayout.layoutElement, _ASFlowLayoutItem);
    return item ? item.collectionElement : nil;
  }];
}

@end
