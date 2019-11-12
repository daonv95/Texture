//
//  ASDisplayElement.m
//  AsyncDisplayKit
//
//  Created by Dao Nguyen Van on 11/4/19.
//  Copyright © 2019 Pinterest. All rights reserved.
//

#import <AsyncDisplayKit/ASDisplayElement.h>
#import <AsyncDisplayKit/ASView.h>
#import <AsyncDisplayKit/ASEqualityHelpers.h>
#import <AsyncDisplayKit/ASDisplayNode+Beta.h>

@implementation ASDisplayNode (ASDisplayElement)


@end

@implementation UIView (ASDisplayElement)

- (BOOL)automaticallyManagesSubnodes {
  return self.automaticallyManageSubviews;
}

- (void)_removeFromSupernodeIfEqualTo:(UIView *)superview
{
  // Only remove if supernode is still the expected supernode
  if (!ASObjectIsEqual(self.superview, superview)) {
    return;
  }
  
  [self removeFromSuperview];
}

- (NSArray *)subnodes
{
  return self.subviews;
}

// NOTE: This method must be dealloc-safe (should not retain self).
- (UIView *)supernode
{
  return self.superview;
}

- (void)_setSupernode:(ASDisplayNode *)newSupernode {}


- (void)addSubnode:(UIView *)subview
{
  ASDisplayNodeLogEvent(self, @"addSubnode: %@ with automaticallyManagesSubnodes: %@",
                        subview, self.automaticallyManagesSubnodes ? @"YES" : @"NO");
  [self addSubview:subview];
}

- (void)_addSubnode:(UIView *)subview
{
  [self addSubview:subview];
}

- (void)insertSubnode:(UIView *)subview belowSubnode:(UIView *)below
{
  ASDisplayNodeLogEvent(self, @"insertSubnode: %@ belowSubnode: %@ with automaticallyManagesSubnodes: %@",
                        subview, below, self.automaticallyManagesSubnodes ? @"YES" : @"NO");

  [self _insertSubnode:subview belowSubnode:below];
}

- (void)_insertSubnode:(UIView *)subview belowSubnode:(UIView *)below
{
  [self insertSubview:subview belowSubview:below];
}

- (void)insertSubnode:(UIView *)subview aboveSubnode:(UIView *)above
{
  ASDisplayNodeLogEvent(self, @"insertSubnode: %@ abodeSubnode: %@ with automaticallyManagesSubnodes: %@",
                        subview, above, self.automaticallyManagesSubnodes ? @"YES" : @"NO");
  [self _insertSubnode:subview aboveSubnode:above];
}

- (void)_insertSubnode:(UIView *)subview aboveSubnode:(UIView *)above
{
  [self insertSubview:subview aboveSubview:above];
}

- (void)insertSubnode:(UIView *)subview atIndex:(NSInteger)idx
{
  ASDisplayNodeLogEvent(self, @"insertSubnode: %@ atIndex: %td with automaticallyManagesSubnodes: %@",
                        subview, idx, self.automaticallyManagesSubnodes ? @"YES" : @"NO");
  [self _insertSubnode:subview atIndex:idx];
}

- (void)_insertSubnode:(UIView *)subview atIndex:(NSInteger)idx
{
  [self insertSubview:subview atIndex:idx];
}

- (void)_removeSubnode:(UIView *)subview
{
  if ([self.subviews containsObject:subview]) {
    [subview removeFromSuperview];
  }
}

- (void)removeFromSupernode
{
  ASDisplayNodeLogEvent(self, @"removeFromSupernode with automaticallyManagesSubnodes: %@",
                        self.automaticallyManagesSubnodes ? @"YES" : @"NO");
  [self _removeFromSupernode];
}

- (void)_removeFromSupernode
{
  [self removeFromSuperview];
}

@end
