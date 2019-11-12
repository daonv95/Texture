//
//  ASView.m
//  AsyncDisplayKit
//
//  Created by Dao Nguyen Van on 11/4/19.
//  Copyright © 2019 Pinterest. All rights reserved.
//

#import <AsyncDisplayKit/ASView.h>
#import <AsyncDisplayKit/ASThread.h>
#import <AsyncDisplayKit/ASDisplayElement.h>
#import <AsyncDisplayKit/ASDisplayNodeLayout.h>
#import <AsyncDisplayKit/ASLayoutSpec+Subclasses.h>
#import <AsyncDisplayKit/ASLayoutSpecPrivate.h>
#import <AsyncDisplayKit/ASDimensionInternal.h>
#import <AsyncDisplayKit/ASDisplayNode.h>
#import <AsyncDisplayKit/ASDisplayNode+Beta.h>
#import <AsyncDisplayKit/ASLayoutElementStylePrivate.h>
#import <AsyncDisplayKit/ASLayoutTransition.h>
#import <AsyncDisplayKit/ASLog.h>

BOOL ASUIViewSubclassOverridesSelector(Class subclass, SEL selector)
{
  return ASSubclassOverridesSelector([ASView class], subclass, selector) ||
         (ASSubclassOverridesSelector([UIView class], subclass, selector) && subclass != ASView.class);
}

@interface UIView (ASLayoutElementInternal)

@property (nonatomic, assign, setter=_setCalculatedDisplayNodeLayout:) ASDisplayNodeLayout _calculatedDisplayNodeLayout;
@property (nonatomic, assign, setter=_setPendingDisplayNodeLayout:) ASDisplayNodeLayout _pendingDisplayNodeLayout;

@property (nonatomic, strong, setter=_setStyle:) ASLayoutElementStyle *_style;
@property (nonatomic, assign, setter=_setLayoutVersion:) NSUInteger _layoutVersion;
@property (nonatomic, assign, setter=_setTransitionID:) NSUInteger _transitionID;

// Debug
@property (nonatomic, strong, setter=_setDebugName:) NSString *_debugName;
@property (nonatomic, strong, setter=_setUnflattenedLayout:) ASLayout *_unflattenedLayout;

@end

@implementation UIView (ASLayoutElementInternal)

ASDK_STYLE_PROP_STR(ASDisplayNodeLayout, _calculatedDisplayNodeLayout, _setCalculatedDisplayNodeLayout, ASDisplayNodeLayout())
ASDK_STYLE_PROP_STR(ASDisplayNodeLayout, _pendingDisplayNodeLayout, _setPendingDisplayNodeLayout, ASDisplayNodeLayout())
ASDK_STYLE_PROP_OBJ(ASLayoutElementStyle *, _style, _setStyle)
ASDK_STYLE_PROP_PRIM(NSUInteger, _layoutVersion, _setLayoutVersion, 0)
ASDK_STYLE_PROP_PRIM(NSUInteger, _transitionID, _transitionID, 0)

ASDK_STYLE_PROP_OBJ(NSString *, _debugName, _setDebugName)
ASDK_STYLE_PROP_OBJ(ASLayout *, _unflattenedLayout, _setUnflattenedLayout)

@end

@implementation UIView (ASLayoutElement)

#pragma mark - ASLayoutElement Protocol

- (ASLayoutElementType)layoutElementType
{
  return ASLayoutElementTypeUIView;
}

- (id<ASDisplayElement>)displayElement {
  return self;
}

