//
//  ASCollectionFlowLayoutItem.h
//  AGEmojiKeyboard
//
//  Created by CPU11815 on 8/9/17.
//

#import <UIKit/UIKit.h>
#import <AsyncDisplayKit/ASBaseDefines.h>
#import <AsyncDisplayKit/ASLayoutElement.h>

@class ASCollectionElement;

NS_ASSUME_NONNULL_BEGIN

/**
 * A dummy item that represents a collection element to participate in the collection layout calculation process
 * without triggering measurement on the actual node of the collection element.
 *
 * This item always has a fixed size that is the item size passed to it.
 */
AS_SUBCLASSING_RESTRICTED
@interface _ASFlowLayoutItem : NSObject <ASLayoutElement>

@property (nonatomic, weak, readonly) ASCollectionElement *collectionElement;

- (instancetype)initWithCollectionElement:(ASCollectionElement *)collectionElement;
- (instancetype)init __unavailable;

@end

NS_ASSUME_NONNULL_END
