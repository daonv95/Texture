//
//  ASDataController.mm
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import <AsyncDisplayKit/ASDataController.h>

#include <atomic>

#import <AsyncDisplayKit/_ASHierarchyChangeSet.h>
#import <AsyncDisplayKit/_ASScopeTimer.h>
#import <AsyncDisplayKit/ASAssert.h>
#import <AsyncDisplayKit/ASCellNode.h>
#import <AsyncDisplayKit/ASCollectionElement.h>
#import <AsyncDisplayKit/ASCollectionLayoutContext.h>
#import <AsyncDisplayKit/ASCollectionLayoutState.h>
#import <AsyncDisplayKit/ASDispatch.h>
#import <AsyncDisplayKit/ASDisplayNodeExtras.h>
#import <AsyncDisplayKit/ASElementMap.h>
#import <AsyncDisplayKit/ASLayout.h>
#import <AsyncDisplayKit/ASLog.h>
#import <AsyncDisplayKit/ASSignpost.h>
#import <AsyncDisplayKit/ASMainSerialQueue.h>
#import <AsyncDisplayKit/ASMutableElementMap.h>
#import <AsyncDisplayKit/ASRangeManagingNode.h>
#import <AsyncDisplayKit/ASThread.h>
#import <AsyncDisplayKit/ASTwoDimensionalArrayUtils.h>
#import <AsyncDisplayKit/ASSection.h>

#import <AsyncDisplayKit/ASInternalHelpers.h>
#import <AsyncDisplayKit/ASCellNode+Internal.h>
#import <AsyncDisplayKit/ASDisplayNode+Subclasses.h>
#import <AsyncDisplayKit/NSIndexSet+ASHelpers.h>

#import "ASReallocOperation.h"

//#define LOG(...) NSLog(__VA_ARGS__)
#define LOG(...)

#define ASSERT_ON_EDITING_QUEUE ASDisplayNodeAssertNotNil(dispatch_get_specific(&kASDataControllerEditingQueueKey), @"%@ must be called on the editing transaction queue.", NSStringFromSelector(_cmd))

const static char * kASDataControllerEditingQueueKey = "kASDataControllerEditingQueueKey";
const static char * kASDataControllerEditingQueueContext = "kASDataControllerEditingQueueContext";

NSString * const ASDataControllerRowNodeKind = @"_ASDataControllerRowNodeKind";
NSString * const ASCollectionInvalidUpdateException = @"ASCollectionInvalidUpdateException";

typedef dispatch_block_t ASDataControllerCompletionBlock;

typedef void (^ASDataControllerSynchronizationBlock)();

@interface ASDataController () {
  id<ASDataControllerLayoutDelegate> _layoutDelegate;

  NSInteger _nextSectionID;
    NSUInteger _relayoutAllNodesTaskCount;
    
  BOOL _itemCountsFromDataSourceAreValid;     // Main thread only.
  std::vector<NSInteger> _itemCountsFromDataSource;         // Main thread only.
  
  ASMainSerialQueue *_mainSerialQueue;

  dispatch_queue_t _editingTransactionQueue;  // Serial background queue.  Dispatches concurrent layout and manages _editingNodes.
  dispatch_group_t _editingTransactionGroup;  // Group of all edit transaction blocks. Useful for waiting.
  std::atomic<int> _editingTransactionGroupCount;
    
    dispatch_queue_t _operationManagerQueue;
    dispatch_queue_t _edittingMaintainQueue;  // Serial background queue.
    dispatch_semaphore_t _regulationSemaphore;
    
  BOOL _initialReloadDataHasBeenCalled;

  BOOL _synchronized;
  NSMutableSet<ASDataControllerSynchronizationBlock> *_onDidFinishSynchronizingBlocks;

  struct {
    unsigned int supplementaryNodeKindsInSections:1;
    unsigned int supplementaryNodesOfKindInSection:1;
    unsigned int supplementaryNodeBlockOfKindAtIndexPath:1;
    unsigned int constrainedSizeForNodeAtIndexPath:1;
    unsigned int constrainedSizeForSupplementaryNodeOfKindAtIndexPath:1;
    unsigned int contextForSection:1;
  } _dataSourceFlags;
}

@property (copy) ASElementMap *pendingMap;
@property (copy) ASElementMap *visibleMap;

@property (nonatomic, readonly) NSOperationQueue *reallocOperationQueue;
@property (nonatomic, readonly) NSOperationQueue *relayoutOperationQueue;
@property (nonatomic, readonly) NSHashTable<NSOperation *> *normalReallocOperations;
@property (nonatomic, readonly) NSHashTable<NSOperation *> *normalRelayoutOperations;

@end

@implementation ASDataController

#pragma mark - Lifecycle

- (instancetype)initWithDataSource:(id<ASDataControllerSource>)dataSource node:(nullable id<ASRangeManagingNode>)node eventLog:(ASEventLog *)eventLog
{
  if (!(self = [super init])) {
    return nil;
  }
  
  _node = node;
  _dataSource = dataSource;
  
    _regulationSemaphore = dispatch_semaphore_create([NSProcessInfo processInfo].activeProcessorCount * 5);
    
  _dataSourceFlags.supplementaryNodeKindsInSections = [_dataSource respondsToSelector:@selector(dataController:supplementaryNodeKindsInSections:)];
  _dataSourceFlags.supplementaryNodesOfKindInSection = [_dataSource respondsToSelector:@selector(dataController:supplementaryNodesOfKind:inSection:)];
  _dataSourceFlags.supplementaryNodeBlockOfKindAtIndexPath = [_dataSource respondsToSelector:@selector(dataController:supplementaryNodeBlockOfKind:atIndexPath:shouldAsyncLayout:)];
  _dataSourceFlags.constrainedSizeForNodeAtIndexPath = [_dataSource respondsToSelector:@selector(dataController:constrainedSizeForNodeAtIndexPath:)];
  _dataSourceFlags.constrainedSizeForSupplementaryNodeOfKindAtIndexPath = [_dataSource respondsToSelector:@selector(dataController:constrainedSizeForSupplementaryNodeOfKind:atIndexPath:)];
  _dataSourceFlags.contextForSection = [_dataSource respondsToSelector:@selector(dataController:contextForSection:)];
  
#if ASEVENTLOG_ENABLE
  _eventLog = eventLog;
#endif

  self.visibleMap = self.pendingMap = [[ASElementMap alloc] init];
  
  _nextSectionID = 0;
  
    _relayoutAllNodesTaskCount = 0;
    
  _mainSerialQueue = [[ASMainSerialQueue alloc] init];

  _synchronized = YES;
  _onDidFinishSynchronizingBlocks = [[NSMutableSet alloc] init];
  
  const char *queueName = [[NSString stringWithFormat:@"org.AsyncDisplayKit.ASDataController.editingTransactionQueue:%p", self] cStringUsingEncoding:NSASCIIStringEncoding];
  _editingTransactionQueue = dispatch_queue_create(queueName, DISPATCH_QUEUE_SERIAL);
  dispatch_queue_set_specific(_editingTransactionQueue, &kASDataControllerEditingQueueKey, &kASDataControllerEditingQueueContext, NULL);
  _editingTransactionGroup = dispatch_group_create();
    
    const char *maintainQueueName = [[NSString stringWithFormat:@"com.VNG.ASDataController.edittingTransactionQueue:%p", self] cStringUsingEncoding:NSASCIIStringEncoding];
    _edittingMaintainQueue = dispatch_queue_create(maintainQueueName, DISPATCH_QUEUE_SERIAL);
    
    const char *operationManagerQueue = [[NSString stringWithFormat:@"com.VNG.ASDataController.operationManagerQueue:%p", self] cStringUsingEncoding:NSASCIIStringEncoding];
    _operationManagerQueue = dispatch_queue_create(operationManagerQueue, DISPATCH_QUEUE_CONCURRENT);
    
    _reallocOperationQueue = [[NSOperationQueue alloc] init];
    _reallocOperationQueue.maxConcurrentOperationCount = 10;
    _reallocOperationQueue.qualityOfService = NSQualityOfServiceUtility;
    
    _relayoutOperationQueue = [[NSOperationQueue alloc] init];
    _relayoutOperationQueue.maxConcurrentOperationCount = 1; // Serial execute
    _relayoutOperationQueue.qualityOfService = NSQualityOfServiceUtility;
    
    _normalReallocOperations = [[NSHashTable alloc] init];
    _normalRelayoutOperations = [[NSHashTable alloc] init];
    
  return self;
}

