/*
 *  test_time_simple.m
 *  Created by Moses DeJong on 7/2/13.
 *  This software has been placed in the public domain.
 *
 */

#include "test_time_simple.h"

#include "test_time.h"

// This file implements the following C functions for the ARM platform.
// Both ARM6 and ARM7 devices are supported by this implementation.

// This ARM asm file will generate an error with clang 4 (xcode 4.5 and newer) because
// the integrated assembler does not accept AT&T syntax. This .s target will need to
// have the "-no-integrated-as" command line option passed via
// "Target" -> "Build Phases" -> "maxvid_decode_arm.s"

#if defined(__arm__)
# define COMPILE_ARM 1
# if defined(__thumb__)
#  define COMPILE_ARM_THUMB_ASM 1
# else
#  define COMPILE_ARM_ASM 1
# endif
#endif

// Xcode 4.2 supports clang only, but the ARM asm integration depends on specifics
// of register allocation and as a result only works when compiled with gcc.

#if defined(__clang__)
#  define COMPILE_CLANG 1
#endif // defined(__clang__)

// For CLANG build on ARM, skip this entire module and use custom ARM asm imp instead.

#if defined(COMPILE_CLANG) && defined(COMPILE_ARM)
# define USE_GENERATED_ARM_ASM 1
#endif // SKIP __clang__ && ARM

// GCC 4.2 and newer seems to allocate registers in a way that breaks the inline
// arm asm in maxvid_decode.c, so use the ARM asm in this case.

#if defined(__GNUC__) && !defined(__clang__) && defined(COMPILE_ARM)
# define __GNUC_PREREQ(maj, min) \
((__GNUC__ << 16) + __GNUC_MINOR__ >= ((maj) << 16) + (min))
# if __GNUC_PREREQ(4,2)
#  define USE_GENERATED_ARM_ASM 1
# endif
#endif


// Defines

const int MaxNumValues = 100;
const int MaxNumSum = 5050; // 0 + 1 + 2 ... + 100

// This C impl will sum 100 integers in a loop and return the result. This is not going to be the most
// efficient possible impl, but it provides a simple baseline timing value that others can be judged
// against. Note that this impl assumes that at least 1 loop will alway be executed.

static inline
uint32_t simple_add_result1(uint32_t* wordPtr, uint32_t numWords) {
  uint32_t sum = 0;
  
  do {
    uint32_t tmp = *wordPtr++;
    sum += tmp;
  } while (--numWords != 0);
  
  return sum;
}

#ifdef USE_GENERATED_ARM_ASM

// ASM defined functions, implemented in test_time_simple.s

extern
uint32_t simple_add_result2(uint32_t* wordPtr, uint32_t numWords);

extern
uint32_t simple_add_result3(uint32_t* wordPtr, uint32_t numWords);

#else

// When run in the simulator, ARM asm impls are not tested. But, the simulator does
// provide a nice environment to debug memory issues so just use the existing
// C impl of result1 again.

static
uint32_t simple_add_result2(uint32_t* wordPtr, uint32_t numWords)
{
  return simple_add_result1(wordPtr, numWords);
}

static
uint32_t simple_add_result3(uint32_t* wordPtr, uint32_t numWords)
{
  return simple_add_result1(wordPtr, numWords);
}

#endif // USE_GENERATED_ARM_ASM



// Actually running a test function inside the test framework depends on two utility functions.

// This validate function will invoke the test function once and then check that the
// correct results were returned. This type of validate logic is critical because
// when implementing optimizations in ASM code, it can be very easy to actually break
// things without noticing. So, the test framework needs to actually check that
// a specific implementaiton is really working before a set of timing runs.

// The validate function should return 0 if everything is working as expected, otherwise
// return a non-zero value and that value will be saved in the test results.

static
int validate_simple_add_result(TT_TimedFunc timedfunc, char *name) {
  // The arguments to be passed to the function, either a pointer or a word
  uint32_t *wordPtr = (uint32_t*) test_time_arg_ptr(0);
  uint32_t numWords  = (uint32_t) test_time_arg_word(1);
  
  assert(wordPtr != NULL);
  assert(numWords > 0);
  
  // Run the fill function once, then check the results
  
  timedfunc();
  
  // Get function result (a uint32_t)
  
  uint32_t result = test_time_get_testcase_result();

  if (result == MaxNumSum) {
    return 0;
  } else {
    return 1;
  }
}

