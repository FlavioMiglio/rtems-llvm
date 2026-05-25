#!/bin/bash
set -euo pipefail

usage() {
	echo "Usage: $0 --prefix <path> --gcc-bset <bset>" >&2
	echo "Example: $0 --prefix \"$HOME/dev/COT-RSB/7\" --gcc-bset 7/rtems-aarch64" >&2
}

prefix=""
gcc_bset=""
llvm_bset="7/rtems-llvm"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--prefix)
			prefix="$2"
			shift 2
			;;
		--gcc-bset)
			gcc_bset="$2"
			shift 2
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			usage
			exit 1
			;;
	esac
done

if [[ -z "$prefix" || -z "$gcc_bset" ]]; then
	usage
	exit 1
fi

cd src/rtems-rsb/rtems

# First, we build the gcc toolchain, for the libraries and runtimes
../source-builder/sb-set-builder --prefix="$prefix" "$gcc_bset"

# Some files get overwritten by the second toolchain install and write permissions are needed
chmod -R u+w "$prefix"

# Then we build the rtems-llvm toolchain
../source-builder/sb-set-builder --prefix="$prefix" "$llvm_bset"

