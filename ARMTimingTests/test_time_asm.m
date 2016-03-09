/*
 *  test_time_asm.m
 *
 *  Created by Moses DeJong on 7/2/13.
 *  This software has been placed in the public domain.
 */

#include "test_time_asm.h"

#include "test_time.h"

// --------

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

// --------

// Defines

#define ONE_PAGE_NUM_BYTES \
  4096

#define SIXTEN_PAGES_NUM_BYTES \
  16*ONE_PAGE_NUM_BYTES

#define HALF_MEG_NUM_BYTES \
  125*ONE_PAGE_NUM_BYTES

#define FOUR_MEG_NUM_BYTES \
  HALF_MEG_NUM_BYTES * 2 * 4

// ---------

// C function, useful for running in the simulator to test memory access
// but not useful for runtime testing since the simulator does not
// help with execution time measurements.

// Most basic impl, fill one word at a time. Not very fast but
// provides a baseline to compare against. Compiler should
// emit basic count down to zero loop, likely with subs and bne.
// This logic would not work properly if numWords was zero,
// but ignore that since we just want a simple baseline that
// the compiler can emit a simple loop for.

static inline
void fill_word_loop(uint32_t* wordPtr, uint32_t word, uint32_t numWords) {
  do {
    *wordPtr++ = word;
  } while (--numWords != 0);
}

// Copy one whole word at a time in C code, this is not sure optimal but gives a baseline
// showing the worst case.

static inline
void copy_pages_with_wordcopy(uint32_t *outWordPtrArg, uint32_t *inWordPtrArg, uint32_t numWordsToFill) {
  while (numWordsToFill--) {
    *outWordPtrArg++ = *inWordPtrArg++;
  }
}

// ASM defined functions

#ifdef USE_GENERATED_ARM_ASM

extern
void
fill_arm_words(uint32_t *outWordPtr, uint32_t inWord, uint32_t numWordsToFill);

extern
void
fill_neon_words1(uint32_t *outWordPtr, uint32_t inWord, uint32_t numWordsToFill);

extern
void
fill_neon_words2(uint32_t *outWordPtr, uint32_t inWord, uint32_t numWordsToFill);

extern
void
fill_neon_words3(uint32_t *outWordPtr, uint32_t inWord, uint32_t numWordsToFill);

extern
void
fill_neon_words4(uint32_t *outWordPtr, uint32_t inWord, uint32_t numWordsToFill);

extern
void
memcopy_arm_words1(uint32_t *outWordPtr, uint32_t *inWordPtr, uint32_t numWords);

extern
void
memcopy_arm_words2(uint32_t *outWordPtr, uint32_t *inWordPtr, uint32_t numWords);

extern
void
memcopy_arm_words3(uint32_t *outWordPtr, uint32_t *inWordPtr, uint32_t numWords);

extern
void
memcopy_arm_words4(uint32_t *outWordPtr, uint32_t *inWordPtr, uint32_t numWords);

extern
void
memcopy_neon_words1(uint32_t *outWordPtr, uint32_t *inWordPtr, uint32_t numWords);

extern
void
memcopy_call_memcpy(uint32_t *outWordPtr, uint32_t *inWordPtr, uint32_t numWords);

#else

// Declare function so that something runs in simulator, not useful to do testing
// but could be useful when debugging util code.

#define DUMMY_FILL_DECL(funcname) \
static \
void funcname(uint32_t *outWordPtr, uint32_t inWord, uint32_t numWords) \
{ \
  fill_word_loop(outWordPtr, inWord, numWords); \
}

DUMMY_FILL_DECL(fill_arm_words)
DUMMY_FILL_DECL(fill_neon_words1)
DUMMY_FILL_DECL(fill_neon_words2)
DUMMY_FILL_DECL(fill_neon_words3)
DUMMY_FILL_DECL(fill_neon_words4)

#define DUMMY_COPY_DECL(funcname) \
static \
void funcname(uint32_t *outWordPtr, uint32_t *inWordPtr, uint32_t numWords) \
{ \
copy_pages_with_wordcopy(outWordPtr, inWordPtr, numWords); \
}

