//
//  ASLayoutMappingElement.m
//  AsyncDisplayKit
//
//  Created by Dao Nguyen Van on 11/4/19.
//  Copyright © 2019 Pinterest. All rights reserved.
//

#import <AsyncDisplayKit/ASLayoutMappingElement.h>
#import <AsyncDisplayKit/ASThread.h>
#import <AsyncDisplayKit/ASLayoutElement.h>
#import <AsyncDisplayKit/ASDisplayNodeLayout.h>
#import <AsyncDisplayKit/ASLayoutSpec+Subclasses.h>
#import <AsyncDisplayKit/ASLayoutSpecPrivate.h>
#import <AsyncDisplayKit/ASDimensionInternal.h>
#import <AsyncDisplayKit/ASDisplayNode.h>
#import <AsyncDisplayKit/ASDisplayNode+Beta.h>
#import <AsyncDisplayKit/ASLayoutElementStylePrivate.h>
#import <AsyncDisplayKit/ASLog.h>

BOOL ASMappingElementSubclassOverridesSelector(Class subclass, SEL selector)
{
  return ASSubclassOverridesSelector([ASLayoutMappingElement class], subclass, selector);
}

@interface ASLayoutMappingElement()
{
  @package
  ASDN::RecursiveMutex __instanceLock__;
  
  NSMutableArray<id<ASLayoutElement>> *_subElements;
  std::atomic<ASPrimitiveTraitCollection> _primitiveTraitCollection;

  // Layout support
  ASMappingElementLayoutSpecBlock _layoutSpecBlock;

  ASLayoutElementStyle *_style;
  
  ASDisplayNodeLayout _calculatedDisplayNodeLayout;
  std::atomic<NSUInteger> _layoutVersion;
  
  ASLayout *_unflattenedLayout;
  NSString *_debugName;
}

@property (nonatomic, copy) ASMappingElementBlock mappingElementBlock;

@end

@implementation ASLayoutMappingElement

#pragma mark - Initial

- (instancetype)initWithMappingKey:(ASMappingKey)mappingKey
{
  self = [super init];
  if (self)
  {
    _mappingKey = mappingKey;
    _subElements = [[NSMutableArray alloc] init];
  }
  return self;
}

- (instancetype)initWithMappingKey:(ASMappingKey)mappingKey
               mappingElementBlock:(ASMappingElementBlock)mappingElementBlock
{
  self = [self initWithMappingKey:mappingKey];
  if (self) {
    _mappingElementBlock = mappingElementBlock;
  }
  return self;
}

+ (instancetype)mappingElementWithKey:(ASMappingKey)mappingKey
{
  return [[self alloc] initWithMappingKey:mappingKey];
}

+ (instancetype)mappingElementWithKey:(ASMappingKey)mappingKey mappingElementBlock:(ASMappingElementBlock)mappingElementBlock
{
  return [[self alloc] initWithMappingKey:mappingKey mappingElementBlock:mappingElementBlock];
}

#pragma mark - ASLayoutElement Protocol

- (ASLayoutElementType)layoutElementType {
  return ASLayoutElementTypeMappingElement;
}

- (id<ASDisplayElement>)displayElement {
  if (self.mappingElementBlock) {
    return self.mappingElementBlock(self.mappingKey);
  }
  return nil;
}

ASPrimitiveTraitCollectionDefaults

- (ASTraitCollection *)asyncTraitCollection {
  return [ASTraitCollection traitCollectionWithASPrimitiveTraitCollection:self.primitiveTraitCollection];
}

- (NSArray<id<ASLayoutElement>> *)sublayoutElements {
  return _subElements;
}

#pragma mark - ASLayoutElementStyle

- (ASLayoutElementStyle *)style {
  ASDN::MutexLocker l(__instanceLock__);
  return [self _locked_style];
}

- (ASLayoutElementStyle *)_locked_style
{
  DISABLED_ASAssertLocked(__instanceLock__);
  if (_style == nil) {
    _style = [[ASLayoutElementStyle alloc] init];
  }
  return _style;
}

#pragma mark - Calculate layout

