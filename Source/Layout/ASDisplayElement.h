//
//  ASDisplayElement.h
//  AsyncDisplayKit
//
//  Created by Dao Nguyen Van on 11/4/19.
//  Copyright © 2019 Pinterest. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AsyncDisplayKit/ASDisplayNode.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ASDisplayElement <NSObject>

@end

@interface ASDisplayNode (ASDisplayElement) <ASDisplayElement>

@end

@interface UIView (ASDisplayElement) <ASDisplayElement>

@end

NS_ASSUME_NONNULL_END