- (id<ASDataControllerLayoutDelegate>)layoutDelegate
{
  ASDisplayNodeAssertMainThread();
  return _layoutDelegate;
}

- (void)setLayoutDelegate:(id<ASDataControllerLayoutDelegate>)layoutDelegate
{
  ASDisplayNodeAssertMainThread();
  if (layoutDelegate != _layoutDelegate) {
    _layoutDelegate = layoutDelegate;
  }
}

- (NSUInteger)relayoutAllNodesTaskCount {
    ASDisplayNodeAssertMainThread();
    return _relayoutAllNodesTaskCount;
}

- (void)setRelayoutAllNodesTaskCount:(NSUInteger)relayoutAllNodesTaskCount {
    ASDisplayNodeAssertMainThread();
    if( _relayoutAllNodesTaskCount != relayoutAllNodesTaskCount) {
        _relayoutAllNodesTaskCount = relayoutAllNodesTaskCount;
    }
}

- (void)dealloc {
    // Cancel relayoutOperation
    for (NSBlockOperation *operation in self.normalRelayoutOperations) {
        [operation cancel];
    }
    [self.normalRelayoutOperations removeAllObjects];
    
    // Cancel reallocOperation
    for (ASReallocOperation *operation in self.normalReallocOperations) {
        [operation cancel];
    }
    [self.normalReallocOperations removeAllObjects];
}

#pragma mark - Cell Layout

- (void)_allocateNodesFromElements:(NSArray<ASCollectionElement *> *)elements {
    
    ASSERT_ON_EDITING_QUEUE;
    
    [self _allocateNodesFromElements:elements deleteNodeIfOutOfMaintainRange:NO];
}

- (void)_allocateNodesFromElements:(NSArray<ASCollectionElement *> *)elements deleteNodeIfOutOfMaintainRange:(BOOL)needDeleteNode {
    
    NSUInteger nodeCount = elements.count;
    __weak id<ASDataControllerSource> weakDataSource = _dataSource;
    if (nodeCount == 0 || weakDataSource == nil) {
        return;
    }
    
    ASSignpostStart(ASSignpostDataControllerBatch);
    
    {
        as_activity_create_for_scope("Data controller batch");
        
        __weak __typeof__(self) weakSelf = self;
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    NSUInteger threadCount = 0;
    if ([_dataSource dataControllerShouldSerializeNodeCreation:self]) {
      threadCount = 1;
    }
    ASDispatchApply(nodeCount, queue, threadCount, ^(size_t i) {
            __strong id<ASDataControllerSource> strongDataSource = weakDataSource;
            if (strongDataSource == nil) {
                return;
            }
            // Allocate the node.
            unowned ASCollectionElement *element = elements[i];
            [self _allocateNodeFromElement:element];
            
            if (needDeleteNode) {
                BOOL stillInMaintain = [weakSelf.delegate dataController:weakSelf checkElementIfStillInMaintainRange:element];
                if (stillInMaintain == NO) {
                    [element removeNode];
                    NSLog(@"REMOVE");
                }
            }
        });
    }
    
    ASSignpostEndCustom(ASSignpostDataControllerBatch, self, 0, (weakDataSource != nil ? ASSignpostColorDefault : ASSignpostColorRed));
}

- (ASCellNode *)_allocateNodeFromElement:(ASCollectionElement *)element {
    
    if (element.nodeIfAllocated) {
        return element.nodeIfAllocated;
    }

    unowned ASCellNode *node = element.node;

    if (element.nodeIfAllocated) {
        // Layout the node if the size range is valid.
        ASSizeRange sizeRange = element.constrainedSize;
        if (ASSizeRangeHasSignificantArea(sizeRange)) {
            [element layoutNodeWithConstrainedSize:sizeRange];
        }
    }

  element.shouldUseUIKitCell = node.shouldUseUIKitCell;

    return node;
}

/**
 * Measure and layout the given node with the constrained size range.
 */
- (void)_layoutNode:(ASCellNode *)node withConstrainedSize:(ASSizeRange)constrainedSize
{
  if (![_dataSource dataController:self shouldEagerlyLayoutNode:node]) {
    return;
  }
  
  ASDisplayNodeAssert(ASSizeRangeHasSignificantArea(constrainedSize), @"Attempt to layout cell node with invalid size range %@", NSStringFromASSizeRange(constrainedSize));

  CGRect frame = CGRectZero;
  frame.size = [node layoutThatFits:constrainedSize].size;
  node.frame = frame;
}

#pragma mark - Data Source Access (Calling _dataSource)

- (NSArray<NSIndexPath *> *)_allIndexPathsForItemsOfKind:(NSString *)kind inSections:(NSIndexSet *)sections
{
  ASDisplayNodeAssertMainThread();
  
  if (sections.count == 0 || _dataSource == nil) {
    return @[];
  }
  
  const auto indexPaths = [[NSMutableArray<NSIndexPath *> alloc] init];
  if ([kind isEqualToString:ASDataControllerRowNodeKind]) {
    std::vector<NSInteger> counts = [self itemCountsFromDataSource];
    [sections enumerateRangesUsingBlock:^(NSRange range, BOOL * _Nonnull stop) {
      for (NSUInteger sectionIndex = range.location; sectionIndex < NSMaxRange(range); sectionIndex++) {
        NSUInteger itemCount = counts[sectionIndex];
        for (NSUInteger i = 0; i < itemCount; i++) {
          [indexPaths addObject:[NSIndexPath indexPathForItem:i inSection:sectionIndex]];
        }
      }
    }];
  } else if (_dataSourceFlags.supplementaryNodesOfKindInSection) {
      __weak __typeof__(self) weakSelf = self;
    id<ASDataControllerSource> dataSource = _dataSource;
    [sections enumerateRangesUsingBlock:^(NSRange range, BOOL * _Nonnull stop) {
      for (NSUInteger sectionIndex = range.location; sectionIndex < NSMaxRange(range); sectionIndex++) {
        NSUInteger itemCount = [dataSource dataController:weakSelf supplementaryNodesOfKind:kind inSection:sectionIndex];
        for (NSUInteger i = 0; i < itemCount; i++) {
          [indexPaths addObject:[NSIndexPath indexPathForItem:i inSection:sectionIndex]];
        }
      }
    }];
  }
  
  return indexPaths;
}

