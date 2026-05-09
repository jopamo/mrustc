#!/bin/bash
set -e
default_jobs() {
	nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1
}
export PARLEVEL=${PARLEVEL:-$(default_jobs)}
export RUSTC_VERSION=1.74.0 MRUSTC_TARGET_VER=1.74 OUTDIR_SUF=-1.74.0
# Enables use of ccache in mrustc if it's available (i.e. ccache is on PATH)
command -v ccache >/dev/null && export MRUSTC_CCACHE=1
make -j"${PARLEVEL}"
make -j"${PARLEVEL}" RUSTCSRC
make -j"${PARLEVEL}" -f minicargo.mk LIBS "$@"
make -j"${PARLEVEL}" test "$@"
make -j"${PARLEVEL}" local_tests "$@"

OUTDIR=output-1.74.0
if [[ "x$MRUSTC_TARGET" != "x" ]]; then
	OUTDIR=$OUTDIR-$MRUSTC_TARGET
fi

RUSTC_INSTALL_BINDIR=bin make -j"${PARLEVEL}" -f minicargo.mk $OUTDIR/rustc "$@"
./$OUTDIR/rustc --version

LIBGIT2_SYS_USE_PKG_CONFIG=1 make -j"${PARLEVEL}" -f minicargo.mk $OUTDIR/cargo "$@"
./$OUTDIR/cargo --version

./$OUTDIR/rustc samples/no_core.rs
#./output-1.74.0/rustc samples/1.rs
