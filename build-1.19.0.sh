#!/bin/bash
set -e
default_jobs() {
	nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1
}
export PARLEVEL=${PARLEVEL:-$(default_jobs)}
export RUSTC_VERSION=1.19.0 MRUSTC_TARGET_VER=1.19 OUTDIR_SUF=-1.19.0
make -j"${PARLEVEL}"
make -j"${PARLEVEL}" -f minicargo.mk RUSTCSRC
make -j"${PARLEVEL}" -f minicargo.mk LIBS
make -j"${PARLEVEL}" -f minicargo.mk test
make -j"${PARLEVEL}" -f minicargo.mk output-1.19.0/stdtest/rustc_data_structures-test_out.txt
make -j"${PARLEVEL}" -f minicargo.mk output-1.19.0/rustc
make -j"${PARLEVEL}" -f minicargo.mk output-1.19.0/cargo
./output-1.19.0/cargo --version
