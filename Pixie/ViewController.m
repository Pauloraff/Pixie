//
//  ViewController.m
//  Pixie
//
//  Created by Paulo Raffaelli on 11/24/19.
//  Copyright © 2019 Paulo Raffaelli. All rights reserved.
//

#import "ViewController.h"
#include <stdlib.h>
#include <stddef.h>

extern void * malloc(size_t nbytes);

#define MAXDISPLAYS 4

typedef struct {
    uint32_t displayCount;
    CGRect fullExtent;
    struct {
        CGDirectDisplayID displayID;
        CGRect bounds;
        dispatch_queue_t queue;
        CGDisplayStreamRef stream;
    } entry[MAXDISPLAYS];
    
    NSImageView * theImageView;
} ScreenLayout;

ScreenLayout theLayout;

// hack to have program exit after N sceen updates
int nUpdates = 0;
#define EXIT_AFTER_NUPDATES 1000

#define PERMISSION_WAIT_QUANTUM   0.5
#define PERMISSION_WAIT_DURATION 30.0

NSImage * theImage = nil;
UInt scaling = 1;
CGSize targetImageSize;

void clearScreenLayout(ScreenLayout * layout) {
    layout->displayCount = 0;
    layout->fullExtent = CGRectZero;
    
    for (size_t n = 0; n < MAXDISPLAYS; n++) {
        layout->entry[n].displayID = 0;
        layout->entry[n].bounds = CGRectZero;
        layout->entry[n].queue = NULL;
        layout->entry[n].stream = NULL;
    }
}

void recalculateFullDisplaySurface(ScreenLayout * layout) {
    // Get a list of displays.  Copied from working apple source code.
    CGDirectDisplayID displays[MAXDISPLAYS];
    
    CGGetActiveDisplayList(MAXDISPLAYS, displays, &(layout->displayCount));
    
    // boolean_t CGDisplayIsMain(CGDirectDisplayID display);
    CGRect full = CGRectZero;
    
    for (size_t n = 0; n < layout->displayCount; n++) {
        layout->entry[n].displayID = displays[n];
        layout->entry[n].bounds = CGDisplayBounds(layout->entry[n].displayID);
        
        char queue_name[32];
        sprintf(queue_name, "queue %d", (int)n);
        layout->entry[n].queue = dispatch_queue_create(queue_name, NULL);
        full = CGRectUnion(full, layout->entry[n].bounds);
    }
    layout->fullExtent = full;
}

int indexForDisplay(ScreenLayout * layout, CGDirectDisplayID displayID) {
    for (int n = 0; n < layout->displayCount; n++) {
        if (layout->entry[n].displayID) {
            return (int)n;
        }
    }
    
    return -1;
}

