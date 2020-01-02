//
//  ASCollectionFlowLayoutItem.m
//  AGEmojiKeyboard
//
//  Created by CPU11815 on 8/9/17.
//

#import "_ASCollectionFlowLayoutItem.h"

#import <AsyncDisplayKit/ASCollectionElement.h>
#import <AsyncDisplayKit/ASLayout.h>
#import <AsyncDisplayKit/ASLayoutElementPrivate.h>
#import <AsyncDisplayKit/ASLayoutElementStylePrivate.h>
#import <AsyncDisplayKit/ASLayoutSpec.h>
#import <AsyncDisplayKit/ASCellNode.h>

@implementation _ASFlowLayoutItem {
    std::atomic<ASPrimitiveTraitCollection> _primitiveTraitCollection;
}

@synthesize style;

- (instancetype)initWithCollectionElement:(ASCollectionElement *)collectionElement {
    self = [super init];
    if (self) {
        ASDisplayNodeAssertNotNil(collectionElement, @"Collection element should not be nil");
        _collectionElement = collectionElement;
    }
    return self;
}

ASLayoutElementStyleExtensibilityForwarding
ASPrimitiveTraitCollectionDefaults

- (ASTraitCollection *)asyncTraitCollection
{
    ASDisplayNodeAssertNotSupported();
    return nil;
}

- (ASLayoutElementType)layoutElementType
{
    return ASLayoutElementTypeLayoutSpec;
}

- (NSArray<id<ASLayoutElement>> *)sublayoutElements
{
    ASDisplayNodeAssertNotSupported();
    return nil;
}

- (BOOL)implementsLayoutMethod
{
    return YES;
}

ASLayoutElementLayoutCalculationDefaults

- (ASLayout *)calculateLayoutThatFits:(ASSizeRange)constrainedSize
{
    CGSize size = _collectionElement.calculatedSize;
    if (_collectionElement.nodeIfAllocated) {
        // Case node not layout-ed yet!
        if (! CGSizeEqualToSize(CGSizeZero, _collectionElement.nodeIfAllocated.calculatedSize)) {
            size = _collectionElement.nodeIfAllocated.calculatedSize;
        }
    } else if (CGSizeEqualToSize(CGSizeZero, _collectionElement.calculatedSize) && _collectionElement.nodeIfAllocated == nil) {
        ASCellNode * node = _collectionElement.node;
        
        CGRect frame = CGRectZero;
        frame.size = [node layoutThatFits:_collectionElement.constrainedSize].size;
        node.frame = frame;
        
        _collectionElement.calculatedSize = node.calculatedSize;
        size = _collectionElement.nodeIfAllocated.calculatedSize;
    }
    
    ASDisplayNodeAssert(CGSizeEqualToSize(size, ASSizeRangeClamp(constrainedSize, size)),
                        @"Item size %@ can't fit within the bounds of constrained size %@", NSStringFromCGSize(size), NSStringFromASSizeRange(constrainedSize));
    return [ASLayout layoutWithLayoutElement:self size:size];
}

#pragma mark - ASLayoutElementAsciiArtProtocol

- (NSString *)asciiArtString
{
    return [ASLayoutSpec asciiArtStringForChildren:@[] parentName:[self asciiArtName]];
}

- (NSString *)asciiArtName
{
    return [NSMutableString stringWithCString:object_getClassName(self) encoding:NSASCIIStringEncoding];
}

@end
