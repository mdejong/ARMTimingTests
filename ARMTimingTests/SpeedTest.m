//
//  SpeedTest.m
//  QTDecodeAnimationSpeedTestApp
//
//  Created by Moses DeJong on 12/19/10.
//  This software has been placed in the public domain.
//
// This class runs test cases and measures the execution time
// of each for a set number of loops. The actual execution
// is done in a background thread to avoid blocking out
// the main loop.

#import "SpeedTest.h"

#import "test_time_simple.h"
#import "test_time_asm.h"

static
UITextView *reportResultsTextView = nil;

@implementation SpeedTest

+ (void) appendResult:(UITextView*)resultTextView
               result:(NSString*)result
{
  NSString *contents = resultTextView.text;
  NSMutableString *results = [NSMutableString string];
  [results appendString:contents];
  [results appendString:result];
  [results appendString:@"\n"];
  resultTextView.text = [NSString stringWithString:results];
  
  NSLog(@"%@", result);
}

// ----------------------------------------

+ (void) runTests:(UITextView*)resultTextView
{
  NSLog(@"SpeedTest.runTests");
 
  resultTextView.text = @"";
  
  // Ugly hack to hold on to pointer to text view!
  reportResultsTextView = resultTextView;
  
  // Start tests
  
  NSString *resultString = @"SpeedTest.runTests";

  [self appendResult:resultTextView result:resultString];
  
  // Update the display
  
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

  // Run in thread
  
  [NSThread detachNewThreadSelector:@selector(runTestsInSecondaryThreadEntryPoint) toTarget:self.class withObject:nil];
  
  return;
}

// Invoked in secondary thread

+ (void) runTestsInSecondaryThreadEntryPoint
{
  @autoreleasepool {
    
    NSString *results;

    if (1) {
      // Simple module shows the most simple test run possible, a single
      // function with a C impl and 2 ASM impls. The ASM module test a huge
      // number of very subtle ARM asm differences. This simple module can
      // be run instead to get a handle on how the timing logic works without
      // having to understand all the details of running multiple tests at the
      // same time.
      
      results = [TestTimeSimple testRun];
    } else {
      // New ASM logic in module test_time_asm.m. This test modules is a lot more
      // complex than TestTimeSimple, but it covers both fill and memcpy times
      // and shows interesting arch diffs on Cortext A8 vs A9.
      
      results = [TestTimeASM testRun];
    }

    [self performSelectorOnMainThread:@selector(runTestsDone:) withObject:results waitUntilDone:TRUE];
    
  }
}

// Invoked in main thread when done

+ (void) runTestsDone:(NSString*)results
{
  [self appendResult:reportResultsTextView result:results];
  
  [self appendResult:reportResultsTextView result:@"DONE"];
  
  // kick off another test run in 30 seconds
  
  NSTimer *runAgainTimer = [NSTimer timerWithTimeInterval: 30.0
                                                 target: self
                                               selector: @selector(runAgainTimerCallback:)
                                               userInfo: NULL
                                                repeats: FALSE];
  
  [[NSRunLoop currentRunLoop] addTimer: runAgainTimer forMode: NSDefaultRunLoopMode];
}

+ (void)runAgainTimerCallback:(NSTimer *)timer {
  [self runTests:reportResultsTextView];
}

@end
