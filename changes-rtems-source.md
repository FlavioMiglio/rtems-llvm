# Changes to RTEMS source code

## C statements in naked functions

    src/rtems/cpukit/score/cpu/arm/armv7m-context-switch.c
    src/rtems/cpukit/score/cpu/arm/armv7m-context-restore.c
    src/rtems/cpukit/score/cpu/arm/armv7m-multitasking-start-stop.c

These three files contain naked functions which have C statements inside them; this is allowed by GCC (but not by clang) but it's not supported, as described [here](https://gcc.gnu.org/onlinedocs/gcc/Common-Attributes.html#index-naked) in the GCC documentation.

The statements are castings only needed to silence the 'unused variable' warning, since the parameter(s) are only used in assembly code (through registers `r0` and `r1`) which is not parsed by the compiler. Hence it is safe to remove these statements.

## Immediate passed as LDR Pseudo instruction

This assembly instruction is a load which uses an [LDR Pseudo Instruction](https://developer.arm.com/documentation/100069/0606/Data-Transfer-Instructions/LDR-pseudo-instruction)

    "ldr r4, =%[cpacr]\n"

that uses an immediate (defined below in the same file)

    [cpacr] "i" (ARMV7M_CPACR),

There is a difference between clang and gcc in how these immediates are evaluated: gcc returns the raw value, resulting in this assembly instruction: 

    ldr r4, =-536810104

clang instead prepends `#` to immediates, which in this case would result in:

    ldr r4, =#-536810104

The solution is to add the `c` modifier to have the compiler print the constant expression with no punctuation:

    "ldr r4, =%c[cpacr]\n"


