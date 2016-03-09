/*
 *  test_time.h
 *  QTDecodeAnimationByteOrderTestApp
 *
 *  Created by Moses DeJong on 2/8/11.
 *  This software has been placed in the public domain.
 *
 */

// Defines a generic frameword for running timed test cases

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <math.h>
#include <assert.h>
#include <limits.h>
#include <unistd.h>

#include <mach/mach_time.h>

// All of the functions in this module are declared static inline,
// use them as indicated in test_time_example.c

typedef union TestTimeArg {
  void *mPtr;
  int mWord;
} TestTimeArg;

#define TEST_TIME_MAX_ARGS 10

typedef struct TestTimeArgs {
  TestTimeArg argv[TEST_TIME_MAX_ARGS];
} TestTimeArgs;

static TestTimeArgs testTimeArgs;

typedef void (*TT_TimedFunc)();
typedef int (*TT_ValidateFunc)(TT_TimedFunc timedFunc, char *name);

#define NAMEARRSIZE 300

typedef struct TestTimeTestCase {
  char *name;
  char nameArr[NAMEARRSIZE];
  TT_ValidateFunc ptr2ValidateFunc;
  int validateResult;
  TT_TimedFunc ptr2TimedFunc;
  uint32_t result;
  float totalTime;
  uint32_t numTimesToRun;
  uint32_t numTimingLoops;
} TestTimeTestCase;

static TestTimeTestCase *currentTestCase = NULL;

typedef struct TestTimeTestCases {
  TestTimeTestCase cases[256];
  int numTestCases;
} TestTimeTestCases;

static
void test_time_init_cases(TestTimeTestCases *cases) {
  bzero(cases, sizeof(TestTimeTestCases));
}

static
void test_time_free_cases(TestTimeTestCases *cases) {
}

static inline
TestTimeArgs* test_time_args()
{
  return &testTimeArgs;
}

static inline
int test_time_arg_word(int argi) {
  assert(argi >= 0 && argi < TEST_TIME_MAX_ARGS);
  return test_time_args()->argv[argi].mWord;
}

static inline
void* test_time_arg_ptr(int argi) {
  assert(argi >= 0 && argi < TEST_TIME_MAX_ARGS);
  return test_time_args()->argv[argi].mPtr;
}

static inline
void test_time_set_arg_word(int argi, int argw) {
  assert(argi >= 0 && argi < TEST_TIME_MAX_ARGS);
  test_time_args()->argv[argi].mWord = argw;
}

static inline
void test_time_set_arg_ptr(int argi, void * argp) {
  assert(argi >= 0 && argi < TEST_TIME_MAX_ARGS);
  test_time_args()->argv[argi].mPtr = argp;
}

// When a test case is running, this module will
// hold a ref to the test case record/struct.

static inline
void test_time_set_testcase(TestTimeTestCase *testTimeTestCase) {
  currentTestCase = testTimeTestCase;
}

static inline
TestTimeTestCase*
test_time_get_testcase() {
  return currentTestCase;
}

// Util method to make it easier to set the current result
// with just 1 function call.

static inline
void test_time_set_testcase_result(uint32_t result) {
  TestTimeTestCase *currentTestCasePtr = test_time_get_testcase();
  assert(currentTestCasePtr != NULL);
  currentTestCasePtr->result = result;
}

// Util method to make it easier to get the current result
// with just 1 function call.

static inline
uint32_t test_time_get_testcase_result() {
  TestTimeTestCase *currentTestCasePtr = test_time_get_testcase();
  assert(currentTestCasePtr != NULL);
  return currentTestCasePtr->result;
}

// Pass non-NULL ptr2ValidateFunc to invoke a function that
// will check the input and possibly run through a test run
// to verify correctness. Must return 0 to indicate success.
// If a value other than 0 is returned, it will be saved
// as the validateResult.

// The ptr2TimedFunc must be non-NULL, it indicates the
// function that will run the test on the input arguments.
// The execution time of this test invocation is recorded
// and reported in the timeInSeconds field.

// numTimesToRun is the number of iterations in a timing loop.
// numTimingLoops indicates how many times to repeat, if > 1 then the time is
//   the average of running numTimingLoops times, with values outside of
//   2 standard deviations ignored.