/**
 * Agressively repopulates supplementary nodes of all kinds for sections that contains some given index paths.
 *
 * @param map The element map into which to apply the change.
 * @param indexPaths The index paths belongs to sections whose supplementary nodes need to be repopulated.
 * @param changeSet The changeset that triggered this repopulation.
 * @param traitCollection The trait collection needed to initialize elements
 * @param indexPathsAreNew YES if index paths are "after the update," NO otherwise.
 * @param shouldFetchSizeRanges Whether constrained sizes should be fetched from data source
 */
- (void)_repopulateSupplementaryNodesIntoMap:(ASMutableElementMap *)map
             forSectionsContainingIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
                                   changeSet:(_ASHierarchyChangeSet *)changeSet
                             traitCollection:(ASPrimitiveTraitCollection)traitCollection
                            indexPathsAreNew:(BOOL)indexPathsAreNew
                       shouldFetchSizeRanges:(BOOL)shouldFetchSizeRanges
                                 previousMap:(ASElementMap *)previousMap
{
  ASDisplayNodeAssertMainThread();

  if (indexPaths.count ==  0) {
    return;
  }

  // Remove all old supplementaries from these sections
  NSIndexSet *oldSections = [NSIndexSet as_sectionsFromIndexPaths:indexPaths];

  // Add in new ones with the new kinds.
  NSIndexSet *newSections;
  if (indexPathsAreNew) {
    newSections = oldSections;
  } else {
    newSections = [oldSections as_indexesByMapping:^NSUInteger(NSUInteger oldSection) {
      return [changeSet newSectionForOldSection:oldSection];
    }];
  }

  for (NSString *kind in [self supplementaryKindsInSections:newSections]) {
    [self _insertElementsIntoMap:map kind:kind forSections:newSections traitCollection:traitCollection shouldFetchSizeRanges:shouldFetchSizeRanges changeSet:changeSet previousMap:previousMap];
  }
}

/**
 * Update supplementary nodes of all kinds for sections.
 *
 * @param map The element map into which to apply the change.
 * @param traitCollection The trait collection needed to initialize elements
 * @param shouldFetchSizeRanges Whether constrained sizes should be fetched from data source
 */
- (void)_updateSupplementaryNodesIntoMap:(ASMutableElementMap *)map
                         traitCollection:(ASPrimitiveTraitCollection)traitCollection
                   shouldFetchSizeRanges:(BOOL)shouldFetchSizeRanges
                             previousMap:(ASElementMap *)previousMap
{
  ASDisplayNodeAssertMainThread();
  if (self.layoutDelegate != nil) {
    // TODO: https://github.com/TextureGroup/Texture/issues/948
    return;
  }
  NSUInteger sectionCount = [self itemCountsFromDataSource].size();
  if (sectionCount > 0) {
    NSIndexSet *sectionIndexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, sectionCount)];
    ASSizeRange newSizeRange = ASSizeRangeZero;
    for (NSString *kind in [self supplementaryKindsInSections:sectionIndexes]) {
      NSArray<NSIndexPath *> *indexPaths = [self _allIndexPathsForItemsOfKind:kind inSections:sectionIndexes];
      NSMutableArray<NSIndexPath *> *indexPathsToDeleteForKind = [[NSMutableArray alloc] init];
      NSMutableArray<NSIndexPath *> *indexPathsToInsertForKind = [[NSMutableArray alloc] init];
      // If supplementary node does exist and size is now zero, remove it.
      // If supplementary node doesn't exist and size is now non-zero, insert one.
      for (NSIndexPath *indexPath in indexPaths) {
        ASCollectionElement *previousElement = [previousMap supplementaryElementOfKind:kind atIndexPath:indexPath];
        newSizeRange = [self constrainedSizeForNodeOfKind:kind atIndexPath:indexPath];
        BOOL sizeRangeIsZero = ASSizeRangeEqualToSizeRange(ASSizeRangeZero, newSizeRange);
        if (previousElement != nil && sizeRangeIsZero) {
          [indexPathsToDeleteForKind addObject:indexPath];
        } else if (previousElement == nil && !sizeRangeIsZero) {
          [indexPathsToInsertForKind addObject:indexPath];
        }
      }

      [map removeSupplementaryElementsAtIndexPaths:indexPathsToDeleteForKind kind:kind];
      [self _insertElementsIntoMap:map kind:kind atIndexPaths:indexPathsToInsertForKind traitCollection:traitCollection shouldFetchSizeRanges:shouldFetchSizeRanges changeSet:nil previousMap:previousMap];
    }
  }
}

/**
 * Inserts new elements of a certain kind for some sections
 *
 * @param kind The kind of the elements, e.g ASDataControllerRowNodeKind
 * @param sections The sections that should be populated by new elements
 * @param traitCollection The trait collection needed to initialize elements
 * @param shouldFetchSizeRanges Whether constrained sizes should be fetched from data source
 */
- (void)_insertElementsIntoMap:(ASMutableElementMap *)map
                          kind:(NSString *)kind
                   forSections:(NSIndexSet *)sections
               traitCollection:(ASPrimitiveTraitCollection)traitCollection
         shouldFetchSizeRanges:(BOOL)shouldFetchSizeRanges
                     changeSet:(_ASHierarchyChangeSet *)changeSet
                   previousMap:(ASElementMap *)previousMap
{
  ASDisplayNodeAssertMainThread();
  
  if (sections.count == 0 || _dataSource == nil) {
    return;
  }
  
  NSArray<NSIndexPath *> *indexPaths = [self _allIndexPathsForItemsOfKind:kind inSections:sections];
  [self _insertElementsIntoMap:map kind:kind atIndexPaths:indexPaths traitCollection:traitCollection shouldFetchSizeRanges:shouldFetchSizeRanges changeSet:changeSet previousMap:previousMap];
}

/**
 * Inserts new elements of a certain kind at some index paths
 *
 * @param map The map to insert the elements into.
 * @param kind The kind of the elements, e.g ASDataControllerRowNodeKind
 * @param indexPaths The index paths at which new elements should be populated
 * @param traitCollection The trait collection needed to initialize elements
 * @param shouldFetchSizeRanges Whether constrained sizes should be fetched from data source
 */
