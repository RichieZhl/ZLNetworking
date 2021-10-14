//
//  ZLImageTableViewCell.h
//  ZLNetworking_Example
//
//  Created by lylaut on 2021/10/13.
//  Copyright © 2021 richiezhl. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZLImageTableViewCell : UITableViewCell
@property (weak, nonatomic) IBOutlet UIImageView *imgView;
@property (weak, nonatomic) IBOutlet UILabel *titleLabel;

@end

NS_ASSUME_NONNULL_END
