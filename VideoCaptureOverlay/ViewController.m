//
//  ViewController.m
//  VideoCaptureOverlay
//
//  Created by malczak on 04/11/14.
//  Copyright (c) 2014 segfaultsoft. All rights reserved.
//

#import <AssetsLibrary/AssetsLibrary.h>
#import <SVProgressHUD.h>
#import "ViewController.h"
#import "AVFrameDrawer.h"
#import "AVCameraPainter.h"

@interface ViewController () <AVCameraPainterDelegate> {
    GPUImageView *cameraPreview;
    AVCameraPainter *painter;
    AVFrameDrawer *frameDrawer;
    
    NSURL *outUrl;
    
    CGRect center;
    
    UIImage *image;
    UIImage * sticker;
}

@property (nonatomic, weak) IBOutlet UIButton *recordButton;

@end

@implementation ViewController

// hd - like a boss
static CGFloat targetWidth = 960.0;
static CGFloat targetHeight = 540.0;
static CGFloat ACCURACY = 0.94;

static NSUInteger videoDurationInSec = 240; // 4min+


- (void)viewDidLoad {
    [super viewDidLoad];
    
    sticker = [UIImage imageNamed:@"sprite_cool_01.png"];
    image = [UIImage imageWithCGImage:sticker.CGImage scale:1.0 orientation:UIImageOrientationLeft];
    
    center = CGRectZero;
    
    // create camera preview
    [self createCameraPreview];
    
    // init capture session and pass it to preview
    [self initCameraCapture];
    
    [self.recordButton addTarget:self action:@selector(recordButtonHandler:) forControlEvents:UIControlEventTouchUpInside];
}

#pragma mark -
#pragma mark - Record button

-(void) recordButtonHandler:(id) sender
{
    if(painter.isRecording) {
        [self stopCameraCapture];
    } else {
        [self startCameraCapture];        
    }
}

#pragma mark -
#pragma mark - Initialize camera preview view

-(void) createCameraPreview
{
    CGRect screen = [[UIScreen mainScreen] bounds];
    
    CGRect rect = CGRectMake(0, 0, screen.size.height, screen.size.width);
    CGAffineTransform T = CGAffineTransformIdentity;
    
    T = CGAffineTransformTranslate(T, -rect.size.width * 0.5, -rect.size.height * 0.5);
    T = CGAffineTransformRotate(T, M_PI_2);
    T = CGAffineTransformTranslate(T, rect.size.width * 0.5, -rect.size.height * 0.5);
    
    cameraPreview = [[GPUImageView alloc] initWithFrame:rect];
    cameraPreview.transform = T;
    cameraPreview.fillMode = kGPUImageFillModePreserveAspectRatio;
    
    [self.view insertSubview:cameraPreview atIndex:0];
}

#pragma mark -
#pragma mark - Initialize camera capture

-(void) initCameraCapture
{
    // create video painter
    painter = [[AVCameraPainter alloc] initWithSessionPreset:AVCaptureSessionPresetiFrame960x540 cameraPosition:AVCaptureDevicePositionFront];
    painter.shouldCaptureAudio = YES;
    painter.camera.outputImageOrientation = UIInterfaceOrientationMaskLandscapeRight;
    painter.delegate = self;
    
    // context initialization - block (we dont want to overload class in this example)
    void (^contextInitialization)(CGContextRef context, CGSize size) = ^(CGContextRef context, CGSize size) {
      
    };
    
    // create overlay + some code
    frameDrawer = [[AVFrameDrawer alloc] initWithSize:CGSizeMake(targetWidth, targetHeight)
                               contextInitailizeBlock:contextInitialization];
    
    frameDrawer.contextUpdateBlock = ^BOOL(CGContextRef context, CGSize size, CMTime time) {
        
        CGContextClearRect(context, CGRectMake(0, 0, size.width, size.height));
        float imageSize = MIN(center.size.width, center.size.height);
                
        UIGraphicsBeginImageContext(image.size);
        UIGraphicsPushContext(context);
        
        [image drawInRect:CGRectMake(center.origin.x + 150, center.origin.y, imageSize, imageSize)];
        
        UIGraphicsPopContext();
        UIGraphicsEndImageContext();

        return YES;
    };
    
    [painter.composer addTarget:cameraPreview];
    [painter setOverlay:frameDrawer];
    [painter startCameraCapture];
}

#pragma mark -
#pragma mark - Handler camera capture

-(void) startCameraCapture
{
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"file.mov"];
    outUrl = [NSURL fileURLWithPath:path];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:path error:nil];
    
    NSLog(@"Recording ...");
    
    [painter startCameraRecordingWithURL:outUrl size:CGSizeMake(targetWidth, targetHeight)];
    
    __weak ViewController *weakSelf = self;

    int64_t stopDelay = (int64_t)(videoDurationInSec * NSEC_PER_SEC);
    dispatch_time_t autoStopTime = dispatch_time(DISPATCH_TIME_NOW, stopDelay);
    
    dispatch_after(autoStopTime, dispatch_get_main_queue(), ^{
        [weakSelf stopCameraCapture];
    });
 
    [self.recordButton setTitle:@"STOP" forState:UIControlStateNormal];
}

