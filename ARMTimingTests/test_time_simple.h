/*
 *  test_time_simple.h
 *  Created by Moses DeJong on 7/2/13.
 *  This software has been placed in the public domain.
 *
 * Highly simplified test module, one function is tested. There is a C impl, an ARM asm impl, and a slightly more
 * optimized ARM asm impl. This simple module makes it easier to understand how to write a piece of module that
 * fits in with the existing timing framework as compared to the more complex test_time_asm.m module which contains
 * many different kinds of tests and implementations.
 *
 */

#import <Foundation/Foundation.h>

@interface TestTimeSimple : NSObject {
}

+ (NSString*) testRun;

@end