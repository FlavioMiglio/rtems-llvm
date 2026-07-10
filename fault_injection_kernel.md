# Kernel Control-Flow Fault Injection on RTEMS

This guide provides instructions on how to perform control-flow fault injection on a hardened RTEMS kernel function. Unlike the data-corruption test on the application workload, here we target a real kernel function (`_Timespec_Is_valid`) hardened with ASPIS's control-flow checking (RASM), and we trigger the fault by corrupting the program counter (PC) instead of a data variable.

## The Test Payload

We use `_Timespec_Is_valid`, a function from the RTEMS score that performs a series of validity checks on a `struct timespec`. Because it consists only of branches (no data computation), ASPIS protects it through **RASM** (control-flow checking) rather than EDDI. The source is located at:

* **Hardened:** [timespecisvalid.c](https://github.com/FlavioMiglio/rtems/blob/main/cpukit/score/src/timespecisvalid.c)

Here is the core logic:

```c
bool _Timespec_Is_valid( const struct timespec *time )
{
  if ( !time ) {
    return false;
  }
  if ( time->tv_sec < 0 ) {
    return false;
  }
  if ( time->tv_nsec < 0 ) {
    return false;
  }
  if ( time->tv_nsec >= TOD_NANOSECONDS_PER_SECOND ) {
    return false;
  }
  return true;
}
```

RASM instruments this function with a per-block **signature** stored on the stack. Each basic block updates the signature by a known constant, and at control-flow merge points the signature is compared against a value precomputed at compile time (e.g. `cmp r0, #2`, `cmp r0, #4`). If the flow reaches a checkpoint via an illegitimate path, the signature does not match and `SigMismatch_Handler` is called.

## The Handlers

The hardened file defines the two ASPIS handlers. Since this is kernel-side code, they use `printk` (not `printf`) and enter an infinite loop as a fail-stop:

```c
void DataCorruption_Handler(void) {
  printk("\n[!] KERNEL PANIC - ASPIS: DATA CORRUPTION IN TIMESPEC\n");
  while(1);
}
void SigMismatch_Handler(void) {
  printk("\n[!] KERNEL PANIC - ASPIS: SIG MISMATCH IN TIMESPEC\n");
  while(1);
}
```

---

## Injecting the Control-Flow Fault

*Note: Keep a UART terminal connected to the STM32 open to monitor the output.*

Start the GDB server in the background and attach the debugger to the test that exercises `_Timespec_Is_valid`:

```bash
cd /opt/rtems-llvm/src/rtems
pkill st-util
st-util &
arm-rtems7-gdb build/arm/stm32f4/testsuites/sptests/sptimespec01.exe
```

*(Note: If GDB throws an `auto-load safe-path` warning, ignore it. We bypass it in the next step).*

Inside the GDB prompt, set up the environment, load the firmware, and break at the target function:

```text
(gdb) set auto-load safe-path /
(gdb) target remote :4242
(gdb) load
(gdb) break _Timespec_Is_valid
(gdb) c
```

Execution is now paused at the entry of `_Timespec_Is_valid`. Inspect the disassembly to locate the basic blocks and the RASM checkpoints:

```text
(gdb) disassemble
```

You will see the RASM instrumentation: a signature loaded from the stack, updated per block, and compared against fixed values before branching to `SigMismatch_Handler`. For example:

```text
   0x08007f48 <+36>:	str	r0, [sp, #20]
   0x08007f4a <+38>:	bne.n	0x8007f6a <_Timespec_Is_valid+70>
   0x08007f4c <+40>:	b.n	0x8007f4e <_Timespec_Is_valid+42>
   ...
   0x08007f54 <+48>:	cmp	r0, #2
   0x08007f56 <+50>:	bne.w	0x800808e <_Timespec_Is_valid+362>
   ...
   0x08007f70 <+76>:	cmp	r0, #4
```

Set a breakpoint just before a branch instruction, then continue to reach it:

```text
(gdb) b *0x08007f4a
(gdb) c
```

Now inject the fault: force the program counter to jump to a different basic block, bypassing the legitimate path. This simulates a control-flow error (as would be caused by a bit-flip in the PC). Here we jump from `+38` directly to `+70`, skipping the block at `+42..+68`:

```text
(gdb) set $pc = 0x08007f6a
(gdb) c
```

Because the flow reached `+70` without traversing the blocks that would have updated the signature correctly, the signature no longer matches the value expected at the next checkpoint. RASM detects the mismatch and jumps to `SigMismatch_Handler`.

Check your UART terminal. Instead of silently continuing with a corrupted execution flow, the system catches the fault:

```text
[!] KERNEL PANIC - ASPIS: SIG MISMATCH IN TIMESPEC
```

To confirm in GDB, press `Ctrl+C` and inspect where execution halted; it will be inside the handler's infinite loop:

```text
(gdb) backtrace
#0  SigMismatch_Handler () at ../../../cpukit/score/src/timespecisvalid.c:79
79	  while(1);
```

To exit GDB, press `Ctrl+C`, type `q`, and confirm.

