//
//  ViewController.h
//  Pixie
//
//  Created by Paulo Raffaelli on 11/24/19.
//  Copyright © 2019 Paulo Raffaelli. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface ViewController : NSViewController<NSMenuItemValidation>

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem;
- (IBAction)increaseMagnification:(id)sender;
- (IBAction)decreaseMagnification:(id)sender;

- (IBAction)magnify1x:(id)sender;
- (IBAction)magnify2x:(id)sender;
- (IBAction)magnify4x:(id)sender;
- (IBAction)magnify8x:(id)sender;
- (IBAction)magnify16x:(id)sender;
- (IBAction)magnify32x:(id)sender;
- (IBAction)magnify64x:(id)sender;

- (IBAction)lockLocation:(id)sender;
- (IBAction)lockHorizontal:(id)sender;
- (IBAction)lockVertical:(id)sender;
- (IBAction)fullScreenToggle:(id)sender;

@property (weak) IBOutlet NSImageView *magnifiedView;

@end