static inline
void test_time_create_case(TestTimeTestCases *testCasesPtr,
                           char *name,
                           TT_ValidateFunc ptr2ValidateFunc,
                           TT_TimedFunc ptr2TimedFunc,
                           int numTimesToRun,
                           int numTimingLoops
                           )
{
  assert(testCasesPtr->numTestCases < 256);
  int next = testCasesPtr->numTestCases++;
  TestTimeTestCase *casePtr = &testCasesPtr->cases[next];
  assert(strlen(name) < NAMEARRSIZE);
  strcpy(casePtr->nameArr, name);
  casePtr->name = &casePtr->nameArr[0];
  casePtr->ptr2ValidateFunc = ptr2ValidateFunc;
  assert(ptr2TimedFunc != NULL);
  casePtr->ptr2TimedFunc = ptr2TimedFunc;
  casePtr->numTimesToRun = numTimesToRun;
  casePtr->numTimingLoops = numTimingLoops;
}

static inline
void test_time_run_cases(TestTimeTestCases *testCasesPtr) {
  mach_timebase_info_data_t timebase;
  mach_timebase_info(&timebase);
  
  for (int i = 0; i < testCasesPtr->numTestCases; i++) {
    TestTimeTestCase *casePtr = &testCasesPtr->cases[i];
    
    test_time_set_testcase(casePtr);

    uint32_t numTimesToRun = casePtr->numTimesToRun;
    uint32_t numTimingLoops = casePtr->numTimingLoops;
    
    fprintf(stderr, "run test %s\n", casePtr->name);
    
    casePtr->validateResult = 0;
    
    if (casePtr->ptr2ValidateFunc != NULL) {
      casePtr->validateResult = casePtr->ptr2ValidateFunc(casePtr->ptr2TimedFunc, casePtr->name);
      
      if (casePtr->validateResult != 0) {
        continue;
      }
    }
    
    float timingLoopElapsedTimes[numTimingLoops];
    
    for (int timingLoop = 0; timingLoop < numTimingLoops; timingLoop++) {    
      uint64_t startTime = mach_absolute_time();
      
      for (int loop=0; loop < numTimesToRun; loop++) {
        casePtr->ptr2TimedFunc();
      }
      
      uint64_t endTime = mach_absolute_time();
      
      uint64_t elapsed = endTime - startTime;
      
      float elapsedSec = ((float)elapsed) * ((float)timebase.numer) / ((float)timebase.denom) / 1000000000.0f;
      
      timingLoopElapsedTimes[timingLoop] = elapsedSec;
    }
    
    if (numTimingLoops == 1) {
      casePtr->totalTime = timingLoopElapsedTimes[0];
    } else {
      
      float sum = 0.0;
      for (int timingLoop = 0; timingLoop < numTimingLoops; timingLoop++) {   
        sum += timingLoopElapsedTimes[timingLoop];
      }
      float mean = sum / numTimingLoops;
      
      float sumOfSquares = 0.0;
      for (int timingLoop = 0; timingLoop < numTimingLoops; timingLoop++) {
        float delta = timingLoopElapsedTimes[timingLoop] - mean;
        sumOfSquares += delta * delta;
      }      
      
      float stddev = sqrt( sumOfSquares / numTimingLoops );
      float stddev_mult;
      //stddev_mult = 2.0;
      //stddev_mult = 1.0;
      stddev_mult = 0.5;
      
      // Keep any values inside of N stddevs, this ignores any crazy slow or fast results
      int countInOne = 0;
      float sumInOne = 0.0;
      
      for (int timingLoop = 0; timingLoop < numTimingLoops; timingLoop++) {
        float elapsedSec = timingLoopElapsedTimes[timingLoop];
        
        float low = mean - (stddev * stddev_mult);
        float high = mean + (stddev * stddev_mult);
        
        if (elapsedSec > low && elapsedSec < high) {
          countInOne++;
          sumInOne += elapsedSec;
        }
      }    
      
      // Finally set the average average of these values
      casePtr->totalTime = sumInOne / countInOne;
    }
  }
  
  test_time_set_testcase(NULL);
  
  memset(&testTimeArgs, 0, sizeof(testTimeArgs));
}
