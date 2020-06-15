//
//  ViewController.h
//  Pixie
//
//  Created by Paulo Raffaelli on 11/24/19.
//  Copyright © 2019 Paulo Raffaelli. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface ViewController : NSViewController

@property (weak) IBOutlet NSTextField *mouseLocationLabel;
@property (weak) IBOutlet NSImageView *magnifiedView;
@property (weak) IBOutlet NSSlider *magnificationMultipler;

@end

