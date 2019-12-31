//
//  ASCollectionElement.mm
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import <AsyncDisplayKit/ASCollectionElement.h>
#import <AsyncDisplayKit/ASCellNode+Internal.h>
#import <AsyncDisplayKit/ASDisplayNodeExtras.h>
#import <mutex>
#import <AsyncDisplayKit/ASInternalHelpers.h>
#import <AsyncDisplayKit/ASDisplayNode+FrameworkPrivate.h>
#import <AsyncDisplayKit/ASLayout.h>

@interface ASCollectionElementPendingState: NSObject
@property (atomic) ASInterfaceState nodeInterfaceState;
@end

@implementation ASCollectionElementPendingState

- (instancetype)init {
    self = [super init];
    if (self) {
        self.nodeInterfaceState = ASInterfaceStateNone;
    }
    
    return self;
}

@end

@interface ASCollectionElement ()

/// Required node block used to allocate a cell node. Nil after the first execution.
@property (nonatomic) ASCellNodeBlock nodeBlock;

@property (atomic) ASCollectionElementPendingState * pendingState;

@property (atomic) BOOL alocatingNode;

@end

@implementation ASCollectionElement {
  std::mutex _lockNode;
    std::mutex _lockCallBackBlock;
    std::mutex _lockCommonProperty;
  ASCellNode *_node;
    CGSize _calculatedSize;
    BOOL _markNeedAllocate;
    BOOL _markNeedDeallocate;
    BOOL _shouldUseUIKitCell;
    
    BlockCallBack_t _allocNodeBlockCallBack;
}

- (instancetype)initWithNodeModel:(id)nodeModel
                        nodeBlock:(ASCellNodeBlock)nodeBlock
         supplementaryElementKind:(NSString *)supplementaryElementKind
                  constrainedSize:(ASSizeRange)constrainedSize
                       owningNode:(id<ASRangeManagingNode>)owningNode
                  traitCollection:(ASPrimitiveTraitCollection)traitCollection
{
  NSAssert(nodeBlock != nil, @"Node block must not be nil");
  self = [super init];
  if (self) {
    _nodeModel = nodeModel;
    _nodeBlock = nodeBlock;
    _supplementaryElementKind = [supplementaryElementKind copy];
    _constrainedSize = constrainedSize;
    _owningNode = owningNode;
    _traitCollection = traitCollection;
      _calculatedSize = CGSizeZero;
      _markNeedAllocate = YES;
      _markNeedDeallocate = NO;
      _shouldUseUIKitCell = NO;
      _alocatingNode = NO;
  }
  return self;
}

- (void)dealloc {
    [self removeNode];
    _nodeBlock = nil;
}

- (ASCellNode *)node
{
    std::lock_guard<std::mutex> l(_lockNode);
    if (_nodeBlock != nil && _node == nil) {
        
        _alocatingNode = YES;
        
        ASCellNode *node = _nodeBlock();
        if (node == nil) {
            ASDisplayNodeFailAssert(@"Node block returned nil node!");
            node = [[ASCellNode alloc] init];
        }
        node.owningNode = _owningNode;
        node.collectionElement = self;
        ASTraitCollectionPropagateDown(node, _traitCollection);
        node.nodeModel = _nodeModel;
        _node = node;
        
        [self addObserver];
        [self setMarkNeedAllocate:NO];
        
        if (_markNeedDeallocate) {
            self.pendingState = nil;
        } else if (_pendingState) {
            ASPerformBlockOnMainThread(^{
                [_node recursivelySetInterfaceState:_pendingState.nodeInterfaceState];
                self.pendingState = nil;
            });
        }
        
        _alocatingNode = NO;
    }
    
    [self executeCallBackBlock];
    
    return _node;
}

- (ASCellNode *)nodeIfAllocated
{
  std::lock_guard<std::mutex> l(_lockNode);
  return _node;
}

- (void)layoutNodeWithConstrainedSize:(ASSizeRange)constrainedSize {
    ASDisplayNodeAssert(ASSizeRangeHasSignificantArea(constrainedSize), @"Attempt to layout cell node with invalid size range %@", NSStringFromASSizeRange(constrainedSize));
    std::lock_guard<std::mutex> l(_lockNode);
    if (_node) {
        CGRect frame = CGRectZero;
        frame.size = [_node layoutThatFits:constrainedSize].size;
        _node.frame = frame;
        
        if (_node.frame.size.width == 0) {
            NSLog(@"gdfgdg");
        }
        
        _calculatedSize = _node.calculatedSize;
    }
}

- (void)setTraitCollection:(ASPrimitiveTraitCollection)traitCollection
{
  ASCellNode *nodeIfNeedsPropagation;
  
  {
    std::lock_guard<std::mutex> l(_lockNode);
    if (! ASPrimitiveTraitCollectionIsEqualToASPrimitiveTraitCollection(_traitCollection, traitCollection)) {
      _traitCollection = traitCollection;
      nodeIfNeedsPropagation = _node;
    }
  }
  
  if (nodeIfNeedsPropagation != nil) {
    ASTraitCollectionPropagateDown(nodeIfNeedsPropagation, traitCollection);
  }
}

- (ASInterfaceState)nodeInterfaceState {
    ASDisplayNodeAssertMainThread();
    if (_node) {
        return _node.interfaceState;
    } else {
        if (self.pendingState) {
            return self.pendingState.nodeInterfaceState;
        }
    }
    return ASInterfaceStateNone;
}

