#!/bin/bash
set -euo pipefail

if [ "$#" -ne 0 ]; then
	echo "usage: $0"
	exit 1
fi

export PARLEVEL=${PARLEVEL:-1}
export LLVM_PARLEVEL=${LLVM_PARLEVEL:-${PARLEVEL}}
export COMPARE_WITH_OFFICIAL=${COMPARE_WITH_OFFICIAL:-0}
export WORKDIR=${WORKDIR:-rustc_bootstrap-1.91.1/}

./TestRustcBootstrap.sh 1.90.0

OUTDIR=output-1.91.1
rm -rf "${OUTDIR}"
cp -a "${WORKDIR%/}/mrustc-output" "${OUTDIR}"

set -x
./"${OUTDIR}"/bin/rustc --version
./"${OUTDIR}"/bin/cargo --version
