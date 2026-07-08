
# ASPIS hardening POC for RTEMS + LLVM


## 1. Hardware Setup (STM32F4 Discovery)
To run this POC, you need an STM32F4 Discovery board and a USB-to-UART adapter.

1. Power the board by connecting a micro-USB cable to the **CN1** interface.
2. Connect the USB-to-UART adapter pins as follows:
   * **RX** -> **PD8**
   * **TX** -> **PD9**
   * **GND** -> **GND**
3. Plug the UART adapter into your PC. Identify the assigned serial port (e.g., `/dev/ttyUSB0` or `/dev/ttyACM0`) by running:

```bash
   dmesg | grep -i tty

```

## 2. Clone and Initialize Submodules

Clone the repository, then initialize and download the required submodules (`rtems`, `rtems-rsb`, and `ASPIS`):

```bash
git submodule update --init --recursive

```

## 3. Start the Environment

Use either Docker or Podman to start the containerized environment. All subsequent compilation commands must be run inside this container. The default working directory is `/opt/rtems-llvm`.

**Using Docker:**

```bash
docker compose -f docker-compose.yml -f docker-compose.podman.yml up -d
docker compose exec dev /bin/bash

```

**Using Podman:**
*(Podman requires explicitly inheriting permissions to read the UART interface)*

```bash
podman-compose -f docker-compose.yml -f docker-compose.podman.yml up -d
podman compose exec dev /bin/bash

```

## 4. Build the Toolchain

The toolchain is built using the RTEMS Source Builder (RSB). It first builds the ARM GCC cross-compiler, then the LLVM/Clang toolchain.
*Note: This step is CPU-intensive and can take 2 to 5 hours.*

```bash
cd src/rtems-rsb/rtems
../source-builder/sb-set-builder --prefix=/opt/rtems-llvm/rtems 7/rtems-arm
chmod -R u+w /opt/rtems-llvm/rtems
../source-builder/sb-set-builder --prefix=/opt/rtems-llvm/rtems 7/rtems-llvm

```

## 5. Build ASPIS

Compile the ASPIS hardening pass using the LLVM toolchain built in the previous step.

```bash
cd /opt/rtems-llvm/ASPIS
git submodule update --init --recursive
mkdir build
cmake -B build -DLLVM_DIR=/opt/rtems-llvm/rtems/lib/cmake/llvm
cmake --build build -j$(nproc)

```

## 6. Build the RTEMS BSP (STM32F4)

Add the new toolchain to your path and build the Board Support Package.

```bash
export PATH="/opt/rtems-llvm/rtems/bin:$PATH"
cd /opt/rtems-llvm/src/rtems

# Copy the configuration file (ensuring it targets the arm/stm32f4 BSP architecture)
cp /opt/rtems-llvm/config.ini .

./waf configure --prefix=/opt/rtems-llvm/rtems
./waf
./waf install

```

## 7. Flash and Test

Convert the compiled binary into a format suitable for flashing, then monitor the output via the UART interface.

**1. Convert the binary:**

```bash
arm-rtems7-objcopy -O binary /opt/rtems-llvm/src/rtems/build/arm/stm32f4/testsuites/samples/aspis_sample aspis_sample.bin

```

**2. Open the serial monitor:**
In a new terminal (on your host machine, outside the container), use `picocom` to listen to the UART port. *Adjust `/dev/ttyUSB0` to match the port you found in Step 1.*

```bash
picocom -b 115200 /dev/ttyUSB0

```

**3. Flash the board:**
In your original terminal, flash the binary to the STM32F4:

```bash
st-flash write aspis_sample.bin 0x8000000

```

**4. Run the program:**
Press the physical **Reset** button on the STM32F4 Discovery board (the cylindrical black button on the right side of the board, usually labeled "B2" or "RESET"). You should now see the program output in the `picocom` terminal.

## 8. Examples of fault injection

To perform a fault injection on an sample application follow [this guide](fault_injection.md)
