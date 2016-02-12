//
//  AVCameraPainter.m
//  AVSimpleEditoriOS
//
//  Created by malczak on 04/11/14.
//
//

#import "AVCameraPainter.h"
#define degreesToRadian(x)  (M_PI * (x) / 180.0)

@interface AVCameraPainter () {
    CMTime startTime;
}

@property (nonatomic, strong) dispatch_semaphore_t dataUpdateSemaphore;
@property (nonatomic, copy) void(^originalFrameProcessingCompletionBlock)(GPUImageOutput*, CMTime);

@end

@implementation AVCameraPainter  {
}

@synthesize faceDetector;

#pragma mark -
#pragma mark Initialization and teardown

- (id)initWithSessionPreset:(NSString *)sessionPreset cameraPosition:(AVCaptureDevicePosition)cameraPosition
{
    self = [super init];
    if(self) {
        self.originalFrameProcessingCompletionBlock = nil;
        self.dataUpdateSemaphore = dispatch_semaphore_create(1);
        startTime = kCMTimeIndefinite;
        
        _composer = nil;
        _overlay = nil;

        _isCapturing = NO;
        _isRecording = NO;
        _isPaused = NO;
        
        self.shouldUseCaptureTime = NO;
        self.shouldCaptureAudio = NO;
        
        [self setComposer:[[GPUImageSourceOverBlendFilter alloc] init]];
        [self initCameraWithSessionPreset:sessionPreset position:cameraPosition];
        
        NSDictionary *detectorOptions = @{ CIDetectorAccuracy : CIDetectorAccuracyHigh, CIDetectorTracking : @TRUE};
        self.faceDetector = [CIDetector detectorOfType:CIDetectorTypeFace context:nil options:detectorOptions];
        faceThinking = NO;
    }
    return self;
}

-(void)initCameraWithSessionPreset:(NSString *)sessionPreset position:(AVCaptureDevicePosition)cameraPosition
{
    _camera = [[GPUImageVideoCamera alloc] initWithSessionPreset:sessionPreset cameraPosition:cameraPosition];
    _camera.delegate = self;

    NSAssert(_camera!=nil,@"Failed to create GPUImageVideoCamera instance");
    
    _camera.horizontallyMirrorFrontFacingCamera = NO;
    _camera.horizontallyMirrorRearFacingCamera = NO;
}

#pragma mark -
#pragma mark Manage classes and options

-(void) setComposer:(GPUImageTwoInputFilter *) framesComposer
{
    if(_isRecording || _isCapturing) {
        @throw [NSException exceptionWithName:@"Cannot set composer while capturing video" reason:nil userInfo:nil];
    }
    
    if(![framesComposer isKindOfClass:[GPUImageTwoInputFilter class]]) {
        @throw [NSException exceptionWithName:@"Expected GPUImageTwoInputFilter subclass"  reason:nil userInfo:nil];
    }
    
    _composer = framesComposer;
}

-(void) setOverlay:(AVFrameDrawer *) framesOverlay
{
    if(_isRecording || _isCapturing) {
        @throw [NSException exceptionWithName:@"Cannot set overlay while capturing video" reason:nil userInfo:nil];
    }

    if(![framesOverlay isKindOfClass:[AVFrameDrawer class]]) {
        @throw [NSException exceptionWithName:@"Expected AVFrameDrawer subclass"  reason:nil userInfo:nil];
    }
    
    _overlay = framesOverlay;
}

#pragma mark -
#pragma mark Manage the camera video stream

- (void)startCameraCapture;
{
    if(!_isCapturing) {
        [self initCameraCapture];
        [_camera startCameraCapture];
        _isCapturing = YES;
    }
}

- (void)stopCameraCapture;
{
    if(_isCapturing) {
        if(_isRecording) {
            [self stopCameraRecordingWithCompetionHandler:nil];
        }
        [_camera stopCameraCapture];
        [self freeCameraCapture];
        _isCapturing = NO;
    }
}

- (void)pauseCameraCapture;
{
    if(!_isPaused) {
        [_camera pauseCameraCapture];
        _isPaused = YES;
    }
}

- (void)resumeCameraCapture;
{
    if(_isPaused) {
        [_camera resumeCameraCapture];
        _isPaused = NO;
    }
}

#pragma mark -
#pragma mark Manage the camera recording

/** Start camera recording
 */