- (void)_insertElementsIntoMap:(ASMutableElementMap *)map
                          kind:(NSString *)kind
                  atIndexPaths:(NSArray<NSIndexPath *> *)indexPaths
               traitCollection:(ASPrimitiveTraitCollection)traitCollection
         shouldFetchSizeRanges:(BOOL)shouldFetchSizeRanges
                     changeSet:(_ASHierarchyChangeSet *)changeSet
                   previousMap:(ASElementMap *)previousMap
{
  ASDisplayNodeAssertMainThread();
  
  if (indexPaths.count == 0 || _dataSource == nil) {
    return;
  }
  
  BOOL isRowKind = [kind isEqualToString:ASDataControllerRowNodeKind];
  if (!isRowKind && !_dataSourceFlags.supplementaryNodeBlockOfKindAtIndexPath) {
    // Populating supplementary elements but data source doesn't support.
    return;
  }
  
  LOG(@"Populating elements of kind: %@, for index paths: %@", kind, indexPaths);
  id<ASDataControllerSource> dataSource = self.dataSource;
  id<ASRangeManagingNode> node = self.node;
  BOOL shouldAsyncLayout = YES;
  for (NSIndexPath *indexPath in indexPaths) {
    ASCellNodeBlock nodeBlock;
    id nodeModel;
    if (isRowKind) {
      nodeModel = [dataSource dataController:self nodeModelForItemAtIndexPath:indexPath];
      
      // Get the prior element and attempt to update the existing cell node.
      if (nodeModel != nil && !changeSet.includesReloadData) {
        NSIndexPath *oldIndexPath = [changeSet oldIndexPathForNewIndexPath:indexPath];
        if (oldIndexPath != nil) {
          ASCollectionElement *oldElement = [previousMap elementForItemAtIndexPath:oldIndexPath];
          ASCellNode *oldNode = oldElement.node;
          if ([oldNode canUpdateToNodeModel:nodeModel]) {
            // Just wrap the node in a block. The collection element will -setNodeModel:
            nodeBlock = ^{
              return oldNode;
            };
          }
        }
      }
      if (nodeBlock == nil) {
        nodeBlock = [dataSource dataController:self nodeBlockAtIndexPath:indexPath shouldAsyncLayout:&shouldAsyncLayout];
      }
    } else {
      nodeBlock = [dataSource dataController:self supplementaryNodeBlockOfKind:kind atIndexPath:indexPath shouldAsyncLayout:&shouldAsyncLayout];
    }

    ASSizeRange constrainedSize = ASSizeRangeUnconstrained;
    if (shouldFetchSizeRanges) {
      constrainedSize = [self constrainedSizeForNodeOfKind:kind atIndexPath:indexPath];
    }
    
    ASCollectionElement *element = [[ASCollectionElement alloc] initWithNodeModel:nodeModel
                                                                        nodeBlock:nodeBlock
                                                         supplementaryElementKind:isRowKind ? nil : kind
                                                                  constrainedSize:constrainedSize
                                                                       owningNode:node
                                                                  traitCollection:traitCollection];
    [map insertElement:element atIndexPath:indexPath];
    changeSet.countForAsyncLayout += (shouldAsyncLayout ? 1 : 0);
  }
}

- (void)invalidateDataSourceItemCounts
{
  ASDisplayNodeAssertMainThread();
  _itemCountsFromDataSourceAreValid = NO;
}

- (std::vector<NSInteger>)itemCountsFromDataSource
{
  ASDisplayNodeAssertMainThread();
  if (NO == _itemCountsFromDataSourceAreValid) {
    id<ASDataControllerSource> source = self.dataSource;
    NSInteger sectionCount = [source numberOfSectionsInDataController:self];
    std::vector<NSInteger> newCounts;
    newCounts.reserve(sectionCount);
    for (NSInteger i = 0; i < sectionCount; i++) {
      newCounts.push_back([source dataController:self rowsInSection:i]);
    }
    _itemCountsFromDataSource = newCounts;
    _itemCountsFromDataSourceAreValid = YES;
  }
  return _itemCountsFromDataSource;
}

- (NSArray<NSString *> *)supplementaryKindsInSections:(NSIndexSet *)sections
{
  if (_dataSourceFlags.supplementaryNodeKindsInSections) {
    return [_dataSource dataController:self supplementaryNodeKindsInSections:sections];
  }
  
  return @[];
}

/**
 * Returns constrained size for the node of the given kind and at the given index path.
 * NOTE: index path must be in the data-source index space.
 */
- (ASSizeRange)constrainedSizeForNodeOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath
{
  ASDisplayNodeAssertMainThread();
  
  id<ASDataControllerSource> dataSource = _dataSource;
  if (dataSource == nil || indexPath == nil) {
    return ASSizeRangeZero;
  }
  
  if ([kind isEqualToString:ASDataControllerRowNodeKind]) {
    ASDisplayNodeAssert(_dataSourceFlags.constrainedSizeForNodeAtIndexPath, @"-dataController:constrainedSizeForNodeAtIndexPath: must also be implemented");
    return [dataSource dataController:self constrainedSizeForNodeAtIndexPath:indexPath];
  }
  
  if (_dataSourceFlags.constrainedSizeForSupplementaryNodeOfKindAtIndexPath){
    return [dataSource dataController:self constrainedSizeForSupplementaryNodeOfKind:kind atIndexPath:indexPath];
  }
  
  ASDisplayNodeAssert(NO, @"Unknown constrained size for node of kind %@ by data source %@", kind, dataSource);
  return ASSizeRangeZero;
}

- (void)_cancelNeedlessOperations:(NSHashTable<NSOperation *> *)reallocOperations {
    __weak ASDataController *weakSelf = self;
    dispatch_sync(_operationManagerQueue, ^{
        NSSet *operations = [reallocOperations copy];
        for (ASReallocOperation *operation in operations) {
            BOOL stillInMaintain = [weakSelf.delegate dataController:weakSelf checkElementsIfStillInMaintainRange:operation.needReallocElements];
            if (! stillInMaintain) {
                
                [operation cancel];
                [reallocOperations removeObject:operation];
                
                for (ASCollectionElement *element in operation.needReallocElements) {
                    element.markNeedAllocate = NO;
                }
            }
        }
    });
}

