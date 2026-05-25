#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# --- 1. Define Paths ---
usage() {
    echo "Usage: $0 --prefix <path> --bsp <arch/board> [--build-tests]" >&2
    echo "  --prefix      Toolchain prefix" >&2
    echo "  --bsp         RTEMS BSP (arch/board); target derived as <arch>-rtems7" >&2
    echo "  --build-tests Enable BUILD_TESTS and remove redundant per-suite test options" >&2
    echo "  -h, --help    Show this help" >&2
}

PREFIX=""
TARGET=""
BSP=""
BUILD_ALL_TESTS=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix)
            shift
            if [ $# -eq 0 ] || [ -z "${1:-}" ]; then
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
            if [ $# -eq 0 ] || [ -z "${1:-}" ]; then
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
        --build-tests|--enable-tests)
            BUILD_ALL_TESTS=true
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

for tool in "${CLANG_BIN}" "${CLANGXX_BIN}" "${GCC_BIN}" "${GXX_BIN}"; do
    if [ ! -x "${tool}" ]; then
        echo "error: required tool not found or not executable: ${tool}" >&2
        exit 1
    fi
done

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

"${SCRIPT_DIR}/rtems-clang-wrapper.sh" --install --prefix "${PREFIX}" --target "${TARGET}"

cd src/rtems

# Clean previous Waf states
./waf distclean

config_set_value() {
    local key="$1"
    local value="$2"

    if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" config.ini; then
        awk -v key="$key" -v value="$value" '
            $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
                print key " = " value
                next
            }
            { print }
        ' config.ini > config.ini.tmp
        mv config.ini.tmp config.ini
    else
        printf "%s = %s\n" "$key" "$value" >> config.ini
    fi
}

config_append_flags() {
    local key="$1"
    local value="$2"

    if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" config.ini; then
        awk -v key="$key" -v value="$value" '
            function trim(s) {
                sub(/^[[:space:]]+/, "", s)
                sub(/[[:space:]]+$/, "", s)
                return s
            }

            function has_token(list, token) {
                return index(" " list " ", " " token " ") > 0
            }

            $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
                existing = $0
                sub(/^[[:space:]]*[^=]+=[[:space:]]*/, "", existing)
                existing = trim(existing)
                merged = existing

                count = split(value, flags, /[[:space:]]+/)
                for (i = 1; i <= count; ++i) {
                    flag = flags[i]
                    if (flag != "" && !has_token(merged, flag)) {
                        merged = merged (merged == "" ? "" : " ") flag
                    }
                }

                print key " = " merged
                next
            }
            { print }
        ' config.ini > config.ini.tmp
        mv config.ini.tmp config.ini
    else
        printf "%s = %s\n" "$key" "$value" >> config.ini
    fi
}

config_remove_build_tests_overrides() {
    awk '
        function flush_comments() {
            if (comments != "") {
                printf "%s", comments
                comments = ""
            }
        }

        function is_redundant_test_build_option(key) {
            return key == "BUILD_ADATESTS" || \
                key == "BUILD_BENCHMARKS" || \
                key == "BUILD_FSTESTS" || \
                key == "BUILD_LIBTESTS" || \
                key == "BUILD_MPTESTS" || \
                key == "BUILD_PSXTESTS" || \
                key == "BUILD_PSXTMTESTS" || \
                key == "BUILD_RHEALSTONE" || \
                key == "BUILD_SAMPLES" || \
                key == "BUILD_SMPTESTS" || \
                key == "BUILD_SPTESTS" || \
                key == "BUILD_TMTESTS" || \
                key == "BUILD_UNITTESTS" || \
                key == "BUILD_VALIDATIONTESTS"
        }

        /^[[:space:]]*[#;]/ {
            comments = comments $0 ORS
            next
        }

        /^[[:space:]]*[A-Za-z0-9_]+[[:space:]]*=/ {
            key = $0
            sub(/^[[:space:]]*/, "", key)
            sub(/[[:space:]]*=.*/, "", key)

            if (key != "BUILD_TESTS" && \
                (is_redundant_test_build_option(key) || \
                (key ~ /^BUILD_[A-Za-z0-9_]+$/ && \
                comments ~ /may be also enabled by/ && \
                comments ~ /BUILD_TESTS/))) {
                comments = ""
                next
            }
        }

        {
            flush_comments()
            print
        }

        END {
            flush_comments()
        }
    ' config.ini > config.ini.tmp
    mv config.ini.tmp config.ini
}

./waf bspdefaults --rtems-bsps="${BSP}" --rtems-compiler=clang > config.ini

config_set_value "COMPILER" "clang"
config_append_flags "WARNING_FLAGS" "-Wall -Wextra -Wno-error"
config_append_flags "CC_WARNING_FLAGS" "-Wno-error -Wmissing-prototypes -Wimplicit-function-declaration -Wstrict-prototypes -Wnested-externs -Wno-asm-operand-widths -Wno-unknown-warning-option"

