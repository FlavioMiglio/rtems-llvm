# Fault Injection Testing on RTEMS

This guide provides instructions on how to perform fault injection on a basic matrix multiplication workload running on RTEMS. We will test both a standard (non-hardened) version and an ASPIS-hardened version of the workload to observe the differences in behavior when a fault is introduced.

## The Test Payload

We use a basic matrix multiplication workload as our test case. The source code is located at:
* **Standard:** [workload.c](src/rtems/testsuites/samples/aspis_sample/workload.c)
* **Hardened:** [workload.c](src/rtems/testsuites/samples/aspis_sample_hardened/workload.c)

Here is the core logic:

```c
uint32_t workload_run(void)
{
    static uint32_t A[N][N];
    static uint32_t B[N][N];

    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++)
            A[i][j] = (uint32_t)(i * N + j + 1);

    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++) {
            uint32_t acc = 0;
            for (int k = 0; k < N; k++)
                acc += A[i][k] * A[k][j];
            B[i][j] = acc;
        }

    uint32_t checksum = 0;
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++)
            checksum += B[i][j];

    return checksum;
}

```

If the execution completes without errors, the expected checksum is `0x041d4400`.

---

## 1. Injecting the Standard (Non-Hardened) Sample

*Note: Keep a UART terminal connected to the STM32 open to monitor the output.*

Start the GDB server in the background and attach the debugger:

```bash
cd /opt/rtems-llvm/src/rtems
pkill st-util
st-util &
arm-rtems7-gdb build/arm/stm32f4/testsuites/samples/aspis_sample.exe

```

*(Note: If GDB throws an `auto-load safe-path` warning, ignore it. We will bypass it in the next step).*

Inside the GDB prompt, set up the environment, load the firmware, and break at the first matrix assignment:

```text
(gdb) set auto-load safe-path /
(gdb) target remote :4242
(gdb) load
(gdb) b workload.c:19
(gdb) c
(gdb) c

```

The execution is now paused at `A[i][j] = (uint32_t)(i * N + j + 1);` (specifically, assigning `A[0][0]`).
Now, inject the fault by modifying the variable in memory, remove the breakpoint, and resume execution:

```text
(gdb) set var A[0][0] = 42
(gdb) delete 
(gdb) c

```

*(Press `y` to confirm breakpoint deletion).*

Check your UART terminal. The output will show a corrupted checksum:

```text
*** BEGIN OF TEST ASPIS SAMPLE ***
*** TEST VERSION: 7.0.0.7c2f1177160ef9c8cdfb696cbc97a4256342c7d4-modified
*** TEST STATE: EXPECTED_PASS
*** TEST BUILD:
*** TEST TOOLS: RTEMS Clang 21.1.8
checksum = 0x041e9669
done

```

To exit GDB, press `Ctrl+C`, type `q`, and confirm.

---

## 2. Injecting the Hardened Sample

The hardened version includes specific ASPIS handlers to detect faults:

```c
void DataCorruption_Handler() {
  printf("ASPIS: DATA CORRUPTION detected\n");
  while(1);
}

void SigMismatch_Handler() {
  printf("ASPIS: SIG MISMATCH detected\n");
  while(1);
}

```

The injection process is identical. Run the following commands to test the hardened binary:

```bash
pkill st-util
st-util &
arm-rtems7-gdb build/arm/stm32f4/testsuites/samples/aspis_sample_hardened.exe

```

Inside GDB:

```text
(gdb) set auto-load safe-path /
(gdb) target remote :4242
(gdb) load
(gdb) b workload.c:25
(gdb) c
(gdb) c
(gdb) set var A[0][0] = 42
(gdb) delete 
(gdb) c

```

Check the UART terminal. Instead of silently processing the corrupted data and printing a wrong checksum, the system now successfully catches the fault:

```text
*** BEGIN OF TEST ASPIS SAMPLE ***
*** TEST VERSION: 7.0.0.7c2f1177160ef9c8cdfb696cbc97a4256342c7d4-modified
*** TEST STATE: EXPECTED_PASS
*** TEST BUILD:
*** TEST TOOLS: RTEMS Clang 21.1.8
ASPIS: DATA CORRUPTION detected

```
