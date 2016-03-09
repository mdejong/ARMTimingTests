//
// test_time_asm.s
//
// Created by Moses DeJong on 7/2/13.
// This software has been placed in the public domain.
//
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

#if defined(USE_GENERATED_ARM_ASM)
	.section __TEXT,__text,regular
	.section __TEXT,__textcoal_nt,coalesced
	.section __TEXT,__const_coal,coalesced
	.section __TEXT,__picsymbolstub4,symbol_stubs,none,16
  .syntax divided

#if !defined(COMPILE_CLANG)
  .arch armv7-a
  .fpu neon
#endif

	.text

// macros for function entry/exit

// http://www.shervinemami.info/armAssembly.html

.macro BEGIN_FUNCTION
.align 2		// Align the function code to a 4-byte (2^n) word boundary.
.arm			// Use ARM instructions instead of Thumb.
.globl _$0		// Make the function globally accessible.
.no_dead_strip _$0	// Stop the optimizer from ignoring this function!
.private_extern _$0
_$0:				// Declare the function.
.endmacro

.macro BEGIN_FUNCTION_THUMB
.align 2		// Align the function code to a 4-byte (2^n) word boundary.
.thumb			// Use THUMB-2 instrctions instead of ARM.
.globl _$0		// Make the function globally accessible.
.thumb_func _$0		// Use THUMB-2 for the following function.
.no_dead_strip _$0	// Stop the optimizer from ignoring this function!
.private_extern _$0
_$0:				// Declare the function.
.endmacro

.macro END_FUNCTION
bx	lr		// Jump back to the caller.
.endmacro

// Store a 32-bit constant into a register.
// eg: SET_REG r1, 0x11223344
.macro 	SET_REG
// Recommended for ARMv6+ because the number is stored inside the instruction:
movw	$0, #:lower16:$1
movt	$0, #:upper16:$1
.endmacro

// fill_arm_words(uint32_t *outWordPtr, uint32_t inWord, uint32_t numWordsToFill)
//
// Optimized ARM stm loop, this logic writes the same word value to memory N times.

BEGIN_FUNCTION fill_arm_words
  push {r4, r5, r6, r7, lr}
  push {r8, r10, r11}
  // r0 = wordPtr
  // r1 = inWord
  // r2 = numWordsToFill

  // r12 will hold numWordsToFill while the loops runs
  mov r12, r2

  // Hold r2 as r12 while loop runs

  // Move r0 into r10, r10 will be the output ptr
  mov r10, r0

  // Load inWord into registers

  mov r0, r1
  mov r2, r0
  mov r3, r0
  mov r4, r0
  mov r5, r0
  mov r6, r0
  mov r8, r0

  cmp r12, #0

1:
  stmne r10!, {r0, r1, r2, r3, r4, r5, r6, r8}
  subnes r12, r12, #8
  bne 1b

  # cleanup and return

  mov r0, #0
  pop {r8, r10, r11}
  pop {r4, r5, r6, r7, pc}
END_FUNCTION

// ---------------------------------

// fill_neon_words1()
//
// Fill words loop w NEON

BEGIN_FUNCTION fill_neon_words1
  push {lr}
  // r0 = wordPtr
  // r1 = inWord
  // r2 = numWordsToFill

  // Load inWord into NEON registers
  vdup.32 q0, r1
  vdup.32 q1, r1
  vdup.32 q2, r1
  vdup.32 q3, r1

1:
  sub r2, r2, #16
  vstm r0!, {d0-d7}
  cmp r2, #15
  bgt 1b

  mov r0, #0
  pop {pc}
END_FUNCTION

// Like fill_neon_loop1 except use 2x the number of neon registers

BEGIN_FUNCTION fill_neon_words2
  push {lr}
  // r0 = wordPtr
  // r1 = inWord
  // r2 = numWordsToFill

  vstmdb	sp!, {d8-d15}

  // Load inWord into NEON registers
  vdup.32 q0, r1
  vdup.32 q1, r1
  vdup.32 q2, r1
  vdup.32 q3, r1

  vdup.32 q4, r1
  vdup.32 q5, r1
  vdup.32 q6, r1
  vdup.32 q7, r1

