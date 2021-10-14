//
//  ZLImageTableViewCell.m
//  ZLNetworking_Example
//
//  Created by lylaut on 2021/10/13.
//  Copyright © 2021 richiezhl. All rights reserved.
//

#import "ZLImageTableViewCell.h"
#import <ZLNetworking/ZLNetImage.h>

@implementation ZLImageTableViewCell

- (void)awakeFromNib {
    [super awakeFromNib];
    // Initialization code
    self.imageView.renderSize = CGSizeMake(60, 60);
    self.imageView.renderCornerRadius = 8;
    self.imageView.renderContentMode = ZLNetImageViewContentModeScaleAspectFill;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

@end