- (void)startCameraRecordingWithURL:(NSURL*) url size:(CGSize) size;
{
    if(!_isCapturing) {
        @throw [NSException exceptionWithName:@"Forgot to start camera capture?" reason:nil userInfo:nil];
    }

    if(!_isRecording) {
        [self initCameraRecordingWithURL:url size:size];
        _isRecording = YES;
    }
}

/** Stop camera recording
 */
- (void)stopCameraRecordingWithCompetionHandler:(void (^)(void))handler
{
    if(_isRecording) {
        [self freeCameraRecordingWithCompetionHandler:handler];
        _isRecording = NO;
    }
}

#pragma mark -
#pragma mark Private camera capture methods

-(void) initCameraCapture
{
    [_camera addTarget:_composer];
    
    if(_overlay != nil) {
        
        startTime = kCMTimeIndefinite;
        
        [_overlay addTarget:_composer];
        [_overlay processData];

        __weak AVFrameDrawer *weakOverlay = _overlay;
        __weak AVCameraPainter *weakSelf = self;
        
        self.originalFrameProcessingCompletionBlock = [_composer frameProcessingCompletionBlock];

        void(^frameProcessingCompletionBlock)(GPUImageOutput*, CMTime) = ^(GPUImageOutput* output, CMTime processingTime) {
            
            CMTime currentTime = processingTime;

            if(CMTIME_IS_INDEFINITE(startTime)) {
                startTime = processingTime;
            }
            
            __strong AVCameraPainter *strongSelf = weakSelf;
            if(strongSelf){
                if(strongSelf.originalFrameProcessingCompletionBlock) {
                    strongSelf.originalFrameProcessingCompletionBlock(output, processingTime);
                }
                
                currentTime = [strongSelf recordTime];
                if(CMTIME_IS_INDEFINITE(currentTime)) {
                    currentTime = strongSelf.shouldUseCaptureTime ? [strongSelf captureTime:processingTime] : kCMTimeZero;
                }
            }
            
            __strong AVFrameDrawer *strongOverlay = weakOverlay;
            if(strongOverlay) {
                [strongOverlay frameProcessingCompletionBlock](output, currentTime);
            }

        };
        
//        [fakeFilter setFrameProcessingCompletionBlock:frameProcessingCompletionBlock];
        [_composer setFrameProcessingCompletionBlock:frameProcessingCompletionBlock];
    }
    
    if(self.shouldCaptureAudio) {
        [_camera addAudioInputsAndOutputs];
    }
}

-(void) initCameraRecordingWithURL:(NSURL*) url size:(CGSize) size
{
    _writer = [[GPUImageMovieWriter alloc] initWithMovieURL:url size:size];
    [_composer addTarget:_writer];

    if(self.shouldCaptureAudio) {
        _camera.audioEncodingTarget = _writer;
    }
    
    _writer.encodingLiveVideo = YES;
    
    CGAffineTransform orientationTransform = CGAffineTransformIdentity;
    orientationTransform = CGAffineTransformMakeRotation(degreesToRadian(90));
    [_writer startRecordingInOrientation:orientationTransform];
}

-(void) freeCameraCapture
{
    self.originalFrameProcessingCompletionBlock = nil;
    
    if(_overlay != nil) {
        [_overlay removeTarget:_composer];
        [_composer setFrameProcessingCompletionBlock:nil];
    }
    
    [_camera removeTarget:_composer];
}

-(void) freeCameraRecordingWithCompetionHandler:(void (^)(void))handler
{
    _camera.audioEncodingTarget = nil;
    [_composer removeTarget:_writer];
    
    if (dispatch_semaphore_wait(self.dataUpdateSemaphore, DISPATCH_TIME_NOW) != 0)
    {
        return;
    }
    
    __weak AVCameraPainter *weakSelf = self;
    // set_sema
    [_writer finishRecordingWithCompletionHandler:^(){
        if(handler) {
            handler();
        }

        __strong AVCameraPainter *strongSelf = weakSelf;
        if(strongSelf) {
            [strongSelf destroyCameraWriter];
        }
        
    }];
}

-(void) destroyCameraWriter
{
    _writer = nil;
    dispatch_semaphore_signal(self.dataUpdateSemaphore);
}

#pragma mark - Handle capture / recording

-(CMTime) captureTime:(CMTime) processingTime {
    return CMTimeSubtract(processingTime, startTime);
}

-(CMTime) recordTime {
    return (_isRecording) ? _writer.duration : kCMTimeIndefinite;
}

#pragma mark - Deallocation

-(void)dealloc
{
    [self stopCameraCapture];

    _camera = nil;
    _overlay = nil;
    _composer = nil;
}