- (void)maintainUpdateWithEnterElements:(NSHashTable<ASCollectionElement *> *)enterElements andExitElement:(NSHashTable<ASCollectionElement *> *)exitElements {
    ASDisplayNodeAssertMainThread();
    
    __weak ASDataController * weakSelf = self;
    
    // Really important to update node interfaceState before going to remove it
    for (ASCollectionElement * exitElement in exitElements) {
        if (ASInterfaceStateIncludesVisible(exitElement.nodeInterfaceState)) {
            [exitElement exitInterfaceState:ASInterfaceStateVisible];
        }
        exitElement.markNeedDeallocate = YES;
    }
    
    for (ASCollectionElement * enterElement in enterElements) {
        if (ASInterfaceStateIncludesVisible(enterElement.nodeInterfaceState)) {
            [enterElement exitInterfaceState:ASInterfaceStateVisible];
        }
        enterElement.markNeedDeallocate = NO;
    }
    
    dispatch_async(_edittingMaintainQueue, ^{
        // Cancel reallocOperation
        [weakSelf _cancelNeedlessOperations:weakSelf.normalReallocOperations];
        
        // deallocate
        if (exitElements.count > 0) {
            NSSet<ASCollectionElement *> * batchElems = ASSetByFlatMapping(exitElements, ASCollectionElement * elem, elem.nodeIfAllocated ? elem : nil);
            if (batchElems.count > 0) {
                for (ASCollectionElement * elem in batchElems) {
                    BOOL stillInMaintain = [weakSelf.delegate dataController:weakSelf checkElementIfStillInMaintainRange:elem];
                    if (! stillInMaintain) {
                        [elem removeNode];
                    }
                }
            }
        }
        
        // Check for re-allocate cellnode
        if (enterElements.count > 0) {
            NSHashTable *batchElement = [[NSHashTable alloc] init];
            for (ASCollectionElement * element in enterElements) {
                if (element.nodeIfAllocated == nil) {
                    element.markNeedAllocate = YES;
                    [batchElement addObject:element];
                }
            }
            
            ASReallocOperation *operation = [[ASReallocOperation alloc] initWithElements:batchElement];
            __weak ASReallocOperation *weakOperation = operation;
            
            [operation addExecutionBlock:^{
                ASReallocOperation *strongOperation = weakOperation;
                
                if (!strongOperation.isCancelled) {
                    
                    NSHashTable<ASCollectionElement *> * elementsToAllocate = strongOperation.needReallocElements;
                    
                    if (elementsToAllocate.count > 0) {
                        for (ASCollectionElement * elem in elementsToAllocate) {
                            if (strongOperation.isCancelled) {
                                break;
                            }
                            
                            [weakSelf _allocateNodeFromElement:elem];
                        }
                    }
                }
                
                dispatch_barrier_async(_operationManagerQueue, ^{
                    [weakSelf.normalReallocOperations removeObject:strongOperation];
                });
            }];
            
            dispatch_barrier_async(_operationManagerQueue, ^{
                [weakSelf.normalReallocOperations addObject:operation];
            });
            
            [weakSelf.reallocOperationQueue addOperation:operation];
        }
    });
}

#pragma mark - Batching (External API)

- (void)waitUntilAllUpdatesAreProcessed
{
  // Schedule block in main serial queue to wait until all operations are finished that are
  // where scheduled while waiting for the _editingTransactionQueue to finish
  [self _scheduleBlockOnMainSerialQueue:^{ }];
}

- (BOOL)isProcessingUpdates
{
  ASDisplayNodeAssertMainThread();
  return _mainSerialQueue.numberOfScheduledBlocks > 0 || _editingTransactionGroupCount > 0;
}

- (void)onDidFinishProcessingUpdates:(void (^)())completion
{
  ASDisplayNodeAssertMainThread();
  if (!completion) {
    return;
  }
  if ([self isProcessingUpdates] == NO) {
    ASPerformBlockOnMainThread(completion);
  } else {
    dispatch_async(_editingTransactionQueue, ^{
      // Retry the block. If we're done processing updates, it'll run immediately, otherwise
      // wait again for updates to quiesce completely.
      // Don't use _mainSerialQueue so that we don't affect -isProcessingUpdates.
      dispatch_async(dispatch_get_main_queue(), ^{
        [self onDidFinishProcessingUpdates:completion];
      });
    });
  }
}

- (BOOL)isSynchronized {
  return _synchronized;
}

- (void)onDidFinishSynchronizing:(void (^)())completion {
  ASDisplayNodeAssertMainThread();
  if (!completion) {
    return;
  }
  if ([self isSynchronized]) {
    ASPerformBlockOnMainThread(completion);
  } else {
    // Hang on to the completion block so that it gets called the next time view is synchronized to data.
    [_onDidFinishSynchronizingBlocks addObject:[completion copy]];
  }
}

