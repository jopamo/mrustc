#!/bin/bash
set -e
# Default to using deferred codegen. It reduces peak memory usage, but may cause link errors
# due to race conditions
export MINICARGO_DEFER_CODEGEN=${MINICARGO_DEFER_CODEGEN:-1}

default_jobs() {
	nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1
}
export PARLEVEL=${PARLEVEL:-$(default_jobs)}
export RUSTC_VERSION=1.90.0 MRUSTC_TARGET_VER=1.90 OUTDIR_SUF=-1.90.0
# Enables use of ccache in mrustc if it's available (i.e. ccache is on PATH)
command -v ccache >/dev/null && export MRUSTC_CCACHE=1
make -j"${PARLEVEL}"
make -j"${PARLEVEL}" RUSTCSRC
make -j"${PARLEVEL}" -f minicargo.mk LIBS "$@"
make -j"${PARLEVEL}" test "$@"
make -j"${PARLEVEL}" local_tests "$@"

OUTDIR=output-1.90.0
if [[ "x$MRUSTC_TARGET" != "x" ]]; then
	OUTDIR=$OUTDIR-$MRUSTC_TARGET
fi

RUSTC_INSTALL_BINDIR=bin make -j"${PARLEVEL}" -f minicargo.mk $OUTDIR/rustc "$@"
set -x
./$OUTDIR/rustc --version
./$OUTDIR/rustc samples/no_core-1_90.rs
set +x

LIBGIT2_SYS_USE_PKG_CONFIG=1 make -j"${PARLEVEL}" -f minicargo.mk $OUTDIR/cargo "$@"
set -x
./$OUTDIR/cargo --version
