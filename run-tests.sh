#!/bin/bash

usage() {
    echo "Usage: $0 --prefix <path> --bsp <bsp|arch/bsp>" >&2
    echo "  --prefix   Toolchain prefix" >&2
    echo "  --bsp      RTEMS BSP name, for example a72_lp64_qemu" >&2
    echo "  -h, --help Show this help" >&2
}

PREFIX=""
BSP=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix)
            shift
            if [ "$#" -eq 0 ] || [ -z "$1" ]; then
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
            if [ "$#" -eq 0 ] || [ -z "$1" ]; then
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

if [[ ":$PATH:" != *":${PREFIX}/bin:"* ]]; then
    export PATH="${PREFIX}/bin:$PATH"
fi

clear

cd src/rtems

BSP_NAME="${BSP##*/}"

if [ "$BSP" != "$BSP_NAME" ] && [ -d "build/${BSP}" ]; then
    BUILD_DIR="build/${BSP}"
else
    BUILD_DIR=""
    MATCH_COUNT=0
    for candidate in build/*/"${BSP_NAME}"; do
        if [ -d "$candidate" ]; then
            BUILD_DIR="$candidate"
            MATCH_COUNT=$((MATCH_COUNT + 1))
        fi
    done

    if [ "$MATCH_COUNT" -eq 0 ]; then
        echo "error: could not find build directory for BSP '${BSP_NAME}' under src/rtems/build" >&2
        echo "       expected something like build/<arch>/${BSP_NAME}" >&2
        exit 1
    fi

    if [ "$MATCH_COUNT" -gt 1 ]; then
        echo "error: multiple build directories found for BSP '${BSP_NAME}'" >&2
        echo "       pass --bsp <arch>/${BSP_NAME} to choose one" >&2
        exit 1
    fi
fi

rtems-test --rtems-bsp="${BSP_NAME}" "${BUILD_DIR}/"
