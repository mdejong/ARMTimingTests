//
//  Created by Moses DeJong on 7/2/13.
//  This software has been placed in the public domain.

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


// uint32_t simple_add_result2(uint32_t *outWordPtr, uint32_t numWords)
//
// Optimized ARM add loop, uses a ldm to load multiple words at once
// and then each word value is added to a running sum.

BEGIN_FUNCTION simple_add_result2
  push {r4, r5, r6, r7, lr}
  push {r8, r10, r11}
  // r0 = wordPtr
  // r1 = numWords
  // r2 = sum

  mov r2, #0

  // Read a block of 4 integer values at a time
  // for as many blocks of 4 words remain.

  cmp r1, #4
  blt 2f

1:
  ldm r0!, {r3, r4, r5, r6}
  sub r1, r1, #4
  // r2 = r2 + r3 + r4 + r5 + r6 with minimal register
  // interlock and better use of dual issue.
  add r2, r2, r3
  add r4, r4, r5
  add r2, r2, r6
  cmp r1, #4
  add r2, r2, r4
  bge 1b

2:
  cmp r1, #0
  ldrgt r3, [r0], #4
  subgt r1, r1, #1
  addgt r2, r2, r3
  bgt 1b

  # cleanup and return

  mov r0, r2
  pop {r8, r10, r11}
  pop {r4, r5, r6, r7, pc}
END_FUNCTION



// uint32_t simple_add_result3(uint32_t *outWordPtr, uint32_t numWords)
//
// This impl uses NEON instructions to load blocks of words and then
// add multiple values together with one simd instruction.

BEGIN_FUNCTION simple_add_result3
  push {r4, r5, r6, r7, lr}
  push {r8, r10, r11}

  // r0 = wordPtr
  // r1 = numWords
  // r2 = sum

  mov r2, #0

  // Load 0 into each word in quad word bank 0
  vdup.32 q0, r2

  // Read a block of 4 integer values at a time
  // for as many blocks of 4 words remain.

  cmp r1, #4
  blt 2f

1:
  vld1.32   {q1}, [r0]!

  sub r1, r1, #4

  // q0 = q0 + q1

  vadd.i32  q0, q0, q1

  cmp r1, #4
  bge 1b

  // Mov the values from quad register back into 4 ARM registers.
  // Note that the NEON processor could be running behind the ARM
  // registers so do this load before processing any remaining
  // words and then finish the add once the ARM registers are loaded.

  vmov r3, r4, d0
  vmov r5, r6, d1

2:
  cmp r1, #0
  ldrgt r8, [r0], #4
  subgt r1, r1, #1
  addgt r2, r2, r8
  bgt 2b

  add r3, r3, r4
  add r5, r5, r6
  add r2, r2, r3
  add r2, r2, r5

  # cleanup and return

  mov r0, r2
  pop {r8, r10, r11}
  pop {r4, r5, r6, r7, pc}
END_FUNCTION


  .subsections_via_symbols
#else
  // No-op when USE_GENERATED_ARM_ASM is not defined
#endif