- (ASLayoutEngineType)layoutEngineType
{
#if YOGA
  ASDN::MutexLocker l(__instanceLock__);
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
  ASDN::MutexLocker l(__instanceLock__);
  
  ASLayout *layout = nil;
  NSUInteger version = _layoutVersion;
  if (_calculatedDisplayNodeLayout.isValid(constrainedSize, parentSize, version)) {
    ASDisplayNodeAssertNotNil(_calculatedDisplayNodeLayout.layout, @"-[ASDisplayNode layoutThatFits:parentSize:] _calculatedDisplayNodeLayout.layout should not be nil! %@", self);
    layout = _calculatedDisplayNodeLayout.layout;
  } else {
    // Create a pending display node layout for the layout pass
    layout = [self calculateLayoutThatFits:constrainedSize
                          restrictedToSize:self.style.size
                      relativeToParentSize:parentSize];
    as_log_verbose(ASLayoutLog(), "Established pending layout for %@ in %s", self, sel_getName(_cmd));
    _calculatedDisplayNodeLayout = ASDisplayNodeLayout(layout, constrainedSize, parentSize,version);
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
  if (_debugName) {
    [result appendFormat:@" (%@)", _debugName];
  }
  return result;
}

- (nonnull NSString *)asciiArtString {
  return [ASLayoutSpec asciiArtStringForChildren:@[] parentName:[self asciiArtName]];
}

ASSynthesizeLockingMethodsWithMutex(__instanceLock__)

@end


@implementation ASLayoutMappingElement (ASLayoutSpec)

- (ASMappingElementLayoutSpecBlock)layoutSpecBlock
{
  ASDN::MutexLocker l(__instanceLock__);
  return _layoutSpecBlock;
}

- (void)setLayoutSpecBlock:(ASMappingElementLayoutSpecBlock)layoutSpecBlock
{
  ASDN::MutexLocker l(__instanceLock__);
  _layoutSpecBlock = layoutSpecBlock;
}

- (ASLayoutSpec *)layoutSpecThatFits:(ASSizeRange)constrainedSize
{
  ASDisplayNodeAssert(NO, @"-[ASDisplayNode layoutSpecThatFits:] should never return an empty value. One way this is caused is by calling -[super layoutSpecThatFits:] which is not currently supported.");
  return [[ASLayoutSpec alloc] init];
}

- (ASLayout *)calculateLayoutLayoutSpec:(ASSizeRange)constrainedSize
{
  ASDN::UniqueLock l(__instanceLock__);
  
  // Manual size calculation via calculateSizeThatFits:
  if (_layoutSpecBlock == NULL && ASMappingElementSubclassOverridesSelector(self.class, @selector(layoutSpecThatFits:)) == NO) {
    CGSize size = [self calculateSizeThatFits:constrainedSize.max];
    ASDisplayNodeLogEvent(self, @"calculatedSize: %@", NSStringFromCGSize(size));
    return [ASLayout layoutWithLayoutElement:self size:ASSizeRangeClamp(constrainedSize, size) sublayouts:nil];
  }
  
  // Get layout element from the node
  id<ASLayoutElement> layoutElement = [self _locked_layoutElementThatFits:constrainedSize];
  
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
    _unflattenedLayout = layout;
  }
  layout = [layout filteredNodeLayoutTree];
  
  return layout;
}

- (id<ASLayoutElement>)_locked_layoutElementThatFits:(ASSizeRange)constrainedSize
{
  DISABLED_ASAssertLocked(__instanceLock__);
  
  if (_layoutSpecBlock != NULL) {
    return ({
      ASDN::MutexLocker l(__instanceLock__);
      _layoutSpecBlock(self, constrainedSize);
    });
  } else {
    return ({
      [self layoutSpecThatFits:constrainedSize];
    });
  }
}

@end


@implementation ASLayout (MappingElement)

- (void)mappingWithBlock:(ASMappingElementBlock)mappingBlock {
  NSMutableArray *stack = [NSMutableArray arrayWithObject:self];
  
  while (stack.count > 0) {
    ASLayout *layout = stack.lastObject;
    [stack removeLastObject];
    
    id<ASLayoutElement> layoutElement = layout.layoutElement;
    if (layoutElement.layoutElementType == ASLayoutElementTypeMappingElement) {
      [(ASLayoutMappingElement *)layoutElement setMappingElementBlock:mappingBlock];
    }
    
    if (layout.sublayouts && layout.sublayouts.count > 0) {
      [stack addObjectsFromArray:layout.sublayouts];
    }
  }
}

@end