DUMMY_COPY_DECL(memcopy_arm_words1)
DUMMY_COPY_DECL(memcopy_arm_words2)
DUMMY_COPY_DECL(memcopy_arm_words3)
DUMMY_COPY_DECL(memcopy_arm_words4)
DUMMY_COPY_DECL(memcopy_neon_words1)

#endif // USE_GENERATED_ARM_ASM

// Verify the word contents of the framebuffer. The buffer could contain a number of pixels set to a specific value.
// The actual buffer size should be followed by a whole page that is set to a default value, so that it is possible
// to determine when code is writing too much data. It can be very tricky to actually track down when this sort of
// error happens in ASM code, so it is better to just check the output buffer after a test case run so that it is
// possible to find an overwrite after a specific test ends.

static
int validate_pixels_util(uint32_t *pixelPtr, uint32_t numSet, uint32_t setValue, uint32_t numUnsetAfter) {
  uint32_t pixel;
  uint32_t unsetPixel;
  memset(&unsetPixel, 0x77, sizeof(unsetPixel));
  
  int bufferOffset = 0;
  
  for (int i=0; i < numSet; i++) {
    pixel = pixelPtr[bufferOffset++];
    if (pixel != setValue) {
      assert(0);
      return 2;
    }
  }  
  
  for (int i=0; i < numUnsetAfter; i++) {
    pixel = pixelPtr[bufferOffset++];
    if (pixel != unsetPixel) {
      assert(0);
      return 3;
    }
  }
  
  return 0;
}

static
void common_clear_framebuffer(void *frameBuffer, uint32_t numFrameBufferBytes) {
  // memset the buffer plus one more page
  memset(frameBuffer, 0x77, numFrameBufferBytes + ONE_PAGE_NUM_BYTES);
  uint32_t bufferNumWords = numFrameBufferBytes / sizeof(uint32_t);
  uint32_t unsetPixel;
  memset(&unsetPixel, 0x77, sizeof(unsetPixel));
  assert(validate_pixels_util(frameBuffer, bufferNumWords, unsetPixel, ONE_PAGE_NUM_BYTES/sizeof(uint32_t)) == 0);
}

// Generic validate that only needs to be passed the size of the framebuffer

static
int validate_generic_filled_page(TT_TimedFunc timedfunc, char *name, uint32_t numFrameBufferBytes) {
  uint32_t *wordPtr = (uint32_t*) test_time_arg_ptr(0);
  uint32_t wordVal  = (uint32_t) test_time_arg_word(1);
  
  common_clear_framebuffer(wordPtr, numFrameBufferBytes);
  
  // Run the fill function once, then check the results
  
  timedfunc();
  
  uint32_t setPixel = wordVal;
  uint32_t bufferNumWords = numFrameBufferBytes / sizeof(uint32_t);
  return validate_pixels_util(wordPtr, bufferNumWords, setPixel, ONE_PAGE_NUM_BYTES/sizeof(uint32_t));
}

// Validate a buffer that is one page long.

static
int validate_one_filled_page(TT_TimedFunc timedfunc, char *name) {
  return validate_generic_filled_page(timedfunc, name, ONE_PAGE_NUM_BYTES);
}

static
int validate_sixteen_filled_pages(TT_TimedFunc timedfunc, char *name) {
  return validate_generic_filled_page(timedfunc, name, SIXTEN_PAGES_NUM_BYTES);
}

static
int validate_halfmeg_filled_pages(TT_TimedFunc timedfunc, char *name) {
  return validate_generic_filled_page(timedfunc, name, HALF_MEG_NUM_BYTES);
}

static
int validate_fourmeg_filled_pages(TT_TimedFunc timedfunc, char *name) {
  return validate_generic_filled_page(timedfunc, name, FOUR_MEG_NUM_BYTES);
}