// A run wrapper is needed to query the test defined function arguments and then actually call
// the function with the proper arguments and record the results. There is no really good way
// to automate these types of wrapper functions for C code so they just need to be created by
// hand or with a macro.

static
void run_simple_add_result1()
{
  uint32_t *wordPtr = (uint32_t*) test_time_arg_ptr(0);
  uint32_t numWords  = (uint32_t) test_time_arg_word(1);
  
  uint32_t result = simple_add_result1(wordPtr, numWords);

  test_time_set_testcase_result(result);
}

static
void run_simple_add_result2()
{
  uint32_t *wordPtr = (uint32_t*) test_time_arg_ptr(0);
  uint32_t numWords  = (uint32_t) test_time_arg_word(1);
  
  uint32_t result = simple_add_result2(wordPtr, numWords);
  
  test_time_set_testcase_result(result);
}

static
void run_simple_add_result3()
{
  uint32_t *wordPtr = (uint32_t*) test_time_arg_ptr(0);
  uint32_t numWords  = (uint32_t) test_time_arg_word(1);
  
  uint32_t result = simple_add_result3(wordPtr, numWords);
  
  test_time_set_testcase_result(result);
}


// ----------------------- TestTimeSimple
//
// tests asm impl times

@implementation TestTimeSimple

+ (NSString*) testRun
{
  NSMutableString *mStr = [NSMutableString string];
  
  NSString *str;
  
  str = [self testSimpleAdd];
  
  [mStr appendString:str];
  
  return [NSString stringWithString:mStr];
}

// Util that will run the tests and convert the results to a NSString
+ (NSString*) printTestResultsUtil:(TestTimeTestCases*)tests
                             ident:(NSString*)ident
{
  NSMutableString *results = [NSMutableString string];
  
  NSLog(@"start %@", ident);
  
  @autoreleasepool {
    test_time_run_cases(tests);
  }

  for (int i=0; i < tests->numTestCases; i++) {
    char *name = tests->cases[i].name;
    float seconds = tests->cases[i].totalTime;
    int result = tests->cases[i].validateResult;
    
    NSString *resultLine;
    
    if (result != 0) {
      resultLine = [NSString stringWithFormat:@"%s: did not pass validation, result %d", name, result];
      NSLog(@"%@", resultLine);
    } else {
      resultLine = [NSString stringWithFormat:@"%-40s %0.4f seconds", name, seconds];
      NSLog(@"%@", resultLine);
    }
    
    [results appendString:resultLine];
    [results appendString:@"\n"];
  }
  
  NSLog(@"finished %@", ident);
  
  return [NSString stringWithString:results];
}

// This "simple add" will add up 100 integers

+ (NSString*) testSimpleAdd
{
  // The number of loop is how many times a test is executed in one timing run
  const int LOOPS = 5000;
  // The number of time that the loops are run, the average of these times is returned
  const int NUM = 100;
  
  TestTimeTestCases testsStruct;
  TestTimeTestCases *tests = &testsStruct;
  test_time_init_cases(tests);
  
  // Allocate a buffer and fill it with integers starting at 1 and ending with 100
  
  int numBytesActuallyAllocated = MaxNumValues * sizeof(uint32_t);
  uint32_t *values = valloc(numBytesActuallyAllocated);
  assert(values);

  memset(values, 0, numBytesActuallyAllocated);
  
  int num = 1;
  for (int i=0; i < 100; i++) {
    values[i] = num++;
  }
  
  // Define 2 arguments that will be passed to wrapper functions. The first
  // is a pointer to integer values. The second argument is the actual
  // number of integers to be read from the array. The functions should not
  // know how many number will be summed up to keep the compiler from
  // phony optimizations.
  
  test_time_set_arg_ptr(0, values);
  test_time_set_arg_word(1, MaxNumValues);

  // Configure name of test, the validation function, and how many times a test is run to generate a timing value
  
  test_time_create_case(tests, "simple_add_result1", validate_simple_add_result, run_simple_add_result1, LOOPS, NUM);
  
  test_time_create_case(tests, "simple_add_result2", validate_simple_add_result, run_simple_add_result2, LOOPS, NUM);
  
  test_time_create_case(tests, "simple_add_result3", validate_simple_add_result, run_simple_add_result3, LOOPS, NUM);

  // Run the tests and record timing results
  
  NSString *str = [self printTestResultsUtil:tests ident:@"simple test"];
  
  free(values);
  
  test_time_free_cases(tests);
  
  return str;
}

@end
