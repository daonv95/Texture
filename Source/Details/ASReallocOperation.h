//
//  ASReallocOperation.h
//  Pods
//
//  Created by CPU11815 on 7/19/17.
//
//

#import <Foundation/Foundation.h>

@class ASCollectionElement;

@interface ASReallocOperation : NSBlockOperation

@property (nonatomic, readonly) NSHashTable<ASCollectionElement *> *needReallocElements;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithElements:(NSHashTable<ASCollectionElement *> *)elements NS_DESIGNATED_INITIALIZER;

@end