-(void) stopCameraCapture
{
    if(!painter.isRecording) {
        return;
    }
    
    NSURL *movieUrl = outUrl;
    
    __weak ViewController *weakSelf = self;
    
    [painter stopCameraRecordingWithCompetionHandler:^(){
        
        dispatch_async(dispatch_get_main_queue(), ^(){
            NSLog(@"Recorded :/");
            [SVProgressHUD showWithStatus:@"Exporting..."];
            
            [weakSelf.recordButton setTitle:@"Record" forState:UIControlStateNormal];
            
            ALAssetsLibrary *assetsLibrary = [[ALAssetsLibrary alloc] init];
            if ([assetsLibrary videoAtPathIsCompatibleWithSavedPhotosAlbum:movieUrl]) {
                [assetsLibrary writeVideoAtPathToSavedPhotosAlbum:movieUrl completionBlock:^(NSURL *assetURL, NSError *error){
                    
                    dispatch_async(dispatch_get_main_queue(), ^(){
                        [SVProgressHUD showSuccessWithStatus:@"File saved in photo..."];
                    });
                    
                }];
            }
        });
    }];
}

#pragma mark -
#pragma mark - Handle dark side

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    NSLog(@"Darkness it getting closer... run... run... you fools!");
}

-(void)dealloc
{
    // Nooooooooo
}

#pragma mark -
#pragma mark - Handle face detection

- (void)GPUVCWillOutputFeatures:(NSArray*)featureArray forClap:(CGRect)clap
                 andOrientation:(UIDeviceOrientation)curDeviceOrientation
{
    dispatch_async(dispatch_get_main_queue(), ^{
        
        if ([featureArray count] > 0) {
            
            CIFaceFeature *faceFeature = featureArray[0];
            CGRect rect = [faceFeature bounds];
            
            if (true)
            {
                [self processBasedOnEyes:faceFeature :rect];
            } else
            {
                [self processBasedOnMouth:faceFeature :rect];
            }
            
        }
    });
}

- (void) processBasedOnEyes:(CIFaceFeature *) feature : (CGRect)rect
{
    if (feature.hasLeftEyePosition && feature.hasRightEyePosition) {
        rect.origin.x = (feature.leftEyePosition.x + feature.rightEyePosition.x) / 2;
        rect.origin.y = (feature.leftEyePosition.y + feature.rightEyePosition.y) / 2;
        
        rect.origin.x  = ABS(rect.origin.x - rect.size.width/2);
        rect.origin.y  = ABS(rect.origin.y - rect.size.height/2);
        
        CGFloat percentage = [self getOverlappingPercentage:rect :center];
        NSLog(@"Percentage Overlay : %f", percentage);
        
        if (percentage >= ACCURACY)
        {
            rect = center;
        }
        
        // Smooth new center compared to old center
        rect.origin.x = (rect.origin.x + 2 * center.origin.x) / 3;
        rect.origin.y = (rect.origin.y + 2 * center.origin.y) / 3;
        
        center = rect;
    }
}

- (void) processBasedOnMouth:(CIFaceFeature *) feature : (CGRect)rect
{
    if (feature.hasMouthPosition) {
        rect.origin.x = feature.mouthPosition.x;
        rect.origin.y = feature.mouthPosition.y;
        
        rect.origin.x  = ABS(rect.origin.x - rect.size.width/2);
        rect.origin.y  = ABS(rect.origin.y - rect.size.height/2);
        
        CGFloat percentage = [self getOverlappingPercentage:rect :center];
        NSLog(@"Percentage Overlay : %f", percentage);
        
        if (percentage >= ACCURACY)
        {
            rect = center;
        }
        
        // Smooth new center compared to old center
        rect.origin.x = (rect.origin.x + 2 * center.origin.x) / 3;
        rect.origin.y = (rect.origin.y + 2 * center.origin.y) / 3;
        
        center = rect;
    }
}

-(CGFloat) getOverlappingPercentage:(CGRect)r1 :(CGRect)r2
{
    CGRect interRect = CGRectIntersection(r1, r2);
    return (interRect.size.width * interRect.size.height) / (((r1.size.width * r1.size.height) + (r2.size.width * r2.size.height))/2.0);
}

- (void) logFacialFeatureCoordinates:(CIFaceFeature *) f
{
    NSLog(@"left eye found: %@", (f. hasLeftEyePosition ? @"YES" : @"NO"));
    NSLog(@"right eye found: %@", (f. hasRightEyePosition ? @"YES" : @"NO"));
    NSLog(@"mouth found: %@", (f. hasMouthPosition ? @"YES" : @"NO"));
    
    if(f.hasLeftEyePosition)
    {
        NSLog(@"left eye position x = %f , y = %f", f.leftEyePosition.x, f.leftEyePosition.y);
    }
    
    if(f.hasRightEyePosition)
    {
        NSLog(@"right eye position x = %f , y = %f", f.rightEyePosition.x, f.rightEyePosition.y);
    }
    
    if(f.hasMouthPosition)
    {
        NSLog(@"mouth position x = %f , y = %f", f.mouthPosition.x, f.mouthPosition.y);
    }
}

@end
