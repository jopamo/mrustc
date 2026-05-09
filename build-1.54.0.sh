#!/bin/bash
set -e
default_jobs() {
	nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1
}
export PARLEVEL=${PARLEVEL:-$(default_jobs)}
export RUSTC_VERSION=1.54.0 MRUSTC_TARGET_VER=1.54 OUTDIR_SUF=-1.54.0
make -j"${PARLEVEL}"
make -j"${PARLEVEL}" RUSTCSRC
make -j"${PARLEVEL}" -f minicargo.mk LIBS "$@"
make -j"${PARLEVEL}" test "$@"
make -j"${PARLEVEL}" local_tests "$@"
## Build just rustc-driver BEFORE building llvm
#RUSTC_INSTALL_BINDIR=bin make -f minicargo.mk output-1.54.0/rustc-build/librustc_driver.rlib
RUSTC_INSTALL_BINDIR=bin make -j"${PARLEVEL}" -f minicargo.mk output-1.54.0/rustc "$@"
./output-1.54.0/rustc --version

LIBGIT2_SYS_USE_PKG_CONFIG=1 make -j"${PARLEVEL}" -f minicargo.mk output-1.54.0/cargo "$@"
./output-1.54.0/cargo --version