- (void)updateWithChangeSet:(_ASHierarchyChangeSet *)changeSet
{
  ASDisplayNodeAssertMainThread();

  _synchronized = NO;

  [changeSet addCompletionHandler:^(BOOL finished) {
    _synchronized = YES;
    [self onDidFinishProcessingUpdates:^{
      if (_synchronized) {
        for (ASDataControllerSynchronizationBlock block in _onDidFinishSynchronizingBlocks) {
          block();
        }
        [_onDidFinishSynchronizingBlocks removeAllObjects];
      }
    }];
  }];
  
  if (changeSet.includesReloadData) {
    if (_initialReloadDataHasBeenCalled) {
      as_log_debug(ASCollectionLog(), "reloadData %@", ASViewToDisplayNode(ASDynamicCast(self.dataSource, UIView)));
    } else {
      as_log_debug(ASCollectionLog(), "Initial reloadData %@", ASViewToDisplayNode(ASDynamicCast(self.dataSource, UIView)));
      _initialReloadDataHasBeenCalled = YES;
    }
  } else {
    as_log_debug(ASCollectionLog(), "performBatchUpdates %@ %@", ASViewToDisplayNode(ASDynamicCast(self.dataSource, UIView)), changeSet);
  }
  
  NSTimeInterval transactionQueueFlushDuration = 0.0f;
  {
    ASDN::ScopeTimer t(transactionQueueFlushDuration);
    dispatch_group_wait(_editingTransactionGroup, DISPATCH_TIME_FOREVER);
  }
  
  // If the initial reloadData has not been called, just bail because we don't have our old data source counts.
  // See ASUICollectionViewTests.testThatIssuingAnUpdateBeforeInitialReloadIsUnacceptable
  // for the issue that UICollectionView has that we're choosing to workaround.
  if (!_initialReloadDataHasBeenCalled) {
    as_log_debug(ASCollectionLog(), "%@ Skipped update because load hasn't happened.", ASObjectDescriptionMakeTiny(_dataSource));
    [changeSet executeCompletionHandlerWithFinished:YES];
    return;
  }
  
  [self invalidateDataSourceItemCounts];
  
  // Log events
#if ASEVENTLOG_ENABLE
  ASDataControllerLogEvent(self, @"updateWithChangeSet waited on previous update for %fms. changeSet: %@",
                           transactionQueueFlushDuration * 1000.0f, changeSet);
  NSTimeInterval changeSetStartTime = CACurrentMediaTime();
  NSString *changeSetDescription = ASObjectDescriptionMakeTiny(changeSet);
    __weak __typeof__(self) weakSelf = self;
  [changeSet addCompletionHandler:^(BOOL finished) {
    ASDataControllerLogEvent(weakSelf, @"finishedUpdate in %fms: %@",
                             (CACurrentMediaTime() - changeSetStartTime) * 1000.0f, changeSetDescription);
  }];
#endif
  
  // Attempt to mark the update completed. This is when update validation will occur inside the changeset.
  // If an invalid update exception is thrown, we catch it and inject our "validationErrorSource" object,
  // which is the table/collection node's data source, into the exception reason to help debugging.
  @try {
    [changeSet markCompletedWithNewItemCounts:[self itemCountsFromDataSource]];
  } @catch (NSException *e) {
    id responsibleDataSource = self.validationErrorSource;
    if (e.name == ASCollectionInvalidUpdateException && responsibleDataSource != nil) {
      [NSException raise:ASCollectionInvalidUpdateException format:@"%@: %@", [responsibleDataSource class], e.reason];
    } else {
      @throw e;
    }
  }

  BOOL canDelegate = (self.layoutDelegate != nil);
  ASElementMap *newMap;
  ASCollectionLayoutContext *layoutContext;
  {
    as_activity_scope(as_activity_create("Latch new data for collection update", changeSet.rootActivity, OS_ACTIVITY_FLAG_DEFAULT));

    // Step 1: Populate a new map that reflects the data source's state and use it as pendingMap
    ASElementMap *previousMap = self.pendingMap;
    if (changeSet.isEmpty) {
      // If the change set is empty, nothing has changed so we can just reuse the previous map
      newMap = previousMap;
    } else {
      // Mutable copy of current data.
      ASMutableElementMap *mutableMap = [previousMap mutableCopy];

      // Step 1.1: Update the mutable copies to match the data source's state
      [self _updateSectionsInMap:mutableMap changeSet:changeSet];
      ASPrimitiveTraitCollection existingTraitCollection = [self.node primitiveTraitCollection];
      [self _updateElementsInMap:mutableMap changeSet:changeSet traitCollection:existingTraitCollection shouldFetchSizeRanges:(! canDelegate) previousMap:previousMap];

      // Step 1.2: Clone the new data
      newMap = [mutableMap copy];
    }
    self.pendingMap = newMap;

    // Step 2: Ask layout delegate for contexts
    if (canDelegate) {
      layoutContext = [self.layoutDelegate layoutContextWithElements:newMap];
    }
  }

  as_log_debug(ASCollectionLog(), "New content: %@", newMap.smallDescription);

  Class<ASDataControllerLayoutDelegate> layoutDelegateClass = [self.layoutDelegate class];
  ++_editingTransactionGroupCount;
  dispatch_group_async(_editingTransactionGroup, _editingTransactionQueue, ^{
    __block __unused os_activity_scope_state_s preparationScope = {}; // unused if deployment target < iOS10
    as_activity_scope_enter(as_activity_create("Prepare nodes for collection update", AS_ACTIVITY_CURRENT, OS_ACTIVITY_FLAG_DEFAULT), &preparationScope);

    // Step 3: Call the layout delegate if possible. Otherwise, allocate and layout all elements
    if (canDelegate) {
      [layoutDelegateClass calculateLayoutWithContext:layoutContext];
    } else {
      const auto elementsToProcess = [[NSMutableArray<ASCollectionElement *> alloc] init];
      for (ASCollectionElement *element in newMap) {
        ASCellNode *nodeIfAllocated = element.nodeIfAllocated;
        if (nodeIfAllocated.shouldUseUIKitCell) {
          // If the node exists and we know it is a passthrough cell, we know it will never have a .calculatedLayout.
          continue;
        } else if (nodeIfAllocated.calculatedLayout == nil && element.markNeedAllocate == YES) {
          // If the node hasn't been allocated, or it doesn't have a valid layout, let's process it.
          [elementsToProcess addObject:element];
        }
      }
      [self _allocateNodesFromElements:elementsToProcess];
    }

    // Step 4: Inform the delegate on main thread
    [_mainSerialQueue performBlockOnMainThread:^{
      as_activity_scope_leave(&preparationScope);
      [_delegate dataController:self updateWithChangeSet:changeSet updates:^{
        // Step 5: Deploy the new data as "completed"
        //
        // Note that since the backing collection view might be busy responding to user events (e.g scrolling),
        // it will not consume the batch update blocks immediately.
        // As a result, in a short intermidate time, the view will still be relying on the old data source state.
        // Thus, we can't just swap the new map immediately before step 4, but until this update block is executed.
        // (https://github.com/TextureGroup/Texture/issues/378)
        self.visibleMap = newMap;
      }];
    }];
    --_editingTransactionGroupCount;
  });

  // We've now dispatched node allocation and layout to a concurrent background queue.
  // In some cases, it's advantageous to prevent the main thread from returning, to ensure the next
  // frame displayed to the user has the view updates in place. Doing this does slightly reduce
  // total latency, by donating the main thread's priority to the background threads. As such, the
  // two cases where it makes sense to block:
  // 1. There is very little work to be performed in the background (UIKit passthrough)
  // 2. There is a higher priority on display latency than smoothness, e.g. app startup.
  if ([_dataSource dataController:self shouldSynchronouslyProcessChangeSet:changeSet]) {
    [self waitUntilAllUpdatesAreProcessed];
  }
}

/**
 * Update sections based on the given change set.
 */
- (void)_updateSectionsInMap:(ASMutableElementMap *)map changeSet:(_ASHierarchyChangeSet *)changeSet
{
  ASDisplayNodeAssertMainThread();
  
  if (changeSet.includesReloadData) {
    [map removeAllSections];
    
    NSUInteger sectionCount = [self itemCountsFromDataSource].size();
    NSIndexSet *sectionIndexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, sectionCount)];
    [self _insertSectionsIntoMap:map indexes:sectionIndexes];
    // Return immediately because reloadData can't be used in conjuntion with other updates.
    return;
  }
  
  for (_ASHierarchySectionChange *change in [changeSet sectionChangesOfType:_ASHierarchyChangeTypeDelete]) {
    [map removeSectionsAtIndexes:change.indexSet];
  }
  
  for (_ASHierarchySectionChange *change in [changeSet sectionChangesOfType:_ASHierarchyChangeTypeInsert]) {
    [self _insertSectionsIntoMap:map indexes:change.indexSet];
  }
}

- (void)_insertSectionsIntoMap:(ASMutableElementMap *)map indexes:(NSIndexSet *)sectionIndexes
{
  ASDisplayNodeAssertMainThread();

  [sectionIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
    id<ASSectionContext> context;
    if (_dataSourceFlags.contextForSection) {
      context = [_dataSource dataController:self contextForSection:idx];
    }
    ASSection *section = [[ASSection alloc] initWithSectionID:_nextSectionID context:context];
    [map insertSection:section atIndex:idx];
    _nextSectionID++;
  }];
}

/**
 * Update elements based on the given change set.
 */
