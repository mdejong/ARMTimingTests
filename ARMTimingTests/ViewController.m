//
//  ViewController.m
//  ARMTimingTests
//
//  Created by Moses DeJong on 7/2/13.
//  This software has been placed in the public domain.

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

@synthesize textView = m_textView;

- (void)viewDidLoad
{
  [super viewDidLoad];
  
  NSAssert(self.textView, @"textView");
  
  // Disable "screen off" timer that would otherwise turn the device
  // off and put the app in the background. The timer loop could take
  // quite some time to run and we do not want to have the system
  // turn off in the middle of a test run.
  
  UIApplication *thisApplication = [UIApplication sharedApplication];
  thisApplication.idleTimerDisabled = YES;
}

- (void)dealloc {
  self.textView = nil;
  [super dealloc];
}

@end