1:
  sub r2, r2, #32
  vstm r0!, {d0-d15}
  cmp r2, #31
  bgt 1b

  # cleanup and return

  mov r0, #0
  vldmia	sp!, {d8-d15}
  pop {pc}
END_FUNCTION


// Write 64 bit values with alignment hints

BEGIN_FUNCTION fill_neon_words3
  push {lr}

  // Load inWord into NEON registers
  vdup.32 q0, r1
  vdup.32 q1, r1

1:
  sub r2, r2, #16
  vst1.64         {d0-d3}, [r0,:128]!
  vst1.64         {d0-d3}, [r0,:128]!
  cmp r2, #15
  bgt 1b

  # cleanup and return

  mov r0, #0
  pop {pc}
END_FUNCTION


// Mixing ARM and NEON instructions
// This code has very poor performance for large buffers and should not be used
// since it takes a long time on iPad2 CPU

BEGIN_FUNCTION fill_neon_words4
  push            {r4-r11}
  // r0 = pointer to write to
  mov             r3,  r0
  // r1 = initial value
  vdup.32         q0,  r1
  vmov            q1,  q0

  mov             r4,  r1
  mov             r5,  r1
  mov             r6,  r1
  mov             r7,  r1
  mov             r8,  r1
  mov             r9,  r1
  mov             r10, r1
  mov             r11, r1
  // r12 = ptr + num words
  add             r12, r3,  r2