#define RUN_FILL_WRAPPER(wrapname, funcname, numbytes) \
static \
void wrapname() \
{ \
uint32_t *wordPtr = (uint32_t*) test_time_arg_ptr(0); \
uint32_t wordVal  = (uint32_t) test_time_arg_word(1); \
funcname(wordPtr, wordVal, numbytes/sizeof(uint32_t)); \
}

RUN_FILL_WRAPPER(run_fill_word_loop_1p, fill_word_loop, ONE_PAGE_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_arm_words_loop_1p, fill_arm_words, ONE_PAGE_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_neon_words1_loop_1p, fill_neon_words1, ONE_PAGE_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_neon_words2_loop_1p, fill_neon_words2, ONE_PAGE_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_neon_words3_loop_1p, fill_neon_words3, ONE_PAGE_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_neon_words4_loop_1p, fill_neon_words4, ONE_PAGE_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_word_loop_16p, fill_word_loop, SIXTEN_PAGES_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_arm_words_loop_16p, fill_arm_words, SIXTEN_PAGES_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_neon_words1_loop_16p, fill_neon_words1, SIXTEN_PAGES_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_neon_words2_loop_16p, fill_neon_words2, SIXTEN_PAGES_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_neon_words3_loop_16p, fill_neon_words3, SIXTEN_PAGES_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_neon_words4_loop_16p, fill_neon_words4, SIXTEN_PAGES_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_word_loop_halfmeg, fill_word_loop, HALF_MEG_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_arm_words_loop_halfmeg, fill_arm_words, HALF_MEG_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_neon_words1_loop_halfmeg, fill_neon_words1, HALF_MEG_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_neon_words2_loop_halfmeg, fill_neon_words2, HALF_MEG_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_neon_words3_loop_halfmeg, fill_neon_words3, HALF_MEG_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_neon_words4_loop_halfmeg, fill_neon_words4, HALF_MEG_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_word_loop_fourmeg, fill_word_loop, FOUR_MEG_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_arm_words_loop_fourmeg, fill_arm_words, FOUR_MEG_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_neon_words1_loop_fourmeg, fill_neon_words1, FOUR_MEG_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_neon_words2_loop_fourmeg, fill_neon_words2, FOUR_MEG_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_neon_words3_loop_fourmeg, fill_neon_words3, FOUR_MEG_NUM_BYTES);

RUN_FILL_WRAPPER(run_fill_neon_words4_loop_fourmeg, fill_neon_words4, FOUR_MEG_NUM_BYTES);


// memcopy impls. Note that the memcopy tests run in a harness that passes
// output ptr, input ptr, and number of words as arguments.

static
int validate_generic_copied_pages(TT_TimedFunc timedfunc, char *name, uint32_t numFrameBufferBytes) {
  uint32_t *outWordPtr = (uint32_t*) test_time_arg_ptr(0);
  uint32_t wordVal;
  memset(&wordVal, 0x01, sizeof(wordVal));
  
  common_clear_framebuffer(outWordPtr, numFrameBufferBytes);
  
  // Run the fill function once, then check the results
  
  timedfunc();
  
  uint32_t setPixel = wordVal;
  uint32_t bufferNumWords = numFrameBufferBytes / sizeof(uint32_t);
  return validate_pixels_util(outWordPtr, bufferNumWords, setPixel, ONE_PAGE_NUM_BYTES/sizeof(uint32_t));
}

static
int validate_one_copied_pages(TT_TimedFunc timedfunc, char *name) {
  return validate_generic_copied_pages(timedfunc, name, ONE_PAGE_NUM_BYTES);
}

static
int validate_sixteen_copied_pages(TT_TimedFunc timedfunc, char *name) {
  return validate_generic_copied_pages(timedfunc, name, SIXTEN_PAGES_NUM_BYTES);
}

static
int validate_halfmeg_copied_pages(TT_TimedFunc timedfunc, char *name) {
  return validate_generic_copied_pages(timedfunc, name, HALF_MEG_NUM_BYTES);
}