if [ "${BUILD_ALL_TESTS}" = true ]; then
    config_remove_build_tests_overrides
    config_set_value "BUILD_TESTS" "True"
fi

CLANG_TARGET_FLAG="--target=${BSP_ARCH}-unknown-rtems7"

ABI_INCLUDE_FLAGS="-I${SYSROOT_INCLUDE_DIR} -I${CLANG_RESOURCE_DIR}/include"

COMMON_FLAGS="-D__rtems__ --sysroot=${SYSROOT}"

case "${BSP}" in
    arm/stm32f4|arm/stm32f446ze)
        config_append_flags "ABI_FLAGS" "-mcpu=cortex-m4 -mthumb -mfloat-abi=hard -mfpu=fpv4-sp-d16 ${CLANG_TARGET_FLAG} ${COMMON_FLAGS} ${ABI_INCLUDE_FLAGS}"
        ;;
    arm/stm32f105rc)
        config_append_flags "ABI_FLAGS" "-mthumb -mcpu=cortex-m3 ${CLANG_TARGET_FLAG} ${COMMON_FLAGS} ${ABI_INCLUDE_FLAGS}"
        ;;
    *)
        config_append_flags "ABI_FLAGS" "${CLANG_TARGET_FLAG} ${COMMON_FLAGS} ${ABI_INCLUDE_FLAGS}"
        ;;
esac

# C include flags for RTEMS/newlib + GCC support headers.
C_INCLUDE_FLAGS="-isystem ${SYSROOT_INCLUDE_DIR} -isystem ${CLANG_RESOURCE_DIR}/include -isystem ${GCC_INCLUDE_DIR} -isystem ${GCC_INCLUDE_FIXED_DIR}"

# C++ include order mirrors GCC. Use -idirafter for sysroot/clang fallback to keep include_next working.
CXX_INCLUDE_FLAGS="-isystem ${GXX_INCLUDE_DIR} -isystem ${GXX_TARGET_INCLUDE_DIR} -isystem ${GXX_BACKWARD_INCLUDE_DIR} -isystem ${GCC_INCLUDE_DIR} -isystem ${GCC_INCLUDE_FIXED_DIR}"
CXX_AFTER_INCLUDE_FLAGS="-idirafter ${SYSROOT_INCLUDE_DIR} -idirafter ${CLANG_RESOURCE_DIR}/include"

# Assembler preprocessor includes: enough for headers like limits.h used by .S paths.
AS_INCLUDE_FLAGS="-isystem ${SYSROOT_INCLUDE_DIR} -isystem ${CLANG_RESOURCE_DIR}/include"

GCC_VERSION=$(${GCC_BIN} -dumpversion)
GCC_LIB_DIR="${PREFIX}/lib/gcc/${TARGET}/${GCC_VERSION}"

# -B flags tell Clang where to find the RTEMS linker, assembler, and crt*.o files
B_FLAGS="-B${SYSROOT}/lib -B${GCC_LIB_DIR} -B${PREFIX}/bin"

CFLAGS_EFFECTIVE="${CLANG_TARGET_FLAG} ${COMMON_FLAGS} ${B_FLAGS} ${C_INCLUDE_FLAGS}"
CXXFLAGS_EFFECTIVE="${CLANG_TARGET_FLAG} ${COMMON_FLAGS} ${B_FLAGS} ${CXX_INCLUDE_FLAGS} ${CXX_AFTER_INCLUDE_FLAGS}"
ASFLAGS_EFFECTIVE="${CLANG_TARGET_FLAG} ${COMMON_FLAGS} ${B_FLAGS} ${AS_INCLUDE_FLAGS}"
LDFLAGS_EFFECTIVE="${CLANG_TARGET_FLAG} ${COMMON_FLAGS} ${B_FLAGS}"

config_set_value "RTEMS_POSIX_API" "True"

# --- 3. Configure and Build ---
# Keep explicit C/C++ flags for waf configure checks and the build.
export CFLAGS="${CFLAGS_EFFECTIVE}"
export CXXFLAGS="${CXXFLAGS_EFFECTIVE}"
export ASFLAGS="${ASFLAGS_EFFECTIVE}"
export LDFLAGS="${LDFLAGS_EFFECTIVE}"

./waf configure --prefix="${PREFIX}" --rtems-tools="${PREFIX}/wrappers"

echo "Logging to file build.log..."

./waf > ../../build.log 2>&1 &
WAF_PID=$!

tail --pid=$WAF_PID -f ../../build.log

wait $WAF_PID


if [ $? -ne 0 ]; then
    echo "Build failed; rerunning with -v. See build.log for the verbose command output." >&2
    ./waf -v > ../../build.log 2>&1
fi
