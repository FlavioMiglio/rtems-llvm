#!/bin/bash
clear

# --- 1. Define Paths ---
usage() {
    echo "Usage: $0 --prefix <path> --bsp <arch/board>" >&2
    echo "  --prefix   Toolchain prefix" >&2
    echo "  --bsp      RTEMS BSP (arch/board); target derived as <arch>-rtems7" >&2
    echo "  -h, --help Show this help" >&2
}

PREFIX=""
TARGET=""
BSP=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix)
            shift
            if [ -z "$1" ]; then
                echo "error: --prefix requires an argument" >&2
                usage
                exit 2
            fi
            PREFIX="$1"
            ;;
        --prefix=*)
            PREFIX="${1#*=}"
            if [ -z "$PREFIX" ]; then
                echo "error: --prefix requires a value" >&2
                usage
                exit 2
            fi
            ;;
        --bsp)
            shift
            if [ -z "$1" ]; then
                echo "error: --bsp requires an argument" >&2
                usage
                exit 2
            fi
            BSP="$1"
            ;;
        --bsp=*)
            BSP="${1#*=}"
            if [ -z "$BSP" ]; then
                echo "error: --bsp requires a value" >&2
                usage
                exit 2
            fi
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: unexpected argument: $1" >&2
            usage
            exit 2
            ;;
    esac
    shift
done

if [ -z "$PREFIX" ] || [ -z "$BSP" ]; then
    echo "error: --prefix and --bsp are required" >&2
    usage
    exit 2
fi

