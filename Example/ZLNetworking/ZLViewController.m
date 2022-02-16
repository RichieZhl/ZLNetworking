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
#import "ZLImageTableViewCell.h"
#import <ZLNetworking/ZLWebSocket.h>

@interface ZLViewController () <UITableViewDataSource, ZLWebSocketDelegate>

@property (nonatomic, weak) IBOutlet UIImageView *imageView;

@property (nonatomic, weak) IBOutlet UITableView *tableView;

@property (nonatomic, strong) NSMutableArray<NSString *> *items;

@property (nonatomic, strong) ZLWebSocket *socket;

@end

@implementation ZLViewController

- (NSMutableArray<NSString *> *)items {
    if (_items == nil) {
        _items = [NSMutableArray array];
    }
    return _items;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib
    self.socket = [[ZLWebSocket alloc] initWithURL:[self webSocketReConnectURL]];
    self.socket.delegate = self;
    [self.socket open];
    
    [[ZLURLSessionManager shared] GET:@"https://aresapi.qianmi.com/api/map" parameters:@{@"pid": @1, @"eid": @2, @"platform": @"android", @"sv": @11, @"gray": @0} headers:nil responseBodyType:ZLResponseBodyTypeJson success:^(NSHTTPURLResponse *urlResponse, id responseObject) {
        NSLog(@"%@", urlResponse);
        NSLog(@"%@", responseObject);
    } failure:^(NSError *error) {

    }];
    
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
    
//    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://qianmi-resources.oss-cn-hangzhou.aliyuncs.com/ares/app/sxxd_ios.ipa"]];
//    NSString *filePath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"1.ipa"];
//    NSURL *url = [NSURL fileURLWithPath:filePath];
//
//    [[ZLURLSessionManager shared] downloadWithRequest:request headers:nil destination:url progress:^(float progress) {
//        NSLog(@"progress:%.2f", progress * 100);
//    } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
//        NSLog(@"%@\n%@", response, filePath);
//    }];
    
//    self.imageView.image = [UIImage zl_imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"locate" ofType:@"png"]];
//    [self.imageView zl_setImageWithURL:[NSURL URLWithString:@"https://qianmi-resources.oss-cn-hangzhou.aliyuncs.com/60ed05864ceaef3ba3620ef9/IMAGE/04004116279755425641.jpg"] placeholderImage:[UIImage zl_imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"locate" ofType:@"png"]] progress:^(float progress) {
//
//    } completed:^(UIImage * _Nullable image, NSError * _Nullable error) {
//
//    }];
    NSLog(@"%@", [ZLURLSessionManager shared].workspaceDirURLString);
//    [self.imageView zl_setImageWithURL:[NSURL URLWithString:@"https://qianmi-resources.oss-cn-hangzhou.aliyuncs.com/60ed05864ceaef3ba3620ef9/IMAGE/04004116279755425641.jpg"]];
    [self.imageView zl_setImageWithURL:[NSURL URLWithString:@"https://qianmi-resources.oss-cn-hangzhou.aliyuncs.com/60ed05864ceaef3ba3620ef9/IMAGE/04004116279755425641.jpg"] placeholderImage:[UIImage zl_imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"locate" ofType:@"png"]] progress:^(float progress) {

    } completed:^(UIImage * _Nullable image, NSError * _Nullable error) {
        NSData *picData = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"测试中文.jpeg" ofType:nil]];
        self.imageView.image = [[UIImage imageWithData:picData] imageScaleForSize:CGSizeMake(240, 128) withCornerRadius:6 contentMode:ZLNetImageViewContentModeCenter];
    }];
    
//    NSData *data = [self.imageView.image zl_imageDataWithQuality:1];
//    [data writeToFile:@"/Users/xx/Desktop/zlnet.png" atomically:YES];
    
    ZLAnimatedImageView *imgView = [[ZLAnimatedImageView alloc] initWithFrame:CGRectMake(20, 240, 150, 150)];
//    NSData *gifData = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"sohucs.gif" ofType:nil]];
    [imgView zl_setImageWithURL:[NSURL URLWithString:@"http://qianmi-resources.oss-cn-hangzhou.aliyuncs.com/60ebb6ae4cea821670a9f77c/IMAGE/sohucs.gif"]];
//    imgView.image = [UIImage zl_animatedImageWithData:gifData scale:1];
    [self.view addSubview:imgView];
    
    NSArray *urls = @[@"https://qianmi-resources.oss-cn-hangzhou.aliyuncs.com/60ed05864ceaef3ba3620ef9/IMAGE/04004116279755425641.jpg", @"https://qianmi-resources.oss-cn-hangzhou.aliyuncs.com/60ebb6ae4cea821670a9f77c/IMAGE/9256481628653214370%E9%BB%84%E8%80%83%E6%8B%89.png", @"https://qianmi-resources.oss-cn-hangzhou.aliyuncs.com/60ebb6ae4cea821670a9f77c/IMAGE/5125451628653627702iShot2021-08-11%2011.46.59.png"];
    for (int i = 0; i < 100; ++i) {
        NSString *url = urls[arc4random() % urls.count];
        [self.items addObject:url];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZLImageTableViewCell *cell = (ZLImageTableViewCell *)[tableView dequeueReusableCellWithIdentifier:@"ZLImageTableViewCell" forIndexPath:indexPath];
    cell.titleLabel.text = [NSString stringWithFormat:@"title %ld", indexPath.row];
    NSURL *url = [NSURL URLWithString:self.items[indexPath.row]];
//    NSLog(@"%@", url);
    [cell.imageView zl_setImageWithURL:url placeholderImage:[UIImage imageNamed:@"WXACode.fa3d686a"]];
    return cell;
}

#pragma mark - webSocket delegate
- (NSURL *)webSocketReConnectURL {
    return [NSURL URLWithString:@"ws://172.19.3.11:8080/ws/OF001?a=bfdf"];
}

- (void)webSocketDidOpen:(ZLWebSocket *)webSocket {
    NSLog(@"%s", __FUNCTION__);
}

- (void)webSocket:(ZLWebSocket *)webSocket didFailWithError:(NSError *)error {
    NSLog(@"%s", __FUNCTION__);
}

- (void)webSocket:(ZLWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(nullable NSString *)reason wasClean:(BOOL)wasClean {
    NSLog(@"%s", __FUNCTION__);
}

- (void)webSocket:(ZLWebSocket *)webSocket didReceivePingWithData:(nullable NSData *)data {
    NSLog(@"------didReceivePingWithData---------%@", data);
}

- (void)webSocket:(ZLWebSocket *)webSocket didReceiveMessageWithString:(NSString *)string {
    NSLog(@"------didReceiveMessageWithString---------%@", string);
}

- (void)webSocket:(ZLWebSocket *)webSocket didReceiveMessageWithData:(NSData *)data {
    NSLog(@"------didReceiveMessageWithData---------%@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
}

- (void)webSocket:(ZLWebSocket *)webSocket didReceivePong:(nullable NSData *)pongData {
    NSLog(@"-------didReceivePong--------");
    [webSocket sendData:[@"tick" dataUsingEncoding:NSUTF8StringEncoding] error:nil];
}
@end
