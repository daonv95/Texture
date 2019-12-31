//
//  ASCollectionElement.h
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import <AsyncDisplayKit/ASDataController.h>
#import <AsyncDisplayKit/ASTraitCollection.h>
#import <AsyncDisplayKit/ASCellNode.h>

typedef void (^BlockCallBack_t)(ASCollectionElement * _Nonnull);

@class ASDisplayNode;
@protocol ASRangeManagingNode;

NS_ASSUME_NONNULL_BEGIN

AS_SUBCLASSING_RESTRICTED
@interface ASCollectionElement : NSObject

@property (nullable, nonatomic, copy, readonly) NSString *supplementaryElementKind;
@property (nonatomic) ASSizeRange constrainedSize;
@property (nonatomic, weak, readonly) id<ASRangeManagingNode> owningNode;
@property (nonatomic) ASPrimitiveTraitCollection traitCollection;
@property (nullable, nonatomic, readonly) id nodeModel;
@property (nonatomic, assign) CGSize calculatedSize;
@property (nonatomic, assign) BOOL shouldUseUIKitCell;
@property (nonatomic, assign) BOOL markNeedAllocate;
@property (nonatomic, assign) BOOL markNeedDeallocate;
@property (atomic, copy, nullable) BlockCallBack_t allocNodeBlockCallBack;
@property (nonatomic, assign) ASInterfaceState nodeInterfaceState;

- (instancetype)initWithNodeModel:(nullable id)nodeModel
                        nodeBlock:(ASCellNodeBlock)nodeBlock
         supplementaryElementKind:(nullable NSString *)supplementaryElementKind
                  constrainedSize:(ASSizeRange)constrainedSize
                       owningNode:(id<ASRangeManagingNode>)owningNode
                  traitCollection:(ASPrimitiveTraitCollection)traitCollection;

/**
 * @return The node, running the node block if necessary. The node block will be discarded
 * after the first time it is run.
 */
@property (readonly) ASCellNode *node;

/**
 * @return The node, if the node block has been run already.
 */
@property (nullable, readonly) ASCellNode *nodeIfAllocated;

- (void)exitInterfaceState:(ASInterfaceState)nodeInterfaceState;

- (void)removeNode;

/**
 * Measure and layout the cellNode in element with the constrained size range.
 */
- (void)layoutNodeWithConstrainedSize:(ASSizeRange)constrainedSize;

@end

NS_ASSUME_NONNULL_END