#pragma mark - Face Detection Delegate Callback
- (void)willOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer{
    if (!faceThinking) {
        CFAllocatorRef allocator = CFAllocatorGetDefault();
        CMSampleBufferRef sbufCopyOut;
        CMSampleBufferCreateCopy(allocator,sampleBuffer,&sbufCopyOut);
        [self performSelectorInBackground:@selector(grepFacesForSampleBuffer:) withObject:CFBridgingRelease(sbufCopyOut)];
    }
}

- (void)grepFacesForSampleBuffer:(CMSampleBufferRef)sampleBuffer{
    faceThinking = TRUE;
    NSLog(@"Faces thinking");
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate);
    CIImage *convertedImage = [[CIImage alloc] initWithCVPixelBuffer:pixelBuffer options:(__bridge NSDictionary *)attachments];
    
    if (attachments)
        CFRelease(attachments);
    NSDictionary *imageOptions = nil;
    UIDeviceOrientation curDeviceOrientation = [[UIDevice currentDevice] orientation];
    int exifOrientation;
    
    /* kCGImagePropertyOrientation values
     The intended display orientation of the image. If present, this key is a CFNumber value with the same value as defined
     by the TIFF and EXIF specifications -- see enumeration of integer constants.
     The value specified where the origin (0,0) of the image is located. If not present, a value of 1 is assumed.
     
     used when calling featuresInImage: options: The value for this key is an integer NSNumber from 1..8 as found in kCGImagePropertyOrientation.
     If present, the detection will be done based on that orientation but the coordinates in the returned features will still be based on those of the image. */
    
    enum {
        PHOTOS_EXIF_0ROW_TOP_0COL_LEFT			= 1, //   1  =  0th row is at the top, and 0th column is on the left (THE DEFAULT).
        PHOTOS_EXIF_0ROW_TOP_0COL_RIGHT			= 2, //   2  =  0th row is at the top, and 0th column is on the right.
        PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT      = 3, //   3  =  0th row is at the bottom, and 0th column is on the right.
        PHOTOS_EXIF_0ROW_BOTTOM_0COL_LEFT       = 4, //   4  =  0th row is at the bottom, and 0th column is on the left.
        PHOTOS_EXIF_0ROW_LEFT_0COL_TOP          = 5, //   5  =  0th row is on the left, and 0th column is the top.
        PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP         = 6, //   6  =  0th row is on the right, and 0th column is the top.
        PHOTOS_EXIF_0ROW_RIGHT_0COL_BOTTOM      = 7, //   7  =  0th row is on the right, and 0th column is the bottom.
        PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM       = 8  //   8  =  0th row is on the left, and 0th column is the bottom.
    };
    BOOL isUsingFrontFacingCamera = FALSE;
    AVCaptureDevicePosition currentCameraPosition = [_camera cameraPosition];
    
    if (currentCameraPosition != AVCaptureDevicePositionBack)
    {
        isUsingFrontFacingCamera = TRUE;
    }
    
    switch (curDeviceOrientation) {
        case UIDeviceOrientationPortraitUpsideDown:  // Device oriented vertically, home button on the top
            exifOrientation = PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM;
            break;
        case UIDeviceOrientationLandscapeLeft:       // Device oriented horizontally, home button on the right
            if (isUsingFrontFacingCamera)
                exifOrientation = PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT;
            else
                exifOrientation = PHOTOS_EXIF_0ROW_TOP_0COL_LEFT;
            break;
        case UIDeviceOrientationLandscapeRight:      // Device oriented horizontally, home button on the left
            if (isUsingFrontFacingCamera)
                exifOrientation = PHOTOS_EXIF_0ROW_TOP_0COL_LEFT;
            else
                exifOrientation = PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT;
            break;
        case UIDeviceOrientationPortrait:            // Device oriented vertically, home button on the bottom
        default:
            exifOrientation = PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP;
            break;
    }
    
    imageOptions = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:exifOrientation] forKey:CIDetectorImageOrientation];
    
    NSArray *features = [self.faceDetector featuresInImage:convertedImage options:imageOptions];
    
    NSLog(@"No. of faces detected %lu", (unsigned long)features.count);
    //NSLog(@"No of faces %d", features.count);
    
    // get the clean aperture
    // the clean aperture is a rectangle that defines the portion of the encoded pixel dimensions
    // that represents image data valid for display.
    CMFormatDescriptionRef fdesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    CGRect clap = CMVideoFormatDescriptionGetCleanAperture(fdesc, false /*originIsTopLeft == false*/);
    
    [self.delegate GPUVCWillOutputFeatures:features forClap:clap andOrientation:curDeviceOrientation];
    faceThinking = FALSE;
}

