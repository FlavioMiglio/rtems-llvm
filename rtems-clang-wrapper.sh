#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage:" >&2
    echo "  $0 --install --prefix <path> --target <target>" >&2
    echo "  clang|clang++ [compiler arguments...]" >&2
}

install_wrappers() {
    local prefix=""
    local target=""

    shift
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --prefix)
                shift
                if [ $# -eq 0 ] || [ -z "${1:-}" ]; then
                    echo "error: --prefix requires an argument" >&2
                    usage
                    exit 2
                fi
                prefix="$1"
                ;;
            --prefix=*)
                prefix="${1#*=}"
                ;;
            --target)
                shift
                if [ $# -eq 0 ] || [ -z "${1:-}" ]; then
                    echo "error: --target requires an argument" >&2
                    usage
                    exit 2
                fi
                target="$1"
                ;;
            --target=*)
                target="${1#*=}"
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

    if [ -z "${prefix}" ] || [ -z "${target}" ]; then
        echo "error: --prefix and --target are required" >&2
        usage
        exit 2
    fi

    local wrapper_dir="${prefix}/wrappers"
    local source_path
    source_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/$(basename "${BASH_SOURCE[0]}")"

    mkdir -p "${wrapper_dir}"
    install -m 755 "${source_path}" "${wrapper_dir}/rtems-clang-wrapper"
    printf 'RTEMS_TARGET=%s\n' "${target}" > "${wrapper_dir}/rtems-clang-wrapper.conf"
    ln -sf rtems-clang-wrapper "${wrapper_dir}/clang"
    ln -sf rtems-clang-wrapper "${wrapper_dir}/clang++"
}

load_target() {
    local config="${RTEMS_CLANG_WRAPPER_CONFIG:-${WRAPPER_DIR}/rtems-clang-wrapper.conf}"
    local key
    local value

    if [ ! -r "${config}" ]; then
        echo "error: wrapper configuration not found: ${config}" >&2
        exit 1
    fi

    while IFS='=' read -r key value; do
        case "${key}" in
            RTEMS_TARGET)
                RTEMS_TARGET="${value}"
                ;;
        esac
    done < "${config}"

    if [ -z "${RTEMS_TARGET:-}" ]; then
        echo "error: RTEMS_TARGET is not set in ${config}" >&2
        exit 1
    fi
}

run_wrapper() {
    local wrapper_name
    local real_clang
    local real_gcc

    wrapper_name="$(basename "$0")"
    WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    load_target

    case "${wrapper_name}" in
        clang)
            real_clang="${WRAPPER_DIR}/../bin/clang"
            real_gcc="${WRAPPER_DIR}/../bin/${RTEMS_TARGET}-gcc"
            ;;
        clang++)
            real_clang="${WRAPPER_DIR}/../bin/clang++"
            real_gcc="${WRAPPER_DIR}/../bin/${RTEMS_TARGET}-g++"
            ;;
        *)
            echo "error: wrapper must be invoked as clang or clang++" >&2
            exit 1
            ;;
    esac

    local args=()
    local link=1
    local a
    for a in "$@"; do
        case "${a}" in
            -c|-S|-E)
                link=0
                ;;
        esac
        args+=("${a}")
    done

    if [ "${link}" -eq 0 ]; then
        exec "${real_clang}" "${args[@]}"
    fi

    local filtered=()
    local skip_next=0
    for a in "${args[@]}"; do
        if [ "${skip_next}" -eq 1 ]; then
            skip_next=0
            continue
        fi
        if [[ "${a}" == --target=* ]]; then
            continue
        fi
        if [ "${a}" = "-target" ]; then
            skip_next=1
            continue
        fi
        filtered+=("${a}")
    done

    exec "${real_gcc}" -qrtems "${filtered[@]}"
}

case "${1:-}" in
    --install)
        install_wrappers "$@"
        ;;
    -h|--help)
        usage
        ;;
    *)
        run_wrapper "$@"
        ;;
esac