1:
  subs            r2,  r2, #32
  // why pld when writing?
  pld             [r3, #64]
  stm             r3!, {r4-r11}
  vst1.64         {d0-d3}, [r12,:128]!
  vst1.64         {d0-d3}, [r12,:128]!
  vst1.64         {d0-d3}, [r12,:128]!
  bgt             1b

  pop             {r4-r11}
END_FUNCTION



// memcpy

/*
 
 impl from iPad
 
 0x394bea2c  <+0156>  push       {r5, r6, r8, r10}
 0x394bea30  <+0160>  ldm        r1!, {r3, r4, r5, r6, r8, r9, r10, r12}
 0x394bea34  <+0164>  subs       r2, r2, #64     ; 0x40
 0x394bea38  <+0168>  stmia      r0!, {r3, r4, r5, r6, r8, r9, r10, r12}
 0x394bea3c  <+0172>  pld        [r1, #96]
 0x394bea40  <+0176>  ldm        r1!, {r3, r4, r5, r6, r8, r9, r10, r12}
 0x394bea44  <+0180>  pld        [r1, #96]
 0x394bea48  <+0184>  stmia      r0!, {r3, r4, r5, r6, r8, r9, r10, r12}
 0x394bea4c  <+0188>  bcs        0x394bea30 <memmove$VARIANT$CortexA9+160>
 
 */

/*
 
 But the iPhone4 impl does this:
 
 0x3496fdc0  <+0704>  vld1.64	{d4-d7}, [r1, :256]!
 0x3496fdc4  <+0708>  vst1.64	{d0-d3}, [r12, :256]!
 0x3496fdc8  <+0712>  vld1.64	{d0-d3}, [r1, :256]!
 0x3496fdcc  <+0716>  subs	r2, #64
 0x3496fdce  <+0718>  vst1.64	{d4-d7}, [r12, :256]!
 0x3496fdd2  <+0722>  bge.n	0x3496fdc0 <memmove$VARIANT$CortexA8+704>
 
 */

// URLS:

// https://github.com/Apple-FOSS-Mirror/Libc/blob/master/arm/string/bcopy_CortexA8.s
// https://github.com/Apple-FOSS-Mirror/Libc/blob/master/arm/string/bcopy_CortexA9.s

// Note that there is no Cortex8 vs Cortex9 impl for memset_pattern4(), it is just
// a series of calls to stm to write after aligningthe output to 16 bytes (quad words).

// But, bzero does have specific implementations. These do not seem to be too useful
// though since the code to use NEON in some cases falls back to stm after a max size.

// So, both the fill and the copy impls could take advantage of this approach!
// But, a runtime switch between different implementation is needed via a trampoline

// Note the pld [r1, #96] after the ldm, order not too likely to matter



// This is the most optimal version of ARM code found via testing on ARM6 hardware.

// memcopy_arm_words1(uint32_t *outWordPtr, uint32_t *inWordPtr, uint32_t numWords)

BEGIN_FUNCTION memcopy_arm_words1
  stmfd sp!, {r4, r5, r6, r7, lr}
  add r7, sp, #12
  stmfd sp!, {r8, r10, r11}

  // r0 = outWordPtr
  // r1 = inWordPtr
  // r2 = numWordsToFill

  // r10 = outWordPtr
  mov r10, r0
  // r9 = inWordPtr
  mov r9, r1
  // r11 = numWordsToFill
  mov r11, r2

  cmp	r11, #15
  bls	2f

  // Note that without the pld calls, this code runs a lot slower!
1:
  ldm r9!, {r0, r1, r2, r3, r4, r5, r6, r8}
  pld	[r9, #32]
  sub r11, r11, #16
  stm r10!, {r0, r1, r2, r3, r4, r5, r6, r8}
  ldm r9!, {r0, r1, r2, r3, r4, r5, r6, r8}
  pld	[r9, #32]
  cmp r11, #15
  stm r10!, {r0, r1, r2, r3, r4, r5, r6, r8}
  bgt 1b

2:
  mov r0, #0
  ldmfd	sp!, {r8, r10, r11}
  ldmfd	sp!, {r4, r5, r6, r7, pc}
END_FUNCTION


// memcopy_arm_words2 builds on the previous fastest impl but
// uses all adjacent registers and reorders the instructions
// to attempt to get the fastest possible code.

// memcopy_arm_words2(uint32_t *outWordPtr, uint32_t *inWordPtr, uint32_t numWords)

BEGIN_FUNCTION memcopy_arm_words2
  stmfd sp!, {r4, r5, r6, r7, lr}
  add r7, sp, #12
  stmfd sp!, {r8, r10, r11}

  #define PRELOAD_NUM_BYTES #32
  pld	[r1, PRELOAD_NUM_BYTES]

  #define outWordPtr r10
  mov outWordPtr, r0

  #define inWordPtr r6
  mov inWordPtr, r1

  #define numWordsToFill r11
  mov numWordsToFill, r2

  cmp	numWordsToFill, #15
  bls	2f

  // use registers that are next to each other, so that
  // 64 bit reads can be done in one cycle.

  // Note that this specific preload size and locations
  // mixed into the ldm/stm stream seems to give the
  // optimal results. Switching to 1 preload of 64
  // bytes significantly reduces performance on iPad2.
  // The sub and cmp was replaced by subs and the
  // move in between the stm and ldm.

1:
  ldm inWordPtr!, {r0, r1, r2, r3, r4, r5, r8, r9}
  pld	[inWordPtr, PRELOAD_NUM_BYTES]
  stm outWordPtr!, {r0, r1, r2, r3, r4, r5, r8, r9}
  subs numWordsToFill, numWordsToFill, #16
  ldm inWordPtr!, {r0, r1, r2, r3, r4, r5, r8, r9}
  pld	[inWordPtr, PRELOAD_NUM_BYTES]
  stm outWordPtr!, {r0, r1, r2, r3, r4, r5, r8, r9}
  bne 1b

2:
  mov r0, #0
  ldmfd	sp!, {r8, r10, r11}
  ldmfd	sp!, {r4, r5, r6, r7, pc}
  #undef outWordPtr
  #undef inWordPtr
  #undef numWordsToFill
  #undef PRELOAD_NUM_BYTES
END_FUNCTION


// while words2 does improve things a bit, the Cortex-8 arch and newer now
// feature dual issue ARM instructions and that changes things a bit.
// As compared to the code above, this impl will move the pld instruction
// after the stm since the register writeback from the ldm would not actually
// be completed by the time pld was executed. The Cortex-8 should optimize
// the ldm/stm pairs in hardware to do the regiter writes as soon as the reads
// are completed. If the ldm/stm instructions are processed in pairs, then this
// ordering should not have any register conflicts between pairs of executed instructions.

// memcopy_arm_words3(uint32_t *outWordPtr, uint32_t *inWordPtr, uint32_t numWords)

BEGIN_FUNCTION memcopy_arm_words3
  stmfd sp!, {r4, r5, r6, r7, lr}
  add r7, sp, #12
  stmfd sp!, {r8, r10, r11}

  pld [r1]
  mov r10, r0
  mov r6, r1
  mov r11, r2

  cmp	r11, #15
  bls	2f

  // preload instruction moved after the stm to avoid conflict
  // with writeback on r6. Testing seems to indicate that
  // this change had no effect or might have made things a bit
  // slower. Clearly slower on iPad2. Not a clear slowdown on
  // iPhone4, but that code is slower than NEON/memcpy anyway.

1:
  ldm r6!, {r0, r1, r2, r3, r4, r5, r8, r9}
  stm r10!, {r0, r1, r2, r3, r4, r5, r8, r9}
  pld	[r6, #32]
  subs r11, r11, #16
  ldm r6!, {r0, r1, r2, r3, r4, r5, r8, r9}
  stm r10!, {r0, r1, r2, r3, r4, r5, r8, r9}
  pld	[r6, #32]
  bne 1b

2:
  mov r0, #0
  ldmfd	sp!, {r8, r10, r11}
  ldmfd	sp!, {r4, r5, r6, r7, pc}
END_FUNCTION


/*

// words4 attempts to undo the performance degredation in word3 which could
// have been caused by interlock between the registers in the ldm/stm pair
// or possibly due to dual issue not being possible on this instructions.
// The pld could be acting like a nop.

// memcopy_arm_words4(uint32_t *outWordPtr, uint32_t *inWordPtr, uint32_t numWords)

BEGIN_FUNCTION memcopy_arm_words4
  stmfd sp!, {r4, r5, r6, r7, lr}
  add r7, sp, #12
  stmfd sp!, {r8, r10, r11}

  pld [r1]
  mov r10, r0
  mov r6, r1
  mov r11, r2

  cmp	r11, #15
  bls	2f

  // move preload before ldm so that the two registers
  // are not in conflict during instruction decoding.
  // This impl performs significantly worse on iPad2.

1:
  pld	[r6, #32]
  ldm r6!, {r0, r1, r2, r3, r4, r5, r8, r9}
  subs r11, r11, #16
  stm r10!, {r0, r1, r2, r3, r4, r5, r8, r9}
  pld	[r6, #32]
  ldm r6!, {r0, r1, r2, r3, r4, r5, r8, r9}
  // FIXME: does putting NOP here help?
  stm r10!, {r0, r1, r2, r3, r4, r5, r8, r9}
  bne 1b

2:
  mov r0, #0
  ldmfd	sp!, {r8, r10, r11}
  ldmfd	sp!, {r4, r5, r6, r7, pc}
END_FUNCTION

*/



// words4 attempts to undo the performance degredation in word3 which could
// have been caused by interlock between the registers in the ldm/stm pair
// or possibly due to dual issue not being possible on this instructions.
// The pld could be acting like a nop.

// memcopy_arm_words4(uint32_t *outWordPtr, uint32_t *inWordPtr, uint32_t numWords)

BEGIN_FUNCTION memcopy_arm_words4
  stmfd sp!, {r4, r5, r6, r7, lr}
  add r7, sp, #12
  stmfd sp!, {r8, r10, r11}

  mov r10, r0
  mov r6, r1
  mov r11, r2

  cmp	r11, #15
  bls	2f

/*
  // Use non-conflicting register r12 for pld
  // to avoid a conflict waiting for r6 in
  // the pld instruction

  pld [r6, #0]
  add r12, r6, #32

1:
  ldm r6!, {r0, r1, r2, r3, r4, r5, r8, r9}
  pld	[r12, #32]
  stm r10!, {r0, r1, r2, r3, r4, r5, r8, r9}
  subs r11, r11, #16
  ldm r6!, {r0, r1, r2, r3, r4, r5, r8, r9}
  pld	[r12, #64]
  stm r10!, {r0, r1, r2, r3, r4, r5, r8, r9}
  add r12, r6, #32
  bne 1b
*/

  // Use non-conflicting register r12 for pld
  // to avoid a conflict waiting for r6 in
  // the pld instruction

  pld [r6, #0]
  pld [r6, #32]
  pld [r6, #64]
  pld [r6, #96]
  add r12, r6, #32

1:
  ldm r6!, {r0, r1, r2, r3, r4, r5, r8, r9}
  pld	[r12, #96]
  stm r10!, {r0, r1, r2, r3, r4, r5, r8, r9}
  subs r11, r11, #16
  ldm r6!, {r0, r1, r2, r3, r4, r5, r8, r9}
  pld	[r12, #160]
  stm r10!, {r0, r1, r2, r3, r4, r5, r8, r9}
  add r12, r6, #32
  bne 1b

2:
  mov r0, #0
  ldmfd	sp!, {r8, r10, r11}
  ldmfd	sp!, {r4, r5, r6, r7, pc}
END_FUNCTION





/*

// This impl is a crazy idea built around the basic question of, is it
// possible to use the ARM and NEON registers to implement a memcpy
// that reads are writes from two different address in the buffer
// to be copied. If the buffer is large enough, then starting at the
// halfway point and doing 2 writes offset by half the buffer length
// might provide some runtime benefit. This only seems useful if the
// ARM and NEON cores can write without blockign each other out.

// memcopy_arm_words4(uint32_t *outWordPtr, uint32_t *inWordPtr, uint32_t numWords)

BEGIN_FUNCTION memcopy_arm_words4
  stmfd sp!, {r4, r5, r6, r7, lr}
  add r7, sp, #12
  stmfd sp!, {r8, r10, r11}

  pld [r1]
  mov r10, r0
  mov r6, r1
  mov r11, r2
 
  // Each copy region needs and in pointer and an out pointer.
  // Read size should be the same for each loop, so 1 counter
  // can count down to zero. Might need to divide to determine
  // where the bounds are, but could likely do this with a large
  // enough MOD AND kind of operation.
 
  // Need 2 pointers, 1st is to start of copy region, 2nd is to
  // the
 
  // make r12 the second pointer ?
  // or is it possible for each write to be offset by a variable
  // or constant amount?

  cmp	r11, #15
  bls	2f

  // move preload before ldm so that the two registers
  // are not in conflict during instruction decoding.

1:
  pld	[r6, #32]
  ldm r6!, {r0, r1, r2, r3, r4, r5, r8, r9}
  subs r11, r11, #16
  stm r10!, {r0, r1, r2, r3, r4, r5, r8, r9}
  pld	[r6, #32]
  ldm r6!, {r0, r1, r2, r3, r4, r5, r8, r9}
  // FIXME: does putting NOP here help?
  stm r10!, {r0, r1, r2, r3, r4, r5, r8, r9}
  bne 1b

2:
  mov r0, #0
  ldmfd	sp!, {r8, r10, r11}
  ldmfd	sp!, {r4, r5, r6, r7, pc}
END_FUNCTION

 
*/

// memcopy_arm_words5 is an attempt to use the ldrd and strd instructions
// to do nothing but 64 bit moves. This actually seems to be quite a bit
// slower than ldm/stm.

// memcopy_arm_words5(uint32_t *outWordPtr, uint32_t *inWordPtr, uint32_t numWords)

BEGIN_FUNCTION memcopy_arm_words5
  stmfd sp!, {r4, r5, r6, r7, lr}
  add r7, sp, #12
  stmfd sp!, {r8, r10, r11}

  // r0 = outWordPtr
  // r1 = inWordPtr
  // r2 = numWordsToFill

  pld	[r1, #32]

  // r6 = outWordPtr
  mov r6, r0
  // r9 = inWordPtr
  mov r9, r1
  // r8 = numWordsToFill
  mov r8, r2

  cmp	r8, #0
  beq	2f

1:
  // Load 64 bit values, 4 dwords loaded each loop iteration

  ldrd r0, r1, [r9, #0]
  ldrd r2, r3, [r9, #8]

  subs r8, r8, #8

  strd r0, r1, [r6, #0]
  strd r2, r3, [r6, #8]

  ldrd r0, r1, [r9, #16]
  ldrd r2, r3, [r9, #24]

  add  r9, r9, #32

  strd r0, r1, [r6, #16]
  strd r2, r3, [r6, #24]

  add  r6, r6, #32

  pld	[r9, #32]

  bne 1b

2:
  mov r0, #0
  ldmfd	sp!, {r8, r10, r11}
  ldmfd	sp!, {r4, r5, r6, r7, pc}
END_FUNCTION



// This NEON impl represents what ARM states is the fastest NEON loop for Cortex-8

// http://infocenter.arm.com/help/index.jsp?topic=/com.arm.doc.faqs/ka13544.html

// memcopy_neon_words1(uint32_t *outWordPtr, uint32_t *inWordPtr, uint32_t numWords)

BEGIN_FUNCTION memcopy_neon_words1
  push {lr}
  // r0 = outWordPtr
  // r1 = inWordPtr
  // r2 = numWordsToFill

1:
  pld [r1, #192]
  vldm r1!, {d0-d7}
  vstm r0!, {d0-d7}
  subs r2, r2, #16
  bne 1b

  // FIXME: complete impl would need to cleanup in the case
  // where numWordsToFill is not a multiple of 16

  mov r0, #0
  pop {pc}
END_FUNCTION


// memcopy_call_memcpy(uint32_t *outWordPtr, uint32_t *inWordPtr, uint32_t numWords)

BEGIN_FUNCTION memcopy_call_memcpy
  push	{r7, lr}
  mov	r7, sp
  // memcpy(void *restrict s1, const void *restrict s2, size_t n)
  // r0 set by caller
  // r1 set by caller
  // r2 convert words to bytes
  lsls	r2, r2, #2
  bl _memcpy
  pop	{r7, pc}
END_FUNCTION

// fill_thumb_words
//
// fill with thumb2 mode instructions to see if decode time is smaller?

.syntax unified

BEGIN_FUNCTION_THUMB _fill_thumb_words
  push  {r4,r5,r6, r7,lr}
  add		r7, sp, #12
  push  {r8,r10,r11,r14}

  // r12 will hold numWordsToFill while the loops runs
  mov r12, r2

  // Move r0 into r10, r10 will be the output ptr
  mov r10, r0

  // Load inWord into registers

  mov r0, r1
  mov r2, r1
  mov r3, r0
  mov r4, r0
  mov r5, r0
  mov r6, r0
  mov r7, r0

1:
  sub r12, r12, #8
  stmia r10!, {r0, r1, r2, r3, r4, r5, r6, r7}
  cmp r12, #0
  bne 1b

  pop		{r8,r10,r11,r14}
  pop		{r4,r5,r6, r7,pc}
END_FUNCTION

  .subsections_via_symbols
#else
  // No-op when USE_GENERATED_ARM_ASM is not defined
#endif