- (ASPrimitiveTraitCollection)primitiveTraitCollection
{
  id obj = objc_getAssociatedObject(self, @selector(primitiveTraitCollection));
  if (obj == nil) {
    return ASPrimitiveTraitCollectionMakeDefault();
  }
  ASPrimitiveTraitCollection primitiveTraitCollection;
  [obj getValue:&primitiveTraitCollection];
  return primitiveTraitCollection;
}
- (void)setPrimitiveTraitCollection:(ASPrimitiveTraitCollection)traitCollection
{
  objc_setAssociatedObject(self, @selector(primitiveTraitCollection), [NSValue value:&traitCollection withObjCType:@encode(ASPrimitiveTraitCollection)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (ASTraitCollection *)asyncTraitCollection
{
  return [ASTraitCollection traitCollectionWithASPrimitiveTraitCollection:self.primitiveTraitCollection];
}

- (NSArray<id<ASLayoutElement>> *)sublayoutElements
{
  return self.subviews;
}

#pragma mark - ASLayoutElementStyle

- (ASLayoutElementStyle *)style {
  if (self._style == nil) {
    self._style = [[ASLayoutElementStyle alloc] init];
  }
  return self._style;
}

#pragma mark - Calculate layout

- (ASLayoutEngineType)layoutEngineType
{
#if YOGA
  YGNodeRef yogaNode = _style.yogaNode;
  BOOL hasYogaParent = (_yogaParent != nil);
  BOOL hasYogaChildren = (_yogaChildren.count > 0);
  if (yogaNode != NULL && (hasYogaParent || hasYogaChildren)) {
    return ASLayoutEngineTypeYoga;
  }
#endif
  
  return ASLayoutEngineTypeLayoutSpec;
}

- (ASLayout *)layoutThatFits:(ASSizeRange)constrainedSize
{
  return [self layoutThatFits:constrainedSize parentSize:constrainedSize.max];
}

- (ASLayout *)layoutThatFits:(ASSizeRange)constrainedSize parentSize:(CGSize)parentSize
{
  ASLayout *layout = nil;
  NSUInteger version = self._layoutVersion;
  if (self._calculatedDisplayNodeLayout.isValid(constrainedSize, parentSize, version)) {
    ASDisplayNodeAssertNotNil(self._calculatedDisplayNodeLayout.layout, @"-[ASDisplayNode layoutThatFits:parentSize:] _calculatedDisplayNodeLayout.layout should not be nil! %@", self);
    layout = self._calculatedDisplayNodeLayout.layout;
  }
  else if (self._pendingDisplayNodeLayout.isValid(constrainedSize, parentSize, version)) {
    layout = self._pendingDisplayNodeLayout.layout;
  } else {
    // Create a pending display node layout for the layout pass
    layout = [self calculateLayoutThatFits:constrainedSize
                          restrictedToSize:self.style.size
                      relativeToParentSize:parentSize];
    as_log_verbose(ASLayoutLog(), "Established pending layout for %@ in %s", self, sel_getName(_cmd));
    self._pendingDisplayNodeLayout = ASDisplayNodeLayout(layout, constrainedSize, parentSize,version);
    ASDisplayNodeAssertNotNil(layout, @"-[ASDisplayNode layoutThatFits:parentSize:] newly calculated layout should not be nil! %@", self);
  }
  
  return layout ?: [ASLayout layoutWithLayoutElement:self size:{0, 0}];
}

- (ASLayout *)calculateLayoutThatFits:(ASSizeRange)constrainedSize
{
  switch (self.layoutEngineType) {
    case ASLayoutEngineTypeLayoutSpec:
      return [self calculateLayoutLayoutSpec:constrainedSize];
#if YOGA
    case ASLayoutEngineTypeYoga:
      return [self calculateLayoutYoga:constrainedSize];
#endif
      // If YOGA is not defined but for some reason the layout type engine is Yoga
      // we explicitly fallthrough here
    default:
      break;
  }
  
  // If this case is reached a layout type engine was defined for a node that is currently
  // not supported.
  ASDisplayNodeAssert(NO, @"No layout type determined");
  return nil;
}

- (CGSize)calculateSizeThatFits:(CGSize)constrainedSize
{
  ASDisplayNodeLogEvent(self, @"calculateSizeThatFits: with constrainedSize: %@", NSStringFromCGSize(constrainedSize));
  
  return ASIsCGSizeValidForSize(constrainedSize) ? constrainedSize : CGSizeZero;
}

- (ASLayout *)calculateLayoutThatFits:(ASSizeRange)constrainedSize
                     restrictedToSize:(ASLayoutElementSize)size
                 relativeToParentSize:(CGSize)parentSize {
  ASSizeRange styleAndParentSize = ASLayoutElementSizeResolve(self.style.size, parentSize);
  const ASSizeRange resolvedRange = ASSizeRangeIntersect(constrainedSize, styleAndParentSize);
  ASLayout *result = [self calculateLayoutThatFits:resolvedRange];
  
  return result;
}

- (BOOL)implementsLayoutMethod {
  return YES;
}

ASLayoutElementStyleExtensibilityForwarding

- (nonnull NSString *)asciiArtName {
  NSMutableString *result = [NSMutableString stringWithCString:object_getClassName(self) encoding:NSASCIIStringEncoding];
  if (self._debugName) {
    [result appendFormat:@" (%@)", self._debugName];
  }
  return result;
}

- (nonnull NSString *)asciiArtString {
  return [ASLayoutSpec asciiArtStringForChildren:@[] parentName:[self asciiArtName]];
}

@end

@implementation UIView (ASLayoutSpec)

- (ASUIViewLayoutSpecBlock)layoutSpecBlock
{
  return (ASUIViewLayoutSpecBlock)objc_getAssociatedObject(self, @selector(layoutSpecBlock));
}

- (void)setLayoutSpecBlock:(ASUIViewLayoutSpecBlock)layoutSpecBlock
{
  objc_setAssociatedObject(self, @selector(layoutSpecBlock), layoutSpecBlock, OBJC_ASSOCIATION_RETAIN);
}

ASDK_STYLE_PROP_PRIM(BOOL, automaticallyManageSubviews, setAutomaticallyManageSubviews, NO)

- (CGSize)calculatedSize
{
  if (self._pendingDisplayNodeLayout.isValid(self._layoutVersion)) {
    return self._pendingDisplayNodeLayout.layout.size;
  }
  return self._calculatedDisplayNodeLayout.layout.size;
}

- (ASLayoutSpec *)layoutSpecThatFits:(ASSizeRange)constrainedSize
{
  ASDisplayNodeAssert(NO, @"-[ASDisplayNode layoutSpecThatFits:] should never return an empty value. One way this is caused is by calling -[super layoutSpecThatFits:] which is not currently supported.");
  return [[ASLayoutSpec alloc] init];
}

- (ASLayout *)calculateLayoutLayoutSpec:(ASSizeRange)constrainedSize
{
  // Manual size calculation via calculateSizeThatFits:
  if (self.layoutSpecBlock == NULL && ASUIViewSubclassOverridesSelector(self.class, @selector(layoutSpecThatFits:)) == NO) {
    CGSize size = [self calculateSizeThatFits:constrainedSize.max];
    ASDisplayNodeLogEvent(self, @"calculatedSize: %@", NSStringFromCGSize(size));
    return [ASLayout layoutWithLayoutElement:self size:ASSizeRangeClamp(constrainedSize, size) sublayouts:nil];
  }
  
  // Get layout element from the node
  id<ASLayoutElement> layoutElement = [self layoutElementThatFits:constrainedSize];
  
  // Certain properties are necessary to set on an element of type ASLayoutSpec
  if (layoutElement.layoutElementType == ASLayoutElementTypeLayoutSpec) {
    ASLayoutSpec *layoutSpec = (ASLayoutSpec *)layoutElement;
    
#if AS_DEDUPE_LAYOUT_SPEC_TREE
    NSHashTable *duplicateElements = [layoutSpec findDuplicatedElementsInSubtree];
    if (duplicateElements.count > 0) {
      ASDisplayNodeFailAssert(@"Node %@ returned a layout spec that contains the same elements in multiple positions. Elements: %@", self, duplicateElements);
      // Use an empty layout spec to avoid crashes
      layoutSpec = [[ASLayoutSpec alloc] init];
    }
#endif
    
    ASDisplayNodeAssert(layoutSpec.isMutable, @"Node %@ returned layout spec %@ that has already been used. Layout specs should always be regenerated.", self, layoutSpec);
    
    layoutSpec.isMutable = NO;
  }
  
  // Manually propagate the trait collection here so that any layoutSpec children of layoutSpec will get a traitCollection
  {
    ASTraitCollectionPropagateDown(layoutElement, self.primitiveTraitCollection);
  }
  
  // Layout element layout creation
  ASLayout *layout = ({
    [layoutElement layoutThatFits:constrainedSize];
  });
  ASDisplayNodeAssertNotNil(layout, @"[ASLayoutElement layoutThatFits:] should never return nil! %@, %@", self, layout);
  
  // Make sure layoutElementObject of the root layout is `self`, so that the flattened layout will be structurally correct.
  BOOL isFinalLayoutElement = (layout.layoutElement != self);
  if (isFinalLayoutElement) {
    layout.position = CGPointZero;
    layout = [ASLayout layoutWithLayoutElement:self size:layout.size sublayouts:@[layout]];
  }
  ASDisplayNodeLogEvent(self, @"computedLayout: %@", layout);
  
  // PR #1157: Reduces accuracy of _unflattenedLayout for debugging/Weaver
  if ([ASDisplayNode shouldStoreUnflattenedLayouts]) {
    self._unflattenedLayout = layout;
  }
  layout = [layout filteredNodeLayoutTree];
  
  return layout;
}

- (id<ASLayoutElement>)layoutElementThatFits:(ASSizeRange)constrainedSize
{
  if (self.layoutSpecBlock != NULL) {
    return ({
      self.layoutSpecBlock(self, constrainedSize);
    });
  } else {
    return ({
      [self layoutSpecThatFits:constrainedSize];
    });
  }
}

@end

@interface UIView (Layout)

@end

@implementation UIView (Layout)

- (void)applyLayout {
  [self __layout];
}

- (void)__layout
{
  {
    if (CGRectEqualToRect(self.bounds, CGRectZero)) {
      // Performing layout on a zero-bounds view often results in frame calculations
      // with negative sizes after applying margins, which will cause
      // layoutThatFits: on subnodes to assert.
      as_log_debug(OS_LOG_DISABLED, "Warning: No size given for node before node was trying to layout itself: %@. Please provide a frame for the view.", self);
      return;
    }
    
    as_activity_create_for_scope("-[UIView __layout]");
  }
  
  [self _measureNodeWithBoundsIfNecessary];
  [self _layoutSublayouts];
}

- (void)_layoutSublayouts
{
  ASLayout *layout;
  {
    if (self._calculatedDisplayNodeLayout.version < self._layoutVersion) {
      return;
    }
    layout = self._calculatedDisplayNodeLayout.layout;
  }
  
  for (UIView *view in self.subviews) {
    CGRect frame = [layout frameForElement:view];
    if (CGRectIsNull(frame)) {
      // There is no frame for this node in our layout.
      // This currently can happen if we get a CA layout pass
      // while waiting for the client to run animateLayoutTransition:
    } else {
      view.frame = frame;
    }
  }
}

- (void)_measureNodeWithBoundsIfNecessary
{
  CGSize boundsSizeForLayout = ASCeilSizeValues(self.bounds.size);
  
  BOOL pendingLayoutIsPreferred = NO;
  if (self._pendingDisplayNodeLayout.isValid(self._layoutVersion)) {
    NSUInteger calculatedVersion = self._calculatedDisplayNodeLayout.version;
    NSUInteger pendingVersion = self._pendingDisplayNodeLayout.version;
    if (pendingVersion > calculatedVersion) {
      pendingLayoutIsPreferred = YES; // Newer _pending
    } else if (pendingVersion == calculatedVersion
               && !ASSizeRangeEqualToSizeRange(self._pendingDisplayNodeLayout.constrainedSize,
                                               self._calculatedDisplayNodeLayout.constrainedSize)) {
                 pendingLayoutIsPreferred = YES; // _pending with a different constrained size
               }
  }
  BOOL calculatedLayoutIsReusable = (self._calculatedDisplayNodeLayout.isValid(self._layoutVersion)
                                     && (self._calculatedDisplayNodeLayout.requestedLayoutFromAbove
                                         || CGSizeEqualToSize(self._calculatedDisplayNodeLayout.layout.size, boundsSizeForLayout)));
  if (!pendingLayoutIsPreferred && calculatedLayoutIsReusable) {
    return;
  }
  
  as_activity_create_for_scope("Update view layout for current bounds");
  as_log_verbose(ASLayoutLog(), "View %@, bounds size %@, calculatedSize %@, calculatedIsDirty %d",
                 self,
                 NSStringFromCGSize(boundsSizeForLayout),
                 NSStringFromCGSize(self._calculatedDisplayNodeLayout->layout.size),
                 self._calculatedDisplayNodeLayout->version < self._layoutVersion);
  // _calculatedDisplayNodeLayout is not reusable we need to transition to a new one
  
  BOOL didCreateNewContext = NO;
  ASLayoutElementContext *context = ASLayoutElementGetCurrentContext();
  if (context == nil) {
    context = [[ASLayoutElementContext alloc] init];
    ASLayoutElementPushContext(context);
    didCreateNewContext = YES;
  }
  
  // Figure out previous and pending layouts for layout transition
  ASDisplayNodeLayout nextLayout = self._pendingDisplayNodeLayout;
#define layoutSizeDifferentFromBounds !CGSizeEqualToSize(nextLayout.layout.size, boundsSizeForLayout)
  
  // nextLayout was likely created by a call to layoutThatFits:, check if it is valid and can be applied.
  // If our bounds size is different than it, or invalid, recalculate.  Use #define to avoid nullptr->
  BOOL pendingLayoutApplicable = NO;
  if (nextLayout.layout == nil) {
    as_log_verbose(ASLayoutLog(), "No pending layout.");
  } else if (!nextLayout.isValid(self._layoutVersion)) {
    as_log_verbose(ASLayoutLog(), "Pending layout is stale.");
  } else if (layoutSizeDifferentFromBounds) {
    as_log_verbose(ASLayoutLog(), "Pending layout size %@ doesn't match bounds size.", NSStringFromCGSize(nextLayout->layout.size));
  } else {
    as_log_verbose(ASLayoutLog(), "Using pending layout %@.", nextLayout->layout);
    pendingLayoutApplicable = YES;
  }
  
  if (!pendingLayoutApplicable) {
    as_log_verbose(ASLayoutLog(), "Measuring with previous constrained size.");
    // Use the last known constrainedSize passed from a parent during layout (if never, use bounds).
    NSUInteger version = self._layoutVersion;
    ASSizeRange constrainedSize = [self constrainedSizeForLayoutPass];
    ASLayout *layout = [self calculateLayoutThatFits:constrainedSize
                                    restrictedToSize:self.style.size
                                relativeToParentSize:boundsSizeForLayout];
    nextLayout = ASDisplayNodeLayout(layout, constrainedSize, boundsSizeForLayout, version);
    // Now that the constrained size of pending layout might have been reused, the layout is useless
    // Release it and any orphaned subnodes it retains
    ASDisplayNodeLayout displayNodeLayout = self._pendingDisplayNodeLayout;
    displayNodeLayout.layout = nil;
  }
  
  if (didCreateNewContext) {
    ASLayoutElementPopContext();
  }
  
  // If our new layout's desired size for self doesn't match current size, ask our parent to update it.
  // This can occur for either pre-calculated or newly-calculated layouts.
  if (nextLayout.requestedLayoutFromAbove == NO
      && CGSizeEqualToSize(boundsSizeForLayout, nextLayout.layout.size) == NO) {
    as_log_verbose(ASLayoutLog(), "Layout size doesn't match bounds size. Requesting layout from above.");
    // The layout that we have specifies that this node (self) would like to be a different size
    // than it currently is.  Because that size has been computed within the constrainedSize, we
    // expect that calling setNeedsLayoutFromAbove will result in our parent resizing us to this.
    // However, in some cases apps may manually interfere with this (setting a different bounds).
    // In this case, we need to detect that we've already asked to be resized to match this
    // particular ASLayout object, and shouldn't loop asking again unless we have a different ASLayout.
    nextLayout.requestedLayoutFromAbove = YES;
    
    {
      [self setNeedsLayoutFromAbove];
    }
    
    // Update the layout's version here because _u_setNeedsLayoutFromAbove calls __setNeedsLayout which in turn increases _layoutVersion
    // Failing to do this will cause the layout to be invalid immediately
    nextLayout.version = self._layoutVersion;
  }
  
  // Prepare to transition to nextLayout
  ASDisplayNodeAssertNotNil(nextLayout.layout, @"nextLayout->layout should not be nil! %@", self);
  ASLayoutTransition *layoutTransition = [[ASLayoutTransition alloc] initWithNode:(ASDisplayNode *)self
                                                                    pendingLayout:nextLayout
                                                                   previousLayout:self._calculatedDisplayNodeLayout];
  
  if (layoutTransition) {
    self._calculatedDisplayNodeLayout = layoutTransition.pendingLayout;
    [self _completeLayoutTransition:layoutTransition];
    [self calculateLayoutDidChange];
  }
}

- (void)_completeLayoutTransition:(ASLayoutTransition *)layoutTransition
{
  // Layout transition is not supported for nodes that do not have automatic subnode management enabled
  if (layoutTransition == nil || self.automaticallyManageSubviews == NO) {
    return;
  }
  
  [layoutTransition commitTransition];
}

- (void)calculateLayoutDidChange
{
  
}

- (ASSizeRange)constrainedSizeForLayoutPass
{
  // TODO: The logic in -_u_setNeedsLayoutFromAbove seems correct and doesn't use this method.
  // logic seems correct.  For what case does -this method need to do the CGSizeEqual checks?
  // IF WE CAN REMOVE BOUNDS CHECKS HERE, THEN WE CAN ALSO REMOVE "REQUESTED FROM ABOVE" CHECK
  
  CGSize boundsSizeForLayout = ASCeilSizeValues(self.bounds.size);
  
  // Checkout if constrained size of pending or calculated display node layout can be used
  if (self._pendingDisplayNodeLayout.requestedLayoutFromAbove
      || CGSizeEqualToSize(self._pendingDisplayNodeLayout.layout.size, boundsSizeForLayout)) {
    // We assume the size from the last returned layoutThatFits: layout was applied so use the pending display node
    // layout constrained size
    return self._pendingDisplayNodeLayout.constrainedSize;
  } else if (self._calculatedDisplayNodeLayout.layout != nil
             && (self._calculatedDisplayNodeLayout.requestedLayoutFromAbove
                 || CGSizeEqualToSize(self._calculatedDisplayNodeLayout.layout.size, boundsSizeForLayout))) {
               // We assume the  _calculatedDisplayNodeLayout is still valid and the frame is not different
               return self._calculatedDisplayNodeLayout.constrainedSize;
             } else {
               // In this case neither the _pendingDisplayNodeLayout or the _calculatedDisplayNodeLayout constrained size can
               // be reused, so the current bounds is used. This is usual the case if a frame was set manually that differs to
               // the one returned from layoutThatFits: or layoutThatFits: was never called
               return ASSizeRangeMake(boundsSizeForLayout);
             }
}

- (void)setNeedsLayoutFromAbove
{
  as_activity_create_for_scope("Set needs layout from above");
  
  // Mark the node for layout in the next layout pass
  [self setNeedsLayout];
  
  // Escalate to the root; entire tree must allow adjustments so the layout fits the new child.
  // Much of the layout will be re-used as cached (e.g. other items in an unconstrained stack)
  UIView *superview = self.superview;
  
  if (superview) {
    // Threading model requires that we unlock before calling a method on our parent.
    [superview setNeedsLayoutFromAbove];
  } else {
    // Let the root node method know that the size was invalidated
    [self _rootViewDidInvalidateSize];
  }
}

- (void)_rootViewDidInvalidateSize
{
  // We are the root node and need to re-flow the layout; at least one child needs a new size.
  CGSize boundsSizeForLayout = ASCeilSizeValues(self.bounds.size);
  
  // Figure out constrainedSize to use
  ASSizeRange constrainedSize = ASSizeRangeMake(boundsSizeForLayout);
  if (self._pendingDisplayNodeLayout.layout != nil) {
    constrainedSize = self._pendingDisplayNodeLayout.constrainedSize;
  } else if (self._calculatedDisplayNodeLayout.layout != nil) {
    constrainedSize = self._calculatedDisplayNodeLayout.constrainedSize;
  }
  
  // Perform a measurement pass to get the full tree layout, adapting to the child's new size.
  ASLayout *layout = [self layoutThatFits:constrainedSize];
  
  // Check if the returned layout has a different size than our current bounds.
  if (CGSizeEqualToSize(boundsSizeForLayout, layout.size) == NO) {
    // If so, inform our container we need an update (e.g Table, Collection, ViewController, etc).
    [self displayViewDidInvalidateSizeNewSize:layout.size];
  }
}

- (void)displayViewDidInvalidateSizeNewSize:(CGSize)size
{
  // The default implementation of display node changes the size of itself to the new size
  CGRect oldBounds = self.bounds;
  CGSize oldSize = oldBounds.size;
  CGSize newSize = size;
  
  if (! CGSizeEqualToSize(oldSize, newSize)) {
    self.bounds = (CGRect){ oldBounds.origin, newSize };
    
    // Frame's origin must be preserved. Since it is computed from bounds size, anchorPoint
    // and position (see frame setter in ASDisplayNode+UIViewBridge), position needs to be adjusted.
    CGPoint anchorPoint = self.layer.anchorPoint;
    CGPoint oldPosition = self.layer.position;
    CGFloat xDelta = (newSize.width - oldSize.width) * anchorPoint.x;
    CGFloat yDelta = (newSize.height - oldSize.height) * anchorPoint.y;
    self.layer.position = CGPointMake(oldPosition.x + xDelta, oldPosition.y + yDelta);
  }
}

@end

@implementation ASView

- (void)layoutSubviews {
  [super layoutSubviews];
  
  [self __layout];
}
@end