void callbackForStream(ScreenLayout * layout, size_t n, CGDisplayStreamFrameStatus status, uint64_t displayTime, IOSurfaceRef frameSurface, CGDisplayStreamUpdateRef updateRef) {
    if (kCGDisplayStreamFrameStatusFrameComplete == status) {
        // Get: pixel format
        CFDictionaryRef d = IOSurfaceCopyAllValues(frameSurface);
        CFIndex i = CFDictionaryGetCount(d);
        const void * keys = malloc(sizeof(uintptr_t) * i);
        const void * values = malloc(sizeof(uintptr_t) * i);
        
        CFDictionaryGetKeysAndValues(d, &keys, &values);
        
        // debugging
        // scaling = 1;
        
        NSPoint mouseLoc = [NSEvent mouseLocation]; //get current mouse position
        mouseLoc.y = layout->fullExtent.size.height - mouseLoc.y;
        
        // we have the mouse location, now grab the 'source rect' from the image data
        // get the view controller's view width and height
        // scale down by the scale factor
        // add one pixel in each direction
        uint32_t seed;
        kern_return_t locker = IOSurfaceLock(frameSurface, kIOSurfaceLockReadOnly, &seed);
        void * buffer = IOSurfaceGetBaseAddress(frameSurface);
        
        size_t elementSize = IOSurfaceGetBytesPerElement(frameSurface);
        size_t width = IOSurfaceGetWidth(frameSurface);
        size_t height = IOSurfaceGetHeight(frameSurface);
        size_t sourceBytesPerRow = IOSurfaceGetBytesPerRow(frameSurface);
        OSType pixelFormat = IOSurfaceGetPixelFormat(frameSurface);
        
        // For now, use a fixed scaling factor of N
        // source window is centered at mouseLoc
        // source window size is dest window size / scaling
        CGSize destSize = CGSizeMake( targetImageSize.width, targetImageSize.height );
        
        CGSize sourceSize = CGSizeMake( destSize.width / scaling, destSize.height / scaling );
        CGRect sourceRect = CGRectMake( mouseLoc.x - (sourceSize.width / 2.0), mouseLoc.y  - (sourceSize.height / 2.0),
                                       sourceSize.width, sourceSize.height );
        
        
        if (sourceRect.origin.x < 0.0) {
            sourceRect.origin.x = 0.0;
        }
        if (sourceRect.origin.y < 0.0) {
            sourceRect.origin.y = 0.0;
        }
        if ((sourceRect.origin.x+sourceRect.size.width) >= width) {
            sourceRect.origin.x = width - sourceRect.size.width;
        }
        if ((sourceRect.origin.y+sourceRect.size.height) >= height) {
            sourceRect.origin.y = height - sourceRect.size.height;
        }
        
        // The scaling buffer is (destSize.width * destSize.height) - i.e, it's exactly the size of the destination.
        size_t bufferLen = (size_t)(destSize.width) * (size_t)elementSize * (size_t)destSize.height;
        uint8_t * imageBuffer = malloc(bufferLen);
        uint8_t * destPtr = imageBuffer;
        size_t    destBytesPerRow = (size_t)destSize.width * (size_t)elementSize;
        
        uint8_t * sourcePtr = ((uint8_t *)buffer) + ((size_t)sourceRect.origin.y * sourceBytesPerRow); // start of top row
        uint8_t * startOfDestRow = destPtr;
        
        // each iteration fills 'scaling' rows of the estination;
        // the last iteration may fill < scaling rows
        uint8_t * startOfSourceRow = sourcePtr;
        size_t srcXOffset = ((size_t)sourceRect.origin.x * (size_t)elementSize);
        
        int row = 0;
        int offsets[4] = { 0, 1, 2, 3 }; // RGBA
        
        if (pixelFormat == 'BGRA') {
            offsets[0] = 2;
            offsets[1] = 1;
            offsets[2] = 0;
            offsets[3] = 3;
        }
        
        for (int y = 0; y < sourceRect.size.height; y++) {
            sourcePtr = startOfSourceRow;
            // move sourcePtr over sourceRect.origin.x pixels
            sourcePtr += srcXOffset;
            
            // start copying the first row into the destination, expanding as we go
            if (elementSize != 4) {
                break;
            }
            
            for (int x = 0; x < destSize.width; ) {
                destPtr[0] = sourcePtr[offsets[0]];
                destPtr[1] = sourcePtr[offsets[1]];
                destPtr[2] = sourcePtr[offsets[2]];
                destPtr[3] = sourcePtr[offsets[3]];

                x++;
                destPtr += elementSize;
                sourcePtr += elementSize; // one pixel

                for (int i = 1; i < scaling; i++) {
                    if (x >= destSize.width) {
                        break;
                    }
                    memcpy(destPtr, destPtr - elementSize, elementSize);
                    
                    x++;
                    destPtr += elementSize;
                }
            }
            
            row++;
            
            // sourcePtr is elementSize * scaling * destSize.width offset from startOfSourceRow
            
            // copy the first expanded row into the next n-1 rows
            // copy () bytes from startOfDestRow to startOfDestRow + (destBytesPerRow, destBytesPerRow*2, ...)
            for (int i = 1; i < scaling && (row < destSize.height); i++) {
                memcpy(startOfDestRow + (destBytesPerRow * i), startOfDestRow, destBytesPerRow);
                row++;
            }
            
            
            startOfDestRow = startOfDestRow + (destBytesPerRow * scaling);
            destPtr = startOfDestRow;

            // make sure sourcePtr is at the start of the next row,
            startOfSourceRow += sourceBytesPerRow;
            
            if ((destPtr - ((uint8_t *)imageBuffer)) >= bufferLen) {
                break;
            }
        }
        
        CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, imageBuffer, bufferLen, NULL);
        size_t bitsPerComponent = 8;
        size_t bitsPerPixel = 32;
        CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
        CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedLast;
        CGColorRenderingIntent renderingIntent = kCGRenderingIntentDefault;
        
        CGImageRef iref = CGImageCreate(destSize.width,
                                        destSize.height,
                                        bitsPerComponent,
                                        bitsPerPixel,
                                        destSize.width * (size_t)elementSize,
                                        colorSpaceRef,
                                        bitmapInfo,
                                        provider,   // data provider
                                        NULL,       // decode
                                        YES,        // should interpolate
                                        renderingIntent);
        
        // we need to get
        if (theImage != nil) {
            theImage = nil;
        }
        theImage = [[NSImage alloc] initWithCGImage:iref size:destSize];
        
        CGDataProviderRelease(provider);
        
        IOSurfaceUnlock(frameSurface, kIOSurfaceLockReadOnly, &seed);
        
        // NSLog(@"Update for display %d...\n", (int)n );
        dispatch_async(dispatch_get_main_queue(), ^(){
            layout->theImageView.image = theImage;
        });
        nUpdates++;
        // NSLog(@"%d %d.", (int)n, (int)nUpdates);
    } else if (kCGDisplayStreamFrameStatusFrameIdle == status) {
        NSLog(@"Display %d idle\n", (int)n );
    } else if (kCGDisplayStreamFrameStatusFrameBlank == status) {
        NSLog(@"Display %d blank\n", (int)n );
    } else if (kCGDisplayStreamFrameStatusStopped == status) {
        // the stream was stopped, we can clear it up now
        layout->entry[n].stream = NULL;
        // shuffle the entries down
        NSLog(@"Display %d stopped\n", (int)n );
        
        NSLog(@"RECALCULATE EXTENTS" );
    } else {
        NSLog(@"Display %d unrecognized status %u\n", (int)n, (uint32_t)status );
    }
}

