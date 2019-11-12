//
//  ASView.h
//  AsyncDisplayKit
//
//  Created by Dao Nguyen Van on 11/4/19.
//  Copyright © 2019 Pinterest. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AsyncDisplayKit/ASLayoutElement.h>

NS_ASSUME_NONNULL_BEGIN

typedef ASLayoutSpec * _Nonnull(^ASUIViewLayoutSpecBlock)(__kindof UIView *view, ASSizeRange constrainedSize);


@interface UIView (ASLayoutElement) <ASLayoutElement>

@end

@interface UIView (ASLayoutSpec)

@property (assign) BOOL automaticallyManageSubviews;
@property (nullable) ASUIViewLayoutSpecBlock layoutSpecBlock;
@property (readonly) CGSize calculatedSize;

- (ASLayout *)calculateLayoutLayoutSpec:(ASSizeRange)constrainedSize;
- (void)calculateLayoutDidChange;

- (void)applyLayout;

@end

@interface ASView : UIView

@end

NS_ASSUME_NONNULL_END