- (void)_updateElementsInMap:(ASMutableElementMap *)map
                   changeSet:(_ASHierarchyChangeSet *)changeSet
             traitCollection:(ASPrimitiveTraitCollection)traitCollection
       shouldFetchSizeRanges:(BOOL)shouldFetchSizeRanges
                 previousMap:(ASElementMap *)previousMap
{
  ASDisplayNodeAssertMainThread();

  if (changeSet.includesReloadData) {
    [map removeAllElements];
    
    NSUInteger sectionCount = [self itemCountsFromDataSource].size();
    if (sectionCount > 0) {
      NSIndexSet *sectionIndexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, sectionCount)];
      [self _insertElementsIntoMap:map sections:sectionIndexes traitCollection:traitCollection shouldFetchSizeRanges:shouldFetchSizeRanges changeSet:changeSet previousMap:previousMap];
    }
    // Return immediately because reloadData can't be used in conjuntion with other updates.
    return;
  }
  
  // Migrate old supplementary nodes to their new index paths.
  [map migrateSupplementaryElementsWithSectionMapping:changeSet.sectionMapping];

  for (_ASHierarchyItemChange *change in [changeSet itemChangesOfType:_ASHierarchyChangeTypeDelete]) {
    [map removeItemsAtIndexPaths:change.indexPaths];
    // Aggressively repopulate supplementary nodes (#1773 & #1629)
    [self _repopulateSupplementaryNodesIntoMap:map forSectionsContainingIndexPaths:change.indexPaths
                                     changeSet:changeSet
                               traitCollection:traitCollection
                              indexPathsAreNew:NO
                         shouldFetchSizeRanges:shouldFetchSizeRanges
                                   previousMap:previousMap];
  }

  for (_ASHierarchySectionChange *change in [changeSet sectionChangesOfType:_ASHierarchyChangeTypeDelete]) {
    NSIndexSet *sectionIndexes = change.indexSet;
    [map removeSectionsOfItems:sectionIndexes];
  }
  
  for (_ASHierarchySectionChange *change in [changeSet sectionChangesOfType:_ASHierarchyChangeTypeInsert]) {
    [self _insertElementsIntoMap:map sections:change.indexSet traitCollection:traitCollection shouldFetchSizeRanges:shouldFetchSizeRanges changeSet:changeSet previousMap:previousMap];
  }
  
  for (_ASHierarchyItemChange *change in [changeSet itemChangesOfType:_ASHierarchyChangeTypeInsert]) {
    [self _insertElementsIntoMap:map kind:ASDataControllerRowNodeKind atIndexPaths:change.indexPaths traitCollection:traitCollection shouldFetchSizeRanges:shouldFetchSizeRanges changeSet:changeSet previousMap:previousMap];
    // Aggressively reload supplementary nodes (#1773 & #1629)
    [self _repopulateSupplementaryNodesIntoMap:map forSectionsContainingIndexPaths:change.indexPaths
                                     changeSet:changeSet
                               traitCollection:traitCollection
                              indexPathsAreNew:YES
                         shouldFetchSizeRanges:shouldFetchSizeRanges
                                   previousMap:previousMap];
  }
}

- (void)_insertElementsIntoMap:(ASMutableElementMap *)map
                      sections:(NSIndexSet *)sectionIndexes
               traitCollection:(ASPrimitiveTraitCollection)traitCollection
         shouldFetchSizeRanges:(BOOL)shouldFetchSizeRanges
                     changeSet:(_ASHierarchyChangeSet *)changeSet
                   previousMap:(ASElementMap *)previousMap
{
  ASDisplayNodeAssertMainThread();
  
  if (sectionIndexes.count == 0 || _dataSource == nil) {
    return;
  }

  // Items
  [map insertEmptySectionsOfItemsAtIndexes:sectionIndexes];
  [self _insertElementsIntoMap:map kind:ASDataControllerRowNodeKind forSections:sectionIndexes traitCollection:traitCollection shouldFetchSizeRanges:shouldFetchSizeRanges changeSet:changeSet previousMap:previousMap];

  // Supplementaries
  for (NSString *kind in [self supplementaryKindsInSections:sectionIndexes]) {
    // Step 2: Populate new elements for all sections
    [self _insertElementsIntoMap:map kind:kind forSections:sectionIndexes traitCollection:traitCollection shouldFetchSizeRanges:shouldFetchSizeRanges changeSet:changeSet previousMap:previousMap];
  }
}

#pragma mark - Relayout

- (void)relayoutNodes:(id<NSFastEnumeration>)nodes nodesSizeChanged:(NSMutableArray<ASCellNode *> *)nodesSizesChanged
{
  NSParameterAssert(nodes);
  NSParameterAssert(nodesSizesChanged);
  
  ASDisplayNodeAssertMainThread();
  if (!_initialReloadDataHasBeenCalled) {
    return;
  }
  
  id<ASDataControllerSource> dataSource = self.dataSource;
  const auto visibleMap = self.visibleMap;
  const auto pendingMap = self.pendingMap;
  for (ASCellNode *node in nodes) {
    const auto element = node.collectionElement;
    NSIndexPath *indexPathInPendingMap = [pendingMap indexPathForElement:element];
    // Ensure the element is present in both maps or skip it. If it's not in the visible map,
    // then we can't check the presented size. If it's not in the pending map, we can't get the constrained size.
    // This will only happen if the element has been deleted, so the specifics of this behavior aren't important.
    if (indexPathInPendingMap == nil || [visibleMap indexPathForElement:element] == nil) {
      continue;
    }

    NSString *kind = element.supplementaryElementKind ?: ASDataControllerRowNodeKind;
    ASSizeRange constrainedSize = [self constrainedSizeForNodeOfKind:kind atIndexPath:indexPathInPendingMap];
      
    [element layoutNodeWithConstrainedSize:constrainedSize];
      
    BOOL matchesSize = [dataSource dataController:self presentedSizeForElement:element matchesSize:node.frame.size];
    if (! matchesSize) {
      [nodesSizesChanged addObject:node];
    }
  }
}

- (void)requeryConstraintSizeAllNodes {
    ASDisplayNodeAssertMainThread();
    for (ASCollectionElement *element in _visibleMap) {
        // Ignore this element if it is no longer in the latest data. It is still recognized in the UIKit world but will be deleted soon.
        NSIndexPath *indexPathInPendingMap = [_pendingMap indexPathForElement:element];
        if (indexPathInPendingMap == nil) {
            continue;
        }
        
        NSString *kind = element.supplementaryElementKind ?: ASDataControllerRowNodeKind;
        ASSizeRange newConstrainedSize = [self constrainedSizeForNodeOfKind:kind atIndexPath:indexPathInPendingMap];
        
        if (ASSizeRangeHasSignificantArea(newConstrainedSize)) {
            element.constrainedSize = newConstrainedSize;
            // relayout node if node avaiable
            if (element.nodeIfAllocated) {
                [element layoutNodeWithConstrainedSize:newConstrainedSize];
            }
        }
    }
}

- (void)relayoutAllNodesWithInvalidationBlock:(nullable void (^)())invalidationBlock
{
    [self relayoutAllNodesWithInvalidationBlock:invalidationBlock withCompletion:nil];
}