//
//- (void)grepFacesForSampleBuffer:(CMSampleBufferRef)sampleBuffer
//{
//    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
//    CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate);
//    CIImage *convertedImage = [[CIImage alloc] initWithCVPixelBuffer:pixelBuffer options:(__bridge NSDictionary *)attachments];
//
//    if (attachments)
//    {
//        CFRelease(attachments);
//    }
//    
//    NSDictionary *imageOptions = nil;
//    UIDeviceOrientation curDeviceOrientation = [[UIDevice currentDevice] orientation];
//    int exifOrientation;
//
//    /* kCGImagePropertyOrientation values
//     The intended display orientation of the image. If present, this key is a CFNumber value with the same value as defined
//     by the TIFF and EXIF specifications -- see enumeration of integer constants.
//     The value specified where the origin (0,0) of the image is located. If not present, a value of 1 is assumed.
//
//     used when calling featuresInImage: options: The value for this key is an integer NSNumber from 1..8 as found in kCGImagePropertyOrientation.
//     If present, the detection will be done based on that orientation but the coordinates in the returned features will still be based on those of the image. */
//
//    enum {
//        PHOTOS_EXIF_0ROW_TOP_0COL_LEFT			= 1, //   1  =  0th row is at the top, and 0th column is on the left (THE DEFAULT).
//        PHOTOS_EXIF_0ROW_TOP_0COL_RIGHT			= 2, //   2  =  0th row is at the top, and 0th column is on the right.
//        PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT      = 3, //   3  =  0th row is at the bottom, and 0th column is on the right.
//        PHOTOS_EXIF_0ROW_BOTTOM_0COL_LEFT       = 4, //   4  =  0th row is at the bottom, and 0th column is on the left.
//        PHOTOS_EXIF_0ROW_LEFT_0COL_TOP          = 5, //   5  =  0th row is on the left, and 0th column is the top.
//        PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP         = 6, //   6  =  0th row is on the right, and 0th column is the top.
//        PHOTOS_EXIF_0ROW_RIGHT_0COL_BOTTOM      = 7, //   7  =  0th row is on the right, and 0th column is the bottom.
//        PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM       = 8  //   8  =  0th row is on the left, and 0th column is the bottom.
//    };
//    BOOL isUsingFrontFacingCamera = FALSE;
//    AVCaptureDevicePosition currentCameraPosition = [_camera cameraPosition];
//
//    if (currentCameraPosition != AVCaptureDevicePositionBack)
//    {
//        isUsingFrontFacingCamera = TRUE;
//    }
//
//    switch (curDeviceOrientation) {
//        case UIDeviceOrientationPortraitUpsideDown:  // Device oriented vertically, home button on the top
//            exifOrientation = PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM;
//            break;
//        case UIDeviceOrientationLandscapeLeft:       // Device oriented horizontally, home button on the right
//            if (isUsingFrontFacingCamera)
//                exifOrientation = PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT;
//            else
//                exifOrientation = PHOTOS_EXIF_0ROW_TOP_0COL_LEFT;
//            break;
//        case UIDeviceOrientationLandscapeRight:      // Device oriented horizontally, home button on the left
//            if (isUsingFrontFacingCamera)
//                exifOrientation = PHOTOS_EXIF_0ROW_TOP_0COL_LEFT;
//            else
//                exifOrientation = PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT;
//            break;
//        case UIDeviceOrientationPortrait:            // Device oriented vertically, home button on the bottom
//        default:
//            exifOrientation = PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP;
//            break;
//    }
//
//    imageOptions = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:exifOrientation] forKey:CIDetectorImageOrientation];
//
//    //NSLog(@"Face Detector %@", [self.faceDetector description]);
//    NSArray *features = [self.faceDetector featuresInImage:convertedImage options:imageOptions];
//    
//    NSLog(@"No. of faces detected %d", features.count);
//
//        // get the clean aperture
//        // the clean aperture is a rectangle that defines the portion of the encoded pixel dimensions
//        // that represents image data valid for display.
//        CMFormatDescriptionRef fdesc = CMSampleBufferGetFormatDescription(sampleBuffer);
//        CGRect clap = CMVideoFormatDescriptionGetCleanAperture(fdesc, false /*originIsTopLeft == false*/);
//        [self.delegate GPUVCWillOutputFeatures:features forClap:clap andOrientation:curDeviceOrientation];
//
//}

@end
