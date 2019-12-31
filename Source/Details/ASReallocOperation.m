//
//  ASReallocOperation.m
//  Pods
//
//  Created by CPU11815 on 7/19/17.
//
//

#import "ASReallocOperation.h"

@implementation ASReallocOperation

- (instancetype)init {
    @throw [NSException exceptionWithName:@"ASReallocOperation init error" reason:@"Use initWithElements instead" userInfo:nil];
    return [self initWithElements:nil];
}

- (instancetype)initWithElements:(NSHashTable<ASCollectionElement *> *)elements {
    if (self = [super init]) {
        _needReallocElements = elements;
    }
    
    return self;
}

@end
