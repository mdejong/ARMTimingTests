/*
 *  test_time_asm.h
 *
 *  Created by Moses DeJong on 7/2/13.
 *  This software has been placed in the public domain.
 *
 * Testing ASM implementations. This module runs a series of tests defined in test_time_asm.m using implementations
 * in C code and in ARM asm defined in test_time_asm.s.
 *
 */

#import <Foundation/Foundation.h>

@interface TestTimeASM : NSObject {
}

+ (NSString*) testRun;

@end