- (void)relayoutAllNodesWithInvalidationBlock:(nullable void (^)())invalidationBlock withCompletion:(void (^)())completion {
    ASDisplayNodeAssertMainThread();
    _relayoutAllNodesTaskCount++;
    
    if (!_initialReloadDataHasBeenCalled) {
        _relayoutAllNodesTaskCount--;
        if (completion) {
            completion();
        }
        return;
    }
    
    // Can't relayout right away because _visibleMap may not be up-to-date,
    // i.e there might be some nodes that were measured using the old constrained size but haven't been added to _visibleMap
    LOG(@"Edit Command - relayoutRows");
    [self _scheduleBlockOnMainSerialQueue:^{
    // Because -invalidateLayout doesn't trigger any operations by itself, and we answer queries from UICollectionView using layoutThatFits:,
    // we invalidate the layout before we have updated all of the cells. Any cells that the collection needs the size of immediately will get
    // -layoutThatFits: with a new constraint, on the main thread, and synchronously calculate them. Meanwhile, relayoutAllNodes will update
    // the layout of any remaining nodes on background threads (and fast-return for any nodes that the UICV got to first).
    if (invalidationBlock) {
      invalidationBlock();
    }
        [self _relayoutAllNodesWithCompletion:completion];
    }];
}

- (void)_relayoutAllNodesWithCompletion:(void (^)())completion {
    ASDisplayNodeAssertMainThread();
    
    [self requeryConstraintSizeAllNodes];
    
    __weak ASDataController * weakSelf = self;
    [self _scheduleBlockOnMainSerialQueue:^{
        
        // Cancel current relayout nodes tasks if any
        [weakSelf cancelRelayoutAllNodesIfAny];
	
	ASMutableElementMap *newMap = [_pendingMap mutableCopy];
  [self _updateSupplementaryNodesIntoMap:newMap
                         traitCollection:[self.node primitiveTraitCollection]
                   shouldFetchSizeRanges:YES
                             previousMap:_pendingMap];
  _pendingMap = [newMap copy];
  _visibleMap = _pendingMap;
        
        // This code snipe run in the serial queue is the need to prevent thread-safety crash
        // when user rotate mutiple time but this snipe of code is not completely done
        //
        // This machanism use NSOperationQueue cause the fact that NSOperationQueue can cancel
        // current very heavy running tasks -> very effective if tableView/collectionView change
        // frame mutiple time.
        NSBlockOperation *operation = [[NSBlockOperation alloc] init];
        __weak NSBlockOperation *weakOperation = operation;
        [operation addExecutionBlock:^{
            
            ESTIMATE_TIME_START;
            
            __block __unused os_activity_scope_state_s preparationScope = {}; // unused if deployment target < iOS10
            as_activity_scope_enter(as_activity_create("Relayout all node for collection frame change", AS_ACTIVITY_CURRENT, OS_ACTIVITY_FLAG_DEFAULT), &preparationScope);
            
            for (int i = 0; i < weakSelf.visibleMap.itemElements.count; i++) {
                if (weakOperation.isCancelled) {
                    // Cancel current relayout process
                    // if tableView/collectionView change frame
                    // mutiple time. This will save a ton of processing time
                } else {
                    // @autoreleasepool is really important
                    // normally object will dealloc as soon as object can be dealloc
                    // but autoreleasepool will force it dealloc immediately
                    // INFO: https://stackoverflow.com/questions/12827319/forcing-an-object-to-deallocate-under-arc
                    // INFO: https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/MemoryMgmt/Articles/mmAutoreleasePools.html
                    //
                    // Currently it's a memory increase if we are on a debug build
                    // due to Texture Event-logging. Release build will not have
                    // memory issue
                    // INFO: https://github.com/TextureGroup/Texture/issues/211
                    @autoreleasepool {
                        ASCollectionElement * element = weakSelf.visibleMap.itemElements[i];
                        ASCellNode *node = element.node;
                        if (node) {
                            [element layoutNodeWithConstrainedSize:element.constrainedSize];
                        }
                        
                        // Check if node is being in maintain range or not
                        BOOL stillInMaintain = [weakSelf.delegate dataController:weakSelf checkElementIfStillInMaintainRange:element];
                        if (stillInMaintain == NO) {
                            [element removeNode];
                        }
                    }
                }
            }
            
            if (completion) {
                ASPerformBlockOnMainThread(^{
                    weakSelf.relayoutAllNodesTaskCount--;
                    completion();
                });
            } else {
                ASPerformBlockOnMainThread(^{
                    weakSelf.relayoutAllNodesTaskCount--;
                });
            }
            as_activity_scope_leave(&preparationScope);
            
            NSUInteger num = weakSelf.visibleMap.itemElements.count;
            NSString * logS = [NSString stringWithFormat:@"Relayout %lu", num];
            ESTIMATE_TIME_END(logS);
            
            dispatch_barrier_async(_operationManagerQueue, ^{
                [weakSelf.normalRelayoutOperations removeObject:weakOperation];
            });
        }];
        
        dispatch_barrier_async(_operationManagerQueue, ^{
            [weakSelf.normalRelayoutOperations addObject:operation];
        });
        
        [weakSelf.reallocOperationQueue addOperation:operation];
    }];
}

- (BOOL)isRelayoutAllNode {
    ASDisplayNodeAssertMainThread();
    return _relayoutAllNodesTaskCount > 0;
}

- (void)cancelRelayoutAllNodesIfAny {
    __weak ASDataController * weakSelf = self;
    if (self.isRelayoutAllNode) {
        dispatch_sync(_operationManagerQueue, ^{
            NSHashTable * operations = [weakSelf.normalRelayoutOperations copy];
            for (NSBlockOperation *operation in operations) {
                [operation cancel];
                [weakSelf.normalRelayoutOperations removeObject:operation];
            }
        });
    }
}

# pragma mark - ASPrimitiveTraitCollection

- (void)environmentDidChange
{
  ASPerformBlockOnMainThread(^{
    if (!_initialReloadDataHasBeenCalled) {
      return;
    }

    // Can't update the trait collection right away because _visibleMap may not be up-to-date,
    // i.e there might be some elements that were allocated using the old trait collection but haven't been added to _visibleMap
    [self _scheduleBlockOnMainSerialQueue:^{
      ASPrimitiveTraitCollection newTraitCollection = [self.node primitiveTraitCollection];
      for (ASCollectionElement *element in _visibleMap) {
        element.traitCollection = newTraitCollection;
      }
    }];
  });
}

- (void)clearData
{
  ASDisplayNodeAssertMainThread();
  if (_initialReloadDataHasBeenCalled) {
    [self waitUntilAllUpdatesAreProcessed];
    self.visibleMap = self.pendingMap = [[ASElementMap alloc] init];
  }
}

# pragma mark - Helper methods

- (void)_scheduleBlockOnMainSerialQueue:(dispatch_block_t)block
{
  ASDisplayNodeAssertMainThread();
  dispatch_group_wait(_editingTransactionGroup, DISPATCH_TIME_FOREVER);
  [_mainSerialQueue performBlockOnMainThread:block];
}

@end
