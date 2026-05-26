#!/bin/bash
set -e
# Default to using deferred codegen. It reduces peak memory usage, but may cause link errors
# due to race conditions
export MINICARGO_DEFER_CODEGEN=${MINICARGO_DEFER_CODEGEN:-1}

default_jobs() {
	nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1
}
pick_default_tool() {
	local var="$1"
	shift
	if [[ -n "${!var:-}" ]]; then
		export "${var}"
		return 0
	fi
	local tool
	for tool in "$@"; do
		if command -v "$tool" >/dev/null 2>&1; then
			printf -v "${var}" '%s' "$(command -v "$tool")"
			export "${var}"
			return 0
		fi
	done
}
make_lld_wrapper() {
	local var="$1"
	local compiler="${!var:-}"
	local wrapper_dir=".obj/tool-wrappers"
	local wrapper="$wrapper_dir/${var,,}-with-lld"
	mkdir -p "${wrapper_dir}"
	{
		echo '#!/bin/sh'
		echo 'set -eu'
		printf 'compiler=%q\n' "${compiler}"
		echo 'link=1'
		echo 'for arg in "$@"; do'
		echo '	case "$arg" in'
		echo '		-c|-E|-S) link=0 ;;'
		echo '	esac'
		echo 'done'
		echo 'if [ "$link" -eq 1 ]; then'
		echo '	exec "$compiler" -fuse-ld=lld "$@"'
		echo 'else'
		echo '	exec "$compiler" "$@"'
		echo 'fi'
	} > "${wrapper}"
	chmod +x "${wrapper}"
	printf -v "${var}" '%s' "${PWD}/${wrapper}"
	export "${var}"
}
export PARLEVEL=${PARLEVEL:-$(default_jobs)}
export RUSTC_VERSION=1.90.0 MRUSTC_TARGET_VER=1.90 OUTDIR_SUF=-1.90.0
pick_default_tool CC cc clang
pick_default_tool CXX c++ clang++
pick_default_tool AR ar llvm-ar
pick_default_tool RANLIB ranlib llvm-ranlib
pick_default_tool NM nm llvm-nm
pick_default_tool OBJCOPY objcopy llvm-objcopy
pick_default_tool STRIP strip llvm-strip
if [[ -z "${LD:-}" ]] && command -v ld.lld >/dev/null 2>&1; then
	export LD=ld.lld
fi
if ! command -v ld >/dev/null 2>&1 && command -v ld.lld >/dev/null 2>&1; then
	make_lld_wrapper CC
	make_lld_wrapper CXX
fi
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
./$OUTDIR/rustc samples/no_core-1_90.rs -C target-feature=-crt-static
set +x

LIBGIT2_SYS_USE_PKG_CONFIG=1 make -j"${PARLEVEL}" -f minicargo.mk $OUTDIR/cargo "$@"
set -x
./$OUTDIR/cargo --version
