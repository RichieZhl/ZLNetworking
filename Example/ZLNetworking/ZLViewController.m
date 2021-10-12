//
//  ZLViewController.m
//  ZLNetworking
//
//  Created by richiezhl on 09/30/2021.
//  Copyright (c) 2021 richiezhl. All rights reserved.
//

#import "ZLViewController.h"
#import <ZLNetworking/ZLURLSessionManager.h>
#import <ZLNetworking/ZLNetImage.h>

@interface ZLViewController ()

@property (nonatomic, strong) NSOperationQueue *queue;

@property (nonatomic, weak) IBOutlet UIImageView *imageView;

@end

@implementation ZLViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib
   
//    ZLURLTask *task = [[ZLURLTask alloc] init];
//    task.task = [[ZLURLSessionManager shared].urlSession dataTaskWithURL:[NSURL URLWithString:@"https://aresapi.qianmi.com/api/map?pid=1&eid=2&platform=android&sv=11&gray=0"]];
//
//    [[ZLURLSessionManager shared].urlSession webSocketTaskWithURL:[NSURL URLWithString:@""] protocols:@[]];
//    
//    self.queue = [[NSOperationQueue alloc] init];
//    self.queue.maxConcurrentOperationCount = 1;
//
//    [self.queue addOperation:task];
    
//    [[ZLURLSessionManager shared] GET:@"https://aresapi.qianmi.com/api/map" parameters:@{@"pid": @1, @"eid": @2, @"platform": @"android", @"sv": @11, @"gray": @0} headers:nil responseBodyType:ZLResponseBodyTypeJson success:^(NSHTTPURLResponse *urlResponse, id responseObject) {
//        NSLog(@"%@", urlResponse);
//        NSLog(@"%@", responseObject);
//    } failure:^(NSError *error) {
//
//    }];
    
//    [[ZLURLSessionManager shared] POST:@"http://localhost:8080" parameters:nil requestBodyType:ZLRequestBodyTypeJson bodyParameters:@{@"a": @34} headers:nil responseBodyType:ZLResponseBodyTypeXml success:^(NSHTTPURLResponse *urlResponse, id responseObject) {
//        NSLog(@"%@", urlResponse);
//        NSLog(@"%@", responseObject);
//    } failure:^(NSError *error) {
//
//    }];
    
//    [[ZLURLSessionManager shared] POST:@"http://172.19.3.65:8080" parameters:nil constructingBodyWithBlock:^(ZLMultipartFormData *formData) {
//        NSURL *url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"测试中文" ofType:@"jpeg"]];
//        [formData appendPartWithFileURL:url name:@"file"];
//    } headers:nil responseBodyType:ZLResponseBodyTypeJson success:^(NSHTTPURLResponse *urlResponse, id responseObject) {
//        NSLog(@"%@", urlResponse);
//        NSLog(@"%@", responseObject);
//    } failure:^(NSError *error) {
//
//    }];
    
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://qianmi-resources.oss-cn-hangzhou.aliyuncs.com/ares/app/sxxd_ios.ipa"]];
    NSString *filePath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"1.ipa"];
    NSURL *url = [NSURL fileURLWithPath:filePath];

    [[ZLURLSessionManager shared] downloadWithRequest:request headers:nil destination:url progress:^(float progress) {
        NSLog(@"progress:%.2f", progress * 100);
    } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        NSLog(@"%@\n%@", response, filePath);
    }];
    
//    self.imageView.image = [UIImage zl_imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"locate" ofType:@"png"]];
//    [self.imageView zl_setImageWithURL:[NSURL URLWithString:@"https://qianmi-resources.oss-cn-hangzhou.aliyuncs.com/60ed05864ceaef3ba3620ef9/IMAGE/04004116279755425641.jpg"] placeholderImage:[UIImage zl_imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"locate" ofType:@"png"]] progress:^(float progress) {
//
//    } completed:^(UIImage * _Nullable image, NSError * _Nullable error) {
//
//    }];
    [self.imageView zl_setImageWithURL:[NSURL URLWithString:@"https://qianmi-resources.oss-cn-hangzhou.aliyuncs.com/60ed05864ceaef3ba3620ef9/IMAGE/04004116279755425641.jpg"]];
    
    NSData *data = [self.imageView.image zl_imageDataWithQuality:1];
    [data writeToFile:@"/Users/lylaut/Desktop/zlnet.png" atomically:YES];
    
    ZLAnimatedImageView *imgView = [[ZLAnimatedImageView alloc] initWithFrame:CGRectMake(20, 240, 150, 150)];
    NSData *gifData = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"sohucs.gif" ofType:nil]];
    imgView.image = [UIImage zl_animatedImageWithData:gifData scale:1];
    [self.view addSubview:imgView];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