case "$BSP" in
    */*)
        BSP_ARCH="${BSP%%/*}"
        if [ -z "$BSP_ARCH" ]; then
            echo "error: --bsp must be in the form <arch>/<board>" >&2
            usage
            exit 2
        fi
        ;;
    *)
        echo "error: --bsp must be in the form <arch>/<board>" >&2
        usage
        exit 2
        ;;
esac

TARGET="${BSP_ARCH}-rtems7"

SYSROOT="${PREFIX}/${TARGET}"

# Add toolchains to PATH
if [[ ":$PATH:" != *":${PREFIX}/bin:"* ]]; then
    export PATH="${PREFIX}/bin:$PATH"
fi

if [[ ":$PATH:" != *":${PREFIX}/wrappers:"* ]]; then
    export PATH="${PREFIX}/wrappers:$PATH"
fi

CLANG_BIN="${PREFIX}/bin/clang"
CLANGXX_BIN="${PREFIX}/bin/clang++"
GCC_BIN="${PREFIX}/bin/${TARGET}-gcc"
GXX_BIN="${PREFIX}/bin/${TARGET}-g++"
CLANG_RESOURCE_DIR="$(${CLANG_BIN} --print-resource-dir)"
GCC_INCLUDE_DIR="$(${GCC_BIN} -print-file-name=include)"
GCC_INCLUDE_FIXED_DIR="$(${GCC_BIN} -print-file-name=include-fixed)"
GXX_INCLUDE_DIR="$(${GXX_BIN} -print-file-name=include/c++)"
GXX_TARGET_INCLUDE_DIR="${GXX_INCLUDE_DIR}/${TARGET}"
GXX_BACKWARD_INCLUDE_DIR="${GXX_INCLUDE_DIR}/backward"
SYSROOT_INCLUDE_DIR="${SYSROOT}/include"

if [ ! -d "${CLANG_RESOURCE_DIR}/include" ] || [ ! -d "${GCC_INCLUDE_DIR}" ] || [ ! -d "${GCC_INCLUDE_FIXED_DIR}" ] || [ ! -d "${SYSROOT_INCLUDE_DIR}" ] || [ ! -d "${GXX_INCLUDE_DIR}" ] || [ ! -d "${GXX_TARGET_INCLUDE_DIR}" ] || [ ! -d "${GXX_BACKWARD_INCLUDE_DIR}" ]; then
    echo "error: required include directories not found"
    echo "  clang resource: ${CLANG_RESOURCE_DIR}/include"
    echo "  gcc include:    ${GCC_INCLUDE_DIR}"
    echo "  gcc include-fixed: ${GCC_INCLUDE_FIXED_DIR}"
    echo "  sysroot include:${SYSROOT_INCLUDE_DIR}"
    echo "  g++ include:    ${GXX_INCLUDE_DIR}"
    echo "  g++ target:     ${GXX_TARGET_INCLUDE_DIR}"
    echo "  g++ backward:   ${GXX_BACKWARD_INCLUDE_DIR}"
    exit 1
fi

# Prevent macOS host flags from leaking into the cross-compiler
unset ARCH ARCHFLAGS CFLAGS CXXFLAGS LDFLAGS CPPFLAGS SDKROOT MACOSX_DEPLOYMENT_TARGET

cd src/rtems

# Clean previous Waf states
./waf distclean

echo "[$BSP]" > config.ini
echo "COMPILER = clang" >> config.ini

echo "WARNING_FLAGS = -Wall -Wextra" >> config.ini
echo "CC_WARNING_FLAGS = -Wno-error -Wmissing-prototypes -Wimplicit-function-declaration -Wstrict-prototypes -Wnested-externs -Wno-asm-operand-widths" >> config.ini
echo "BUILD_SAMPLES = True" >> config.ini
echo "BUILD_TESTS = True" >> config.ini

COMMON_FLAGS="-D__rtems__ --sysroot=${SYSROOT}"
# --target=${TARGET}

ABI_INCLUDE_FLAGS="-I${SYSROOT_INCLUDE_DIR} -I${CLANG_RESOURCE_DIR}/include"

# C include flags for RTEMS/newlib + GCC support headers.
C_INCLUDE_FLAGS="-isystem ${SYSROOT_INCLUDE_DIR} -isystem ${CLANG_RESOURCE_DIR}/include -isystem ${GCC_INCLUDE_DIR} -isystem ${GCC_INCLUDE_FIXED_DIR}"

# C++ include order mirrors GCC. Use -idirafter for sysroot/clang fallback to keep include_next working.
CXX_INCLUDE_FLAGS="-isystem ${GXX_INCLUDE_DIR} -isystem ${GXX_TARGET_INCLUDE_DIR} -isystem ${GXX_BACKWARD_INCLUDE_DIR} -isystem ${GCC_INCLUDE_DIR} -isystem ${GCC_INCLUDE_FIXED_DIR}"
CXX_AFTER_INCLUDE_FLAGS="-idirafter ${SYSROOT_INCLUDE_DIR} -idirafter ${CLANG_RESOURCE_DIR}/include"

# Assembler preprocessor includes: enough for headers like limits.h used by .S paths.
AS_INCLUDE_FLAGS="-isystem ${SYSROOT_INCLUDE_DIR} -isystem ${CLANG_RESOURCE_DIR}/include"

CLANG_TARGET_FLAG="--target=${TARGET}"

GCC_VERSION=$(${GCC_BIN} -dumpversion)
GCC_LIB_DIR="${PREFIX}/lib/gcc/${TARGET}/${GCC_VERSION}"

# -B flags tell Clang where to find the RTEMS linker, assembler, and crt*.o files
B_FLAGS="-B${SYSROOT}/lib -B${GCC_LIB_DIR} -B${PREFIX}/bin"

CFLAGS_EFFECTIVE="${CLANG_TARGET_FLAG} ${B_FLAGS} ${C_INCLUDE_FLAGS}"
CXXFLAGS_EFFECTIVE="${CLANG_TARGET_FLAG} ${B_FLAGS} ${CXX_INCLUDE_FLAGS} ${CXX_AFTER_INCLUDE_FLAGS}"
ASFLAGS_EFFECTIVE="${CLANG_TARGET_FLAG} ${B_FLAGS} ${AS_INCLUDE_FLAGS}"
LDFLAGS_EFFECTIVE="${CLANG_TARGET_FLAG} ${COMMON_FLAGS} ${B_FLAGS} -L${SYSROOT}/lib -L${GCC_LIB_DIR}"

echo "ABI_FLAGS = ${CLANG_TARGET_FLAG} ${COMMON_FLAGS} ${ABI_INCLUDE_FLAGS}" >> config.ini
echo "RTEMS_POSIX_API = True" >> config.ini

# --- 3. Configure and Build ---
# Keep explicit C/C++ flags for waf configure checks and the build.
export CFLAGS="${CFLAGS_EFFECTIVE}"
export CXXFLAGS="${CXXFLAGS_EFFECTIVE}"
export ASFLAGS="${ASFLAGS_EFFECTIVE}"
export LDFLAGS="${LDFLAGS_EFFECTIVE}"

./waf configure --prefix="${PREFIX}" --rtems-tools="${PREFIX}/wrappers"
./waf -k > build.log 2>&1