void addStreamForDisplay(ScreenLayout * layout, size_t n) {
    if (layout->entry[n].stream != NULL) {
        NSLog(@"addStreamForDisplay %d: stream already exists\n", (int)n );
    } else {
        // kCGDisplayStreamSourceRect: omit, we want all of the display to be streamed
        // kCGDisplayStreamShowCursor: YES
        // kCGDisplayStreamMinimumFrameTime: 1 / 30 sec
        // kCGDisplayStreamQueueDepth: default value is 3.
        
        const void *keys[1] = { kCGDisplayStreamShowCursor };
        const void *values[1] = { kCFBooleanTrue };
        CFDictionaryRef properties = CFDictionaryCreate(NULL, keys, values, 1, NULL, NULL);
        
        layout->entry[n].stream = CGDisplayStreamCreateWithDispatchQueue(
                                                                         layout->entry[n].displayID,
                                                                         (int)layout->entry[n].bounds.size.width,
                                                                         (int)layout->entry[n].bounds.size.height,
                                                                         'BGRA', properties,
                                                                         layout->entry[n].queue,
                                                                         ^(CGDisplayStreamFrameStatus status, uint64_t displayTime, IOSurfaceRef frameSurface, CGDisplayStreamUpdateRef updateRef) {
            callbackForStream(layout, n, status, displayTime, frameSurface, updateRef);
        });
        
        if (layout->entry[n].stream == NULL) {
            NSLog(@"addStreamForDisplay %d: stream is NULL, permissions?...\n", (int)n );
        } else {
            NSLog(@"addStreamForDisplay %d: stream added, starting...\n", (int)n );
            CGError stream_err = CGDisplayStreamStart(layout->entry[n].stream);
            if (stream_err == CGDisplayNoErr) {
                NSLog(@"Works: stream for display %d started SUCCESS", (int)n);
            } else {
                NSLog(@"Error: stream for display %d start error %d", (int)n, stream_err);
            }
        }
    }
}

void removeStreamForDisplay(ScreenLayout * layout, size_t n) {
    if (layout->entry[n].stream == NULL) {
        NSLog(@"removeStreamForDisplay %d: stream is NULL\n", (int)n );
    } else {
        CGError stream_err = CGDisplayStreamStop(layout->entry[n].stream);
        if (stream_err == CGDisplayNoErr) {
            NSLog(@"Works: stream for display %d stopped, waiting...", (int)n);
        } else {
            NSLog(@"Error: stream for display %d stop error %d", (int)n, stream_err);
        }
    }
}

void recalculateDisplayExtents(ScreenLayout * layout) {
    CGRect full = CGRectZero;
    
    for (size_t n = 0; n < layout->displayCount; n++) {
        layout->entry[n].bounds = CGDisplayBounds(layout->entry[n].displayID);
        
        char queue_name[32];
        sprintf(queue_name, "queue %d", (int)n);
        layout->entry[n].queue = dispatch_queue_create(queue_name, NULL);
        full = CGRectUnion(full, layout->entry[n].bounds);
    }
    layout->fullExtent = full;
}