- (void)setNodeInterfaceState:(ASInterfaceState)nodeInterfaceState {
    ASDisplayNodeAssertMainThread();
    ASDisplayNodeAssertFalse(ASInterfaceStateIncludesVisible(nodeInterfaceState) && !ASInterfaceStateIncludesDisplay(nodeInterfaceState));

    if (_node) {
        [_node recursivelySetInterfaceState:nodeInterfaceState];
    } else {
        if (_pendingState == nil) {
            _pendingState = [ASCollectionElementPendingState new];
        }
        _pendingState.nodeInterfaceState = nodeInterfaceState;
    }
}

- (void)exitInterfaceState:(ASInterfaceState)nodeInterfaceState
{
    ASDisplayNodeAssertMainThread();
    
    if (nodeInterfaceState == ASInterfaceStateNone) {
        return; // This method is a no-op with a 0-bitfield argument, so don't bother recursing.
    }
    
    if (_node) {
        [_node exitInterfaceState:nodeInterfaceState];
    } else {
        if (self.pendingState == nil) {
            self.pendingState = [ASCollectionElementPendingState new];
        }
        self.pendingState.nodeInterfaceState &= (~nodeInterfaceState);
    }
}

- (void)setMarkNeedAllocate:(BOOL)markNeedAllocate {
    _markNeedAllocate = markNeedAllocate;
}

- (BOOL)markNeedAllocate {
    return _markNeedAllocate;
}

- (BOOL)markNeedDeallocate {
    return _markNeedDeallocate;
}

- (void)setMarkNeedDeallocate:(BOOL)markNeedDeallocate {
    _markNeedDeallocate = markNeedDeallocate;
}

- (void)setShouldUseUIKitCell:(BOOL)shouldUseUIKitCell {
    _shouldUseUIKitCell = shouldUseUIKitCell;
}

- (BOOL)shouldUseUIKitCell {
    return _shouldUseUIKitCell;
}

- (void)setCalculatedSize:(CGSize)calculatedSize {
    std::lock_guard<std::mutex> l(_lockCommonProperty);
    _calculatedSize = calculatedSize;
}

- (CGSize)calculatedSize {
    std::lock_guard<std::mutex> l(_lockCommonProperty);
    return _calculatedSize;
}

- (void)executeCallBackBlock {
    std::lock_guard<std::mutex> l(_lockCallBackBlock);
    if (_allocNodeBlockCallBack) {
        __weak ASCollectionElement * weakSelf = self;
        _allocNodeBlockCallBack(weakSelf);
        _allocNodeBlockCallBack = nil;
    }
}

- (void)setAllocNodeBlockCallBack:(BlockCallBack_t)allocNodeBlockCallBack {
    {
        std::lock_guard<std::mutex> l(_lockCallBackBlock);
        _allocNodeBlockCallBack = [allocNodeBlockCallBack copy];
    }
    
    if (self.nodeIfAllocated) {
        [self executeCallBackBlock];
    }
}

- (BlockCallBack_t)allocNodeBlockCallBack {
    std::lock_guard<std::mutex> l(_lockCallBackBlock);
    return _allocNodeBlockCallBack;
}

- (void)removeNode {
    std::lock_guard<std::mutex> l(_lockNode);
    if (_node) {
        // Weird enough that we don't know why node is still in visible range
        // FIXME: Find the cause of this issue
        // INFO: Maybe after the node creation complete and then pendingState set visibleState
        // of node to 'visible' and then element try to remove this node
        if (ASInterfaceStateIncludesVisible(_node.interfaceState)) {
            
            NSLog(@"Try to remove node when node interfaceState is visible");
            
            // Temporary we ignore this issue
//                ASPerformBlockOnMainThread(^{
//                    _markNeedAllocate = NO;
//                    _markNeedDeallocate = NO;
//                    _pendingState = nil;
//                    [self removeObserver];
//
//                    [_node exitInterfaceState:ASInterfaceStateVisible];
//                    _node = nil;
//                });
        } else {
            ASDisplayNodeAssert(!ASInterfaceStateIncludesVisible(_node.interfaceState), @"Node should always be marked invisible before deallocatingxx. Node: %@", _node);
            
            _markNeedAllocate = NO;
            _markNeedDeallocate = NO;
            self.pendingState = nil;
            [self removeObserver];
            _node = nil;
        }
    }
}

- (void)addObserver {
    [_node addObserver:self forKeyPath:@"frame" options:0 context:nil];
    [_node addObserver:self forKeyPath:@"shouldUseUIKitCell" options:0 context:nil];
}

- (void)removeObserver {
    @try {
        [_node removeObserver:self forKeyPath:@"frame"];
        [_node removeObserver:self forKeyPath:@"shouldUseUIKitCell"];
    } @catch (NSException *exception) {
        NSLog(@"%@", [exception description]);
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath compare:@"frame"] == NSOrderedSame) {
        ASCellNode * node = object;
        ASPerformBlockOnMainThread(^{
            [self setCalculatedSize:node.frame.size];
        });
    } else if ([keyPath compare:@"shouldUseUIKitCell"] == NSOrderedSame) {
        ASCellNode * node = object;
        ASPerformBlockOnMainThread(^{
            [self setShouldUseUIKitCell:node.shouldUseUIKitCell];
        });
    }
}

@end