static
int validate_fourmeg_copied_pages(TT_TimedFunc timedfunc, char *name) {
  return validate_generic_copied_pages(timedfunc, name, FOUR_MEG_NUM_BYTES);
}

// Make sure this memcpy is not inlined so that it is not possible for the memcpy
// to be turned into an inlined impl of memcpy.

static
__attribute__ ((noinline))
void copy_pages_with_memcpy(uint32_t *outWordPtrArg, uint32_t *inWordPtrArg, uint32_t numWordsToFill) {
  memcpy(outWordPtrArg, inWordPtrArg, numWordsToFill << 2);
}

#define RUN_PAGECOPY_WRAPPER(wrapname, funcname, numBytes) \
static \
void wrapname() \
{ \
uint32_t *outWordPtr = (uint32_t*) test_time_arg_ptr(0); \
uint32_t *inWordPtr = (uint32_t*) test_time_arg_ptr(1); \
uint32_t numWords = ((uint32_t) numBytes) >> 2; \
funcname(outWordPtr, inWordPtr, numWords); \
}

RUN_PAGECOPY_WRAPPER(run_copy_page_with_wordcopy_1p, copy_pages_with_wordcopy, ONE_PAGE_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_memcpy_1p, copy_pages_with_memcpy, ONE_PAGE_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_armwords1_1p, memcopy_arm_words1, ONE_PAGE_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_armwords2_1p, memcopy_arm_words2, ONE_PAGE_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_armwords3_1p, memcopy_arm_words3, ONE_PAGE_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_armwords4_1p, memcopy_arm_words4, ONE_PAGE_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_neonwords1_1p, memcopy_neon_words1, ONE_PAGE_NUM_BYTES);

RUN_PAGECOPY_WRAPPER(run_copy_page_with_wordcopy_16p, copy_pages_with_wordcopy, SIXTEN_PAGES_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_memcpy_16p, copy_pages_with_memcpy, SIXTEN_PAGES_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_armwords1_16p, memcopy_arm_words1, SIXTEN_PAGES_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_armwords2_16p, memcopy_arm_words2, SIXTEN_PAGES_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_armwords3_16p, memcopy_arm_words3, SIXTEN_PAGES_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_armwords4_16p, memcopy_arm_words4, SIXTEN_PAGES_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_neonwords1_16p, memcopy_neon_words1, SIXTEN_PAGES_NUM_BYTES);

RUN_PAGECOPY_WRAPPER(run_copy_page_with_wordcopy_halfmeg, copy_pages_with_wordcopy, HALF_MEG_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_memcpy_halfmeg, copy_pages_with_memcpy, HALF_MEG_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_armwords1_halfmeg, memcopy_arm_words1, HALF_MEG_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_armwords2_halfmeg, memcopy_arm_words2, HALF_MEG_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_armwords3_halfmeg, memcopy_arm_words3, HALF_MEG_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_armwords4_halfmeg, memcopy_arm_words4, HALF_MEG_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_neonwords1_halfmeg, memcopy_neon_words1, HALF_MEG_NUM_BYTES);

RUN_PAGECOPY_WRAPPER(run_copy_page_with_wordcopy_fourmeg, copy_pages_with_wordcopy, FOUR_MEG_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_memcpy_fourmeg, copy_pages_with_memcpy, FOUR_MEG_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_armwords1_fourmeg, memcopy_arm_words1, FOUR_MEG_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_armwords2_fourmeg, memcopy_arm_words2, FOUR_MEG_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_armwords3_fourmeg, memcopy_arm_words3, FOUR_MEG_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_armwords4_fourmeg, memcopy_arm_words4, FOUR_MEG_NUM_BYTES);
RUN_PAGECOPY_WRAPPER(run_copy_page_with_neonwords1_fourmeg, memcopy_neon_words1, FOUR_MEG_NUM_BYTES);

// ----------------------- TestTimeASM
//
// tests asm impl times

@implementation TestTimeASM

