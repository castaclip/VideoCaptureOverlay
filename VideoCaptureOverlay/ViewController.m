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
    
    CGRect currentFaceRect;
    CGRect priorCenter;
    UIImage *image;
    UIImage * sticker;
}

@property (nonatomic, weak) IBOutlet UIButton *recordButton;

@end

@implementation ViewController

// hd - like a boss
static CGFloat targetWidth = 1280.0;
static CGFloat targetHeight = 720.0;

static NSUInteger videoDurationInSec = 240; // 4min+


- (void)viewDidLoad {
    [super viewDidLoad];
    
    faceView = [[UIView alloc] initWithFrame:CGRectMake(100.0, 100.0, 100.0, 100.0)];
    faceView.layer.borderWidth = 1;
    faceView.layer.borderColor = [[UIColor redColor] CGColor];
    [self.view addSubview:faceView];
    faceView.hidden = NO;
    
    sticker = [UIImage imageNamed:@"sprite_cool_01.png"];
    image = [UIImage imageWithCGImage:sticker.CGImage scale:1.0 orientation:UIImageOrientationLeft];
    priorCenter = CGRectZero;
    
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
    painter = [[AVCameraPainter alloc] initWithSessionPreset:AVCaptureSessionPreset1280x720 cameraPosition:AVCaptureDevicePositionFront];
    painter.shouldCaptureAudio = YES;
    painter.camera.outputImageOrientation = UIInterfaceOrientationMaskLandscapeRight;
    painter.delegate = self;
    
//    if (painter.camera.cameraPosition == AVCaptureDevicePositionFront)
//    {
//        //[cameraPreview setInputRotation:kGPUImageNoRotation atIndex:0];
//        [cameraPreview setInputRotation:kGPUImageFlipHorizonal atIndex:0];
//    }
    
    
    // context initialization - block (we dont want to overload class in this example)
    void (^contextInitialization)(CGContextRef context, CGSize size) = ^(CGContextRef context, CGSize size) {
        //CGContextClearRect(context, CGRectMake(0, 0, size.width, size.height));
        
//        CGContextSetRGBFillColor(context, 0.0, 1.0, 0.0, 0.5);
//        CGContextFillRect(context, CGRectMake(0, 0, size.width*0.3, size.height*0.8));
//        
//        CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 0.7);
//        CGContextFillEllipseInRect(context, CGRectMake(0, 0, size.width*0.5, size.height*0.4));
//        
//        NSString *fontName = @"Courier-Bold";
//        CGContextSelectFont(context, [fontName UTF8String], 18, kCGEncodingMacRoman);
//        
//        CGContextSetRGBFillColor(context, 1, 0, 0, 1);
//        NSString *s = @"Just running this ...";
//        CGContextShowTextAtPoint(context, 10, 10, [s UTF8String], s.length);
    };
    
    // create overlay + some code
    frameDrawer = [[AVFrameDrawer alloc] initWithSize:CGSizeMake(targetWidth, targetHeight)
                               contextInitailizeBlock:contextInitialization];
    
    frameDrawer.contextUpdateBlock = ^BOOL(CGContextRef context, CGSize size, CMTime time) {
        CGContextClearRect(context, CGRectMake(0, 0, size.width, size.height));

        float imageSize = MIN(currentFaceRect.size.width, currentFaceRect.size.height);
        UIGraphicsBeginImageContext(image.size);
        UIGraphicsPushContext(context);
        
        [image drawInRect:CGRectMake(currentFaceRect.origin.x, currentFaceRect.origin.y, imageSize, imageSize)];
        
        UIGraphicsPopContext();
        UIGraphicsEndImageContext();

        return YES;
    };
    
    // setup composer, preview and painter all together
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
    NSLog(@"Did receive array");

    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"Did receive array");
        
        if ([featureArray count] > 0) {
            CIFaceFeature *faceFeature = featureArray[0];
            if (faceFeature.hasRightEyePosition && faceFeature.hasLeftEyePosition) {
                currentFaceRect = [faceFeature bounds];
                
                if(priorCenter.origin.x == 0) {
                    priorCenter = currentFaceRect;
                    return;
                }
                
                if (ABS(currentFaceRect.origin.x - priorCenter.origin.x) < 7 &&
                    ABS(currentFaceRect.origin.y - priorCenter.origin.y) < 7)
                {
                    currentFaceRect = priorCenter;
                }
                
                currentFaceRect.origin.x = (currentFaceRect.origin.x + 2*priorCenter.origin.x) / 3;
                currentFaceRect.origin.y = (currentFaceRect.origin.y + 2*priorCenter.origin.y) / 3;
                priorCenter = currentFaceRect;
            }
        }
        
//        CGRect previewBox = self.view.frame;
//        
//        if (featureArray == nil && faceView) {
//            [faceView removeFromSuperview];
//            faceView = nil;
//        }
//        
//        
//        for ( CIFaceFeature *faceFeature in featureArray) {
//            
//            [self logFacialFeatureCoordinates:faceFeature];
//            
//            // find the correct position for the square layer within the previewLayer
//            // the feature box originates in the bottom left of the video frame.
//            // (Bottom right if mirroring is turned on)
//            NSLog(@"%@", NSStringFromCGRect([faceFeature bounds]));
//            
//            //Update face bounds for iOS Coordinate System
//            CGRect faceRect = [faceFeature bounds];
//            
//            // flip preview width and height
//            CGFloat temp = faceRect.size.width;
//            faceRect.size.width = faceRect.size.height;
//            faceRect.size.height = temp;
//            temp = faceRect.origin.x;
//            faceRect.origin.x = faceRect.origin.y;
//            faceRect.origin.y = temp;
//            // scale coordinates so they fit in the preview box, which may be scaled
//            CGFloat widthScaleBy = previewBox.size.width / clap.size.height;
//            CGFloat heightScaleBy = previewBox.size.height / clap.size.width;
//            faceRect.size.width *= widthScaleBy;
//            faceRect.size.height *= heightScaleBy;
//            faceRect.origin.x *= widthScaleBy;
//            faceRect.origin.y *= heightScaleBy;
//            
//            faceRect = CGRectOffset(faceRect, previewBox.origin.x, previewBox.origin.y);
//            
//            if (faceView) {
//                [faceView removeFromSuperview];
//                faceView =  nil;
//            }
//            
//            // create a UIView using the bounds of the face
//            faceView = [[UIView alloc] initWithFrame:faceRect];
//            
//            // add a border around the newly created UIView
//            faceView.layer.borderWidth = 1;
//            faceView.layer.borderColor = [[UIColor redColor] CGColor];
//            
//            // add the new view to create a box around the face
//            [self.view addSubview:faceView];
//            
//            //            if (recording == TRUE) {
//            ////                [self startScreenCapture]
//            //                startScreenCapture(view);
//            //            }
        
        //}
    });
    
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