void addDisplay(CGDirectDisplayID displayID) {
    if (theLayout.displayCount < (MAXDISPLAYS - 1)) {
        
        theLayout.entry[theLayout.displayCount].displayID = displayID;
        theLayout.entry[theLayout.displayCount].bounds = CGRectZero;
        theLayout.entry[theLayout.displayCount].queue = NULL;
        theLayout.entry[theLayout.displayCount].stream = NULL;
        theLayout.displayCount += 1;
        
        addStreamForDisplay(&theLayout, theLayout.displayCount-1);
    } else {
        NSLog(@"Can only add %d displays at most", MAXDISPLAYS);
    }
}

void removeDisplay(CGDirectDisplayID displayID) {
    for (size_t n = 0; n < theLayout.displayCount; n++) {
        if (theLayout.entry[n].displayID == displayID) {
            removeStreamForDisplay(&theLayout, n);
            // shuffle
            break;
        }
    }
}

void displayReconfigured(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *userInfo) {
    ScreenLayout * layout = (ScreenLayout *)userInfo;
    if (flags & kCGDisplayBeginConfigurationFlag) {
        // stop the display stream
    }
    if (flags & kCGDisplayMirrorFlag) {
        
    }
    if (flags & kCGDisplayUnMirrorFlag) {
        
    }
    if (flags & kCGDisplayAddFlag) {
        NSLog(@"display added");
        // a display has been added.
        addDisplay(display);
    }
    else if (flags & kCGDisplayRemoveFlag) {
        NSLog(@"display removed");
        removeDisplay(display);
    } else if (flags & kCGDisplayMovedFlag) {
        NSLog(@"display moved"); // display arrangement changed, resolution changed, mirroring on/off
    }
    
    
}


@implementation ViewController

ScreenLayout * layout;
CGError DisplayRegistrationCallBackSuccessful = kCGErrorSuccess;
#define PERMISSION_WAIT_DURATION 30.0
#define PERMISSION_WAIT_QUANTUM 0.5

NSTimer * updateTimer;


- (void)timerFired:(NSTimer *)timer {
    targetImageSize = self.magnifiedView.bounds.size;
}



- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Do any additional setup after loading the view.
    clearScreenLayout(&theLayout);
    recalculateFullDisplaySurface(&theLayout);
    
    theLayout.theImageView = self.magnifiedView;
    
    DisplayRegistrationCallBackSuccessful =  CGDisplayRegisterReconfigurationCallback(displayReconfigured, &theLayout);
    if (DisplayRegistrationCallBackSuccessful == kCGErrorSuccess) {
        NSLog(@"CGDisplayRegisterReconfiguration SUCCESS");
    } else {
        NSLog(@"CGDisplayRegisterReconfiguration FAILURE");
    }
    
    updateTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(timerFired:) userInfo:nil repeats:YES];

}

- (void)viewDidAppear {
    BOOL someStreamExists = NO;
    int noStreamRetry = 0;
    
    if (!someStreamExists) {
        for (size_t n = 0; n < theLayout.displayCount; n++) {
            addStreamForDisplay(&theLayout, n);
        }
    }
    
    for (size_t n = 0; n < theLayout.displayCount; n++) {
        if (theLayout.entry[n].stream != NULL) {
            someStreamExists = YES;
        }
    }
    
    if (someStreamExists) {
        NSLog(@"Displays ready to stream...");
        noStreamRetry = 0;
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0, NO);
        NSLog(@"...Displays ready to stream");
    } else {
        noStreamRetry += 1;
        NSLog(@"Waiting for permission...");
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, PERMISSION_WAIT_QUANTUM, NO);
        NSLog(@"..Waiting for permission");
    }
}

- (void)viewWillDisappear {
    if (DisplayRegistrationCallBackSuccessful == kCGErrorSuccess) {
        if (CGDisplayRemoveReconfigurationCallback(displayReconfigured, &theLayout) == kCGErrorSuccess) {
            NSLog(@"CGDisplayRemoveReconfiguration SUCCESS");
        } else {
            NSLog(@"CGDisplayRemoveReconfiguration ERROR");
        }
    }
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];
    
    // Update the view, if already loaded.
}


@end