+ (NSString*) testRun
{
  NSMutableString *mStr = [NSMutableString string];
  
  NSString *str;
  
  str = [self testFillBuffers];
  
  [mStr appendString:str];

  str = [self testCopyBuffers];
  
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

+ (NSString*) testFillBuffers
{
  // The number of loop is how many times a test is run in one timing
  const int SMALL_LOOPS = 2000;
  // The number of time that the loops are run, the average of these times is returned
  const int SMALL_NUM = 100;

  // The number of loop is how many times a test is run in one timing
  const int LARGE_LOOPS = 100;
  // The number of time that the loops are run, the average of these times is returned
  const int LARGE_NUM = 100;
  
  TestTimeTestCases testsStruct;
  TestTimeTestCases *tests = &testsStruct;
  test_time_init_cases(tests);
  
  // Fill 1 page
  
  test_time_create_case(tests, "fill_word_loop_1p", validate_one_filled_page, run_fill_word_loop_1p, SMALL_LOOPS, SMALL_NUM);

  test_time_create_case(tests, "fill_arm_words_loop_1p", validate_one_filled_page, run_fill_arm_words_loop_1p, SMALL_LOOPS, SMALL_NUM);

  // Enable only 1 neon fill impl, testing all 4 not needed since they are basically the same
  
  test_time_create_case(tests, "fill_neon_words_loop_1p", validate_one_filled_page, run_fill_neon_words1_loop_1p, SMALL_LOOPS, SMALL_NUM);
  
  /*
  
  test_time_create_case(tests, "fill_neon_words1_loop_1p", validate_one_filled_page, run_fill_neon_words1_loop_1p, SMALL_LOOPS, SMALL_NUM);
  
  test_time_create_case(tests, "fill_neon_words2_loop_1p", validate_one_filled_page, run_fill_neon_words2_loop_1p, SMALL_LOOPS, SMALL_NUM);
  
  test_time_create_case(tests, "fill_neon_words3_loop_1p", validate_one_filled_page, run_fill_neon_words3_loop_1p, SMALL_LOOPS, SMALL_NUM);
  
  test_time_create_case(tests, "fill_neon_words4_loop_1p", validate_one_filled_page, run_fill_neon_words4_loop_1p, SMALL_LOOPS, SMALL_NUM);
  
  */
   
  // Fill 16 pages
  
  test_time_create_case(tests, "fill_word_loop_16p", validate_sixteen_filled_pages, run_fill_word_loop_16p, SMALL_LOOPS, SMALL_NUM);

  test_time_create_case(tests, "fill_arm_words_loop_16p", validate_sixteen_filled_pages, run_fill_arm_words_loop_16p, SMALL_LOOPS, SMALL_NUM);

  test_time_create_case(tests, "fill_neon_words_loop_16p", validate_sixteen_filled_pages, run_fill_neon_words1_loop_16p, SMALL_LOOPS, SMALL_NUM);
  
  /*
  
  test_time_create_case(tests, "fill_neon_words1_loop_16p", validate_sixteen_filled_pages, run_fill_neon_words1_loop_16p, SMALL_LOOPS, SMALL_NUM);
  
  test_time_create_case(tests, "fill_neon_words2_loop_16p", validate_sixteen_filled_pages, run_fill_neon_words2_loop_16p, SMALL_LOOPS, SMALL_NUM);
  
  test_time_create_case(tests, "fill_neon_words3_loop_16p", validate_sixteen_filled_pages, run_fill_neon_words3_loop_16p, SMALL_LOOPS, SMALL_NUM);
  
  test_time_create_case(tests, "fill_neon_words4_loop_16p", validate_sixteen_filled_pages, run_fill_neon_words4_loop_16p, SMALL_LOOPS, SMALL_NUM);
  
  */

  // Fill half meg of pages
  
  test_time_create_case(tests, "fill_word_loop_halfmeg", validate_halfmeg_filled_pages, run_fill_word_loop_halfmeg, LARGE_LOOPS, LARGE_NUM);
  
  test_time_create_case(tests, "fill_arm_words_loop_halfmeg", validate_halfmeg_filled_pages, run_fill_arm_words_loop_halfmeg, LARGE_LOOPS, LARGE_NUM);
  
  test_time_create_case(tests, "fill_neon_words_loop_halfmeg", validate_halfmeg_filled_pages, run_fill_neon_words1_loop_halfmeg, LARGE_LOOPS, LARGE_NUM);
  
  /*
   
   test_time_create_case(tests, "fill_neon_words1_loop_halfmeg", validate_halfmeg_filled_pages, run_fill_neon_words1_loop_halfmeg, LARGE_LOOPS, LARGE_NUM);
   
   test_time_create_case(tests, "fill_neon_words2_loop_halfmeg", validate_halfmeg_filled_pages, run_fill_neon_words2_loop_halfmeg, LARGE_LOOPS, LARGE_NUM);
   
   test_time_create_case(tests, "fill_neon_words3_loop_halfmeg", validate_halfmeg_filled_pages, run_fill_neon_words3_loop_halfmeg, LARGE_LOOPS, LARGE_NUM);
   
   test_time_create_case(tests, "fill_neon_words4_loop_halfmeg", validate_halfmeg_filled_pages, run_fill_neon_words4_loop_halfmeg, LARGE_LOOPS, LARGE_NUM);
   
   */
  
  // Fill 4 megs
  
  test_time_create_case(tests, "fill_word_loop_fourmeg", validate_fourmeg_filled_pages, run_fill_word_loop_fourmeg, LARGE_LOOPS, LARGE_NUM);
  
  test_time_create_case(tests, "fill_arm_words_loop_fourmeg", validate_fourmeg_filled_pages, run_fill_arm_words_loop_fourmeg, LARGE_LOOPS, LARGE_NUM);
  
  test_time_create_case(tests, "fill_neon_words_loop_fourmeg", validate_fourmeg_filled_pages, run_fill_neon_words1_loop_fourmeg, LARGE_LOOPS, LARGE_NUM);
  
  /*
   
   test_time_create_case(tests, "fill_neon_words1_loop_fourmeg", validate_fourmeg_filled_pages, run_fill_neon_words1_loop_fourmeg, LARGE_LOOPS, LARGE_NUM);
   
   test_time_create_case(tests, "fill_neon_words2_loop_fourmeg", validate_fourmeg_filled_pages, run_fill_neon_words2_loop_fourmeg, LARGE_LOOPS, LARGE_NUM);
   
   test_time_create_case(tests, "fill_neon_words3_loop_fourmeg", validate_fourmeg_filled_pages, run_fill_neon_words3_loop_fourmeg, LARGE_LOOPS, LARGE_NUM);
   
   test_time_create_case(tests, "fill_neon_words4_loop_fourmeg", validate_fourmeg_filled_pages, run_fill_neon_words4_loop_fourmeg, LARGE_LOOPS, LARGE_NUM);
   
   */
  
  // Allocate a framebuffer that is large enough to hold the largest chunk of data
  // that will be used with this test plus one more page to catch overwrites.
  
  int numBytesActuallyAllocated = FOUR_MEG_NUM_BYTES + ONE_PAGE_NUM_BYTES;
  uint32_t *frameBuffer = valloc(numBytesActuallyAllocated);
  assert(frameBuffer);
  
  common_clear_framebuffer(frameBuffer, FOUR_MEG_NUM_BYTES);
  
  // The arguments to pass to test wrapper functions. These 2 arguments do
  // not change from one test to another. The size of data written to
  // the framebuffer will actually change from one test to the next, so
  // it is not defined in terms of these arguments.
  
  test_time_set_arg_ptr(0, frameBuffer);
  test_time_set_arg_word(1, 0x1);

  NSString *str = [self printTestResultsUtil:tests ident:@"fill buffers"];
  
  free(frameBuffer);
  
  test_time_free_cases(tests);
  
  return str;
}

+ (NSString*) testCopyBuffers
{
  // The number of loop is how many times a test is run in one timing
  const int SMALL_LOOPS = 2000;
  // The number of time that the loops are run, the average of these times is returned
  const int SMALL_NUM = 200;
  
  // The number of loop is how many times a test is run in one timing
  const int LARGE_LOOPS = 30;
  // The number of time that the loops are run, the average of these times is returned
  const int LARGE_NUM = 100;
    
  TestTimeTestCases testsStruct;
  TestTimeTestCases *tests = &testsStruct;
  test_time_init_cases(tests);
  
  // COPY 1 page
  
  test_time_create_case(tests, "copy_page_with_wordcopy_1p", validate_one_copied_pages, run_copy_page_with_wordcopy_1p, SMALL_LOOPS, SMALL_NUM);
  
  test_time_create_case(tests, "copy_page_with_memcpy_1p", validate_one_copied_pages, run_copy_page_with_memcpy_1p, SMALL_LOOPS, SMALL_NUM);

  test_time_create_case(tests, "copy_page_with_armwords1_1p", validate_one_copied_pages, run_copy_page_with_armwords1_1p, SMALL_LOOPS, SMALL_NUM);
  
  test_time_create_case(tests, "copy_page_with_armwords2_1p", validate_one_copied_pages, run_copy_page_with_armwords2_1p, SMALL_LOOPS, SMALL_NUM);
  
  test_time_create_case(tests, "copy_page_with_armwords3_1p", validate_one_copied_pages, run_copy_page_with_armwords3_1p, SMALL_LOOPS, SMALL_NUM);
  
  test_time_create_case(tests, "copy_page_with_armwords4_1p", validate_one_copied_pages, run_copy_page_with_armwords4_1p, SMALL_LOOPS, SMALL_NUM);
  
  test_time_create_case(tests, "copy_page_with_neonwords1_1p", validate_one_copied_pages, run_copy_page_with_neonwords1_1p, SMALL_LOOPS, SMALL_NUM);
  
  // COPY 16 pages

  test_time_create_case(tests, "copy_page_with_wordcopy_16p", validate_sixteen_copied_pages, run_copy_page_with_wordcopy_16p, SMALL_LOOPS, SMALL_NUM);
  
  test_time_create_case(tests, "copy_page_with_memcpy_16p", validate_sixteen_copied_pages, run_copy_page_with_memcpy_16p, SMALL_LOOPS, SMALL_NUM);

  test_time_create_case(tests, "copy_page_with_armwords1_16p", validate_sixteen_copied_pages, run_copy_page_with_armwords1_16p, SMALL_LOOPS, SMALL_NUM);
  
  test_time_create_case(tests, "copy_page_with_armwords2_16p", validate_sixteen_copied_pages, run_copy_page_with_armwords2_16p, SMALL_LOOPS, SMALL_NUM);
  
  test_time_create_case(tests, "copy_page_with_armwords3_16p", validate_sixteen_copied_pages, run_copy_page_with_armwords3_16p, SMALL_LOOPS, SMALL_NUM);
  
  test_time_create_case(tests, "copy_page_with_armwords4_16p", validate_sixteen_copied_pages, run_copy_page_with_armwords4_16p, SMALL_LOOPS, SMALL_NUM);
  
  test_time_create_case(tests, "copy_page_with_neonwords1_16p", validate_sixteen_copied_pages, run_copy_page_with_neonwords1_16p, SMALL_LOOPS, SMALL_NUM);

  // Copy half meg of pages
  
  test_time_create_case(tests, "copy_page_with_wordcopy_halfmeg", validate_halfmeg_copied_pages, run_copy_page_with_wordcopy_halfmeg, LARGE_LOOPS, LARGE_NUM);
  
  test_time_create_case(tests, "copy_page_with_memcpy_halfmeg", validate_halfmeg_copied_pages, run_copy_page_with_memcpy_halfmeg, LARGE_LOOPS, LARGE_NUM);
  
  test_time_create_case(tests, "copy_page_with_armwords1_halfmeg", validate_halfmeg_copied_pages, run_copy_page_with_armwords1_halfmeg, LARGE_LOOPS, LARGE_NUM);
  
  test_time_create_case(tests, "copy_page_with_armwords2_halfmeg", validate_halfmeg_copied_pages, run_copy_page_with_armwords2_halfmeg, LARGE_LOOPS, LARGE_NUM);
  
  test_time_create_case(tests, "copy_page_with_armwords3_halfmeg", validate_halfmeg_copied_pages, run_copy_page_with_armwords3_halfmeg, LARGE_LOOPS, LARGE_NUM);

  test_time_create_case(tests, "copy_page_with_armwords4_halfmeg", validate_halfmeg_copied_pages, run_copy_page_with_armwords4_halfmeg, LARGE_LOOPS, LARGE_NUM);
  
  test_time_create_case(tests, "copy_page_with_neonwords1_halfmeg", validate_halfmeg_copied_pages, run_copy_page_with_neonwords1_halfmeg, LARGE_LOOPS, LARGE_NUM);
  
  // Copy 4 megabytes of pages
  
  test_time_create_case(tests, "copy_page_with_wordcopy_fourmeg", validate_fourmeg_copied_pages, run_copy_page_with_wordcopy_fourmeg, LARGE_LOOPS, LARGE_NUM);
  
  test_time_create_case(tests, "copy_page_with_memcpy_fourmeg", validate_fourmeg_copied_pages, run_copy_page_with_memcpy_fourmeg, LARGE_LOOPS, LARGE_NUM);
  
  test_time_create_case(tests, "copy_page_with_armwords1_fourmeg", validate_fourmeg_copied_pages, run_copy_page_with_armwords1_fourmeg, LARGE_LOOPS, LARGE_NUM);
  
  test_time_create_case(tests, "copy_page_with_armwords2_fourmeg", validate_fourmeg_copied_pages, run_copy_page_with_armwords2_fourmeg, LARGE_LOOPS, LARGE_NUM);
  
  test_time_create_case(tests, "copy_page_with_armwords3_fourmeg", validate_fourmeg_copied_pages, run_copy_page_with_armwords3_fourmeg, LARGE_LOOPS, LARGE_NUM);
  
  test_time_create_case(tests, "copy_page_with_armwords4_fourmeg", validate_fourmeg_copied_pages, run_copy_page_with_armwords4_fourmeg, LARGE_LOOPS, LARGE_NUM);
  
  test_time_create_case(tests, "copy_page_with_neonwords1_fourmeg", validate_fourmeg_copied_pages, run_copy_page_with_neonwords1_fourmeg, LARGE_LOOPS, LARGE_NUM);
  
  // Allocate a framebuffer that is large enough to hold the largest chunk of data
  // that will be used with this test plus one more page to catch overwrites.
  
  int numBytesActuallyAllocated = FOUR_MEG_NUM_BYTES + ONE_PAGE_NUM_BYTES;
  uint32_t *outFramebuffer = valloc(numBytesActuallyAllocated);
  assert(outFramebuffer);
  
  common_clear_framebuffer(outFramebuffer, FOUR_MEG_NUM_BYTES);
  
  uint32_t *inFramebuffer = valloc(numBytesActuallyAllocated);
  assert(inFramebuffer);
  
  common_clear_framebuffer(inFramebuffer, FOUR_MEG_NUM_BYTES);
  // Explicitly set input value, this only needs to be done once
  memset(inFramebuffer, 0x01, FOUR_MEG_NUM_BYTES);
  
  // The arguments to pass to test wrapper functions. These 2 arguments do
  // not change from one test to another. The size of data written to
  // the framebuffer will actually change from one test to the next, so
  // it is not defined in terms of these arguments.
  
  test_time_set_arg_ptr(0, outFramebuffer);
  test_time_set_arg_ptr(1, inFramebuffer);
  
  // Run the tests

  NSString *str = [self printTestResultsUtil:tests ident:@"copy buffers"];
  
  free(outFramebuffer);
  free(inFramebuffer);
  
  test_time_free_cases(tests);
  
  return str;
}

@end
