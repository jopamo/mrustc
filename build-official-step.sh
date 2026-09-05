#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
	echo "usage: $0 <from-version> <to-version>"
	exit 1
fi

FROM_VERSION="$1"
TO_VERSION="$2"

default_jobs() {
	nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1
}

next_release() {
	local major minor patch
	IFS=. read -r major minor patch <<<"$1"
	printf '%s.%s.0\n' "$major" "$((minor + 1))"
}

next_bootstrap_release() {
	case "$1" in
		1.91.1) printf '1.92.0\n' ;;
		1.92.0) printf '1.93.1\n' ;;
		1.93.1) printf '1.94.1\n' ;;
		1.94.1) printf '1.95.0\n' ;;
		1.95.0) printf '1.96.1\n' ;;
		1.96.1) printf '1.97.1\n' ;;
		1.97.1) printf '1.98.1\n' ;;
		*) next_release "$1" ;;
	esac
}

EXPECTED_TO_VERSION="$(next_bootstrap_release "${FROM_VERSION}")"
if [ "${TO_VERSION}" != "${EXPECTED_TO_VERSION}" ]; then
	echo "build-official-step.sh only supports one bootstrap hop: ${FROM_VERSION} -> ${EXPECTED_TO_VERSION}" >&2
	echo "use ./build-official-chain.sh ${FROM_VERSION} ${TO_VERSION}" >&2
	exit 1
fi

default_rustc_target() {
	local host_gnu_type
	host_gnu_type="$(${CC:-cc} -dumpmachine 2>/dev/null || echo unknown)"
	case "${host_gnu_type}" in
		x86_64-*-linux-musl) echo x86_64-unknown-linux-musl ;;
		x86_64-*-linux-gnu*) echo x86_64-unknown-linux-gnu ;;
		aarch64-*-linux-musl) echo aarch64-unknown-linux-musl ;;
		aarch64-*-linux-gnu*) echo aarch64-unknown-linux-gnu ;;
		arm-*-linux-musl|armv[0-9]*-*-linux-musl) echo arm-unknown-linux-musl ;;
		arm-*-linux-gnu*|armv[0-9]*-*-linux-gnu*) echo arm-unknown-linux-gnu ;;
		i?86-*-linux-musl) echo i586-unknown-linux-musl ;;
		i?86-*-linux-gnu*) echo i586-unknown-linux-gnu ;;
		m68k-*-linux-musl) echo m68k-unknown-linux-musl ;;
		m68k-*-linux-gnu*) echo m68k-unknown-linux-gnu ;;
		powerpc64le-*-linux-musl) echo powerpc64le-unknown-linux-musl ;;
		powerpc64le-*-linux-gnu*) echo powerpc64le-unknown-linux-gnu ;;
		powerpc64-*-linux-musl) echo powerpc64-unknown-linux-musl ;;
		powerpc64-*-linux-gnu*) echo powerpc64-unknown-linux-gnu ;;
		riscv64-*-linux-musl) echo riscv64-unknown-linux-musl ;;
		riscv64-*-linux-gnu*) echo riscv64-unknown-linux-gnu ;;
		*) echo x86_64-unknown-linux-gnu ;;
	esac
}

default_llvm_targets() {
	local arch="${RUSTC_TARGET%%-*}"
	case "${arch}" in
		x86_64|i?86) echo "AArch64;X86" ;;
		aarch64) echo AArch64 ;;
		arm|armv*) echo ARM ;;
		riscv64*) echo RISCV ;;
		powerpc*|ppc*) echo PowerPC ;;
		mips*|mips64*) echo Mips ;;
		loongarch64) echo LoongArch ;;
		s390x) echo SystemZ ;;
		sparc*|sparcv9) echo Sparc ;;
		wasm32|wasm64) echo WebAssembly ;;
		bpfel|bpfeb) echo BPF ;;
		hexagon) echo Hexagon ;;
		m68k|avr|csky) echo "" ;;
		*) echo "AArch64;X86" ;;
	esac
}

default_llvm_experimental_targets() {
	local arch="${RUSTC_TARGET%%-*}"
	case "${arch}" in
		m68k) echo M68k ;;
		avr) echo AVR ;;
		csky) echo CSKY ;;
		*) echo "" ;;
	esac
}

write_strip_target_wrapper() {
	local wrapper_path="$1"
	local compiler_path="$2"
	cat > "${wrapper_path}" <<EOF
#!/bin/sh
MRUSTC_STRIP_TARGET=${RUSTC_TARGET@Q} \
MRUSTC_WRAPPED_COMPILER=${compiler_path@Q} \
exec python3 - "\$@" <<'PY'
import os
import sys

target = os.environ["MRUSTC_STRIP_TARGET"]
compiler = os.environ["MRUSTC_WRAPPED_COMPILER"]
args = [arg for arg in sys.argv[1:] if arg != "--target=" + target]
os.execvp(compiler, [compiler] + args)
PY
EOF
	chmod +x "${wrapper_path}"
}

append_target_bootstrap_config() {
	local cfg_path="$1"
	local host_gnu_type host_cc host_cxx wrapper_dir target_cc target_cxx target_linker
	cat - >> "${cfg_path}" <<EOF
[target.${RUSTC_TARGET}]
EOF
	if [[ "${RUSTC_TARGET}" == *-linux-musl ]]; then
		host_gnu_type="$(${CC:-cc} -dumpmachine 2>/dev/null || true)"
		if [ -n "${host_gnu_type}" ]; then
			host_cc="$(command -v "${host_gnu_type}-gcc" 2>/dev/null || true)"
			host_cxx="$(command -v "${host_gnu_type}-g++" 2>/dev/null || command -v "${host_gnu_type}-c++" 2>/dev/null || true)"
			if [ -n "${host_cc}" ] && [ -n "${host_cxx}" ]; then
				if [ "${host_gnu_type}" = "${RUSTC_TARGET}" ]; then
					target_cc="${host_cc}"
					target_cxx="${host_cxx}"
					target_linker="${host_cc}"
				else
					wrapper_dir="${PWD}/${WORKDIR}toolchain-bin"
					mkdir -p "${wrapper_dir}"
					target_cc="${wrapper_dir}/host-musl-cc"
					target_cxx="${wrapper_dir}/host-musl-cxx"
					target_linker="${target_cc}"
					write_strip_target_wrapper "${target_cc}" "${host_cc}"
					write_strip_target_wrapper "${target_cxx}" "${host_cxx}"
				fi
				cat - >> "${cfg_path}" <<EOF
cc = "${target_cc}"
cxx = "${target_cxx}"
linker = "${target_linker}"
llvm-libunwind = "in-tree"
EOF
			fi
		fi
		cat - >> "${cfg_path}" <<EOF
crt-static = false
EOF
	fi
}

append_llvm_bootstrap_config() {
	local cfg_path="$1"
	if [[ "${RUSTC_TARGET}" == *-linux-musl ]]; then
		local host_cc_target
		host_cc_target="$(${CC:-cc} -dumpmachine 2>/dev/null || true)"
		cat - >> "${cfg_path}" <<EOF
use-libcxx = true
EOF
		if [ -n "${host_cc_target}" ] && [ "${host_cc_target}" != "${RUSTC_TARGET}" ]; then
			cat - >> "${cfg_path}" <<EOF
cflags = "--target=${host_cc_target}"
cxxflags = "--target=${host_cc_target}"
EOF
		fi
	fi
	if [ -n "${LLVM_TARGETS:-}" ]; then
		cat - >> "${cfg_path}" <<EOF
targets = "${LLVM_TARGETS}"
EOF
	fi
	if [ "${LLVM_EXPERIMENTAL_TARGETS+x}" = x ]; then
		cat - >> "${cfg_path}" <<EOF
experimental-targets = "${LLVM_EXPERIMENTAL_TARGETS}"
EOF
	fi
}

BOOTSTRAP_PARLEVEL="${BOOTSTRAP_PARLEVEL:-$(default_jobs)}"
LLVM_PARLEVEL="${LLVM_PARLEVEL:-$BOOTSTRAP_PARLEVEL}"
COMPARE_WITH_OFFICIAL="${COMPARE_WITH_OFFICIAL:-0}"
RUSTC_TARGET="${RUSTC_TARGET:-$(default_rustc_target)}"
if [ "${LLVM_TARGETS+x}" != x ]; then
	LLVM_TARGETS="$(default_llvm_targets)"
fi
if [ "${LLVM_EXPERIMENTAL_TARGETS+x}" != x ]; then
	LLVM_EXPERIMENTAL_TARGETS="$(default_llvm_experimental_targets)"
fi
WORKDIR="${WORKDIR:-rustc_bootstrap-${TO_VERSION}}"
WORKDIR="${WORKDIR%/}/"
OUTDIR="output-${TO_VERSION}"
SRC_TARBALL="rustc-${TO_VERSION}-src.tar.gz"
SRC_URL="https://static.rust-lang.org/dist/${SRC_TARBALL}"
STAGE0_PREFIX="${STAGE0_PREFIX:-${PWD}/output-${FROM_VERSION}}"

if [ ! -x "${STAGE0_PREFIX}/bin/rustc" ]; then
	echo "missing stage0 rustc: ${STAGE0_PREFIX}/bin/rustc"
	exit 1
fi
if [ ! -x "${STAGE0_PREFIX}/bin/cargo" ]; then
	echo "missing stage0 cargo: ${STAGE0_PREFIX}/bin/cargo"
	exit 1
fi

MAKEFLAGS="-j${LLVM_PARLEVEL}"
export MAKEFLAGS

STAGE0_PREFIX="$(cd "${STAGE0_PREFIX}" && pwd -P)"
STAGE0_LD_LIBRARY_PATH="${STAGE0_PREFIX}/lib:${STAGE0_PREFIX}/lib/rustlib/${RUSTC_TARGET}/lib"

download_tarball() {
	if [ -e "${SRC_TARBALL}" ]; then
		return 0
	fi
	echo "--- Downloading ${SRC_TARBALL}"
	curl -fL --retry 3 -o "${SRC_TARBALL}" "${SRC_URL}"
}

apply_rust_patches() {
	local rust_src="$1"
	python3 scripts/fix_rust_libdir_symlink.py "${rust_src}"
	python3 - "${rust_src}" <<'PY'
import sys
import json
import hashlib
from pathlib import Path

root = Path(sys.argv[1])
path = root / "vendor" / "openssl-sys-0.9.109" / "build" / "main.rs"
if not path.exists():
    raise SystemExit(0)

text = path.read_text()

if "(4, 2, 0) => ('4', '2', '0')" not in text:
    anchor = """            (4, 1, 0) => ('4', '1', '0'),
            (4, 1, _) => ('4', '1', 'x'),
            _ => version_error(),"""
    replacement = """            (4, 1, 0) => ('4', '1', '0'),
            (4, 1, _) => ('4', '1', 'x'),
            (4, 2, 0) => ('4', '2', '0'),
            (4, 2, _) => ('4', '2', 'x'),
            (4, 3, 0) => ('4', '3', '0'),
            (4, 3, _) => ('4', '3', 'x'),
            _ => version_error(),"""
    if anchor not in text:
        raise SystemExit(f"unexpected openssl-sys source layout: {path}")
    text = text.replace(anchor, replacement, 1)

text = text.replace("through 4.1.x", "through 4.3.x")
path.write_text(text)

checksum_path = path.parent.parent / ".cargo-checksum.json"
if checksum_path.exists():
    data = json.loads(checksum_path.read_text())
    data.setdefault("files", {})["build/main.rs"] = hashlib.sha256(path.read_bytes()).hexdigest()
    checksum_path.write_text(json.dumps(data, sort_keys=True))
PY
}

prepare_tree() {
	local mode="$1"
	rm -rf "${WORKDIR}${mode}"
	mkdir -p "${WORKDIR}${mode}/"
	tar -xzf "${SRC_TARBALL}" -C "${WORKDIR}${mode}/"
	apply_rust_patches "${WORKDIR}${mode}/rustc-${TO_VERSION}-src"
}

write_local_config() {
	cat > "${WORKDIR}local/rustc-${TO_VERSION}-src/config.toml" <<EOF
[build]
cargo = "${STAGE0_PREFIX}/bin/cargo"
rustc = "${STAGE0_PREFIX}/bin/rustc"
jobs = ${BOOTSTRAP_PARLEVEL}
full-bootstrap = true
vendor = true
extended = true
[llvm]
ninja = false
download-ci-llvm = false
EOF
	append_llvm_bootstrap_config "${WORKDIR}local/rustc-${TO_VERSION}-src/config.toml"
	append_target_bootstrap_config "${WORKDIR}local/rustc-${TO_VERSION}-src/config.toml"
}

write_official_config() {
cat > "${WORKDIR}official/rustc-${TO_VERSION}-src/config.toml" <<EOF
[build]
jobs = ${BOOTSTRAP_PARLEVEL}
full-bootstrap = true
vendor = true
extended = true
[llvm]
ninja = false
download-ci-llvm = false
EOF
	append_llvm_bootstrap_config "${WORKDIR}official/rustc-${TO_VERSION}-src/config.toml"
	append_target_bootstrap_config "${WORKDIR}official/rustc-${TO_VERSION}-src/config.toml"
}

package_stage3() {
	local mode="$1"
	local target_out="$2"
	rm -rf "${WORKDIR}output"
	cp -r "${WORKDIR}${mode}/rustc-${TO_VERSION}-src/build/${RUSTC_TARGET}/stage3" "${WORKDIR}output"
	cp "${WORKDIR}${mode}/rustc-${TO_VERSION}-src/build/${RUSTC_TARGET}/stage3-tools-bin/"* "${WORKDIR}output/bin/"
	rm -rf "${WORKDIR}output/lib/rustlib/src" "${WORKDIR}output/lib/rustlib/rustc-src"
	rm -rf "${target_out}"
	mv "${WORKDIR}output" "${target_out}"
}

archive_output() {
	local source_dir="$1"
	local archive="$2"
	tar --mtime="@0" --sort=name -czf "${archive}" -C "${source_dir%/*}" "${source_dir##*/}"
}

download_tarball

echo "--- Working in directory ${WORKDIR}"
echo "=== Cleaning up"
rm -rf "${WORKDIR}build"

echo "=== Building rustc bootstrap from local stage0 ${FROM_VERSION}"
prepare_tree local
write_local_config
( cd "${WORKDIR}" && mv local build )
cleanup_local() {
	if [ -d "${WORKDIR}build" ]; then
		( cd "${WORKDIR}" && mv build local )
	fi
}
trap cleanup_local EXIT
rm -rf "${WORKDIR}build/rustc-${TO_VERSION}-src/build"
echo "--- Running x.py, see ${WORKDIR}local.log for progress"
( cd "${WORKDIR}build/rustc-${TO_VERSION}-src/" && LD_LIBRARY_PATH="${STAGE0_LD_LIBRARY_PATH}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" ./x.py build --stage 3 ) > "${WORKDIR}local.log" 2>&1
cleanup_local
trap - EXIT
package_stage3 local "${WORKDIR}local-output"
archive_output "${WORKDIR}local-output" "${WORKDIR}local.tar.gz"
rm -rf "${OUTDIR}"
cp -a "${WORKDIR}local-output" "${OUTDIR}"

if [ "${COMPARE_WITH_OFFICIAL}" != "0" ]; then
	echo "=== Building rustc bootstrap downloaded stage0"
	prepare_tree official
	write_official_config
	( cd "${WORKDIR}" && mv official build )
	cleanup_official() {
		if [ -d "${WORKDIR}build" ]; then
			( cd "${WORKDIR}" && mv build official )
		fi
	}
	trap cleanup_official EXIT
	rm -rf "${WORKDIR}build/rustc-${TO_VERSION}-src/build"
	echo "--- Running x.py, see ${WORKDIR}official.log for progress"
	( cd "${WORKDIR}build/rustc-${TO_VERSION}-src/" && ./x.py build --stage 3 ) > "${WORKDIR}official.log" 2>&1
	cleanup_official
	trap - EXIT
	package_stage3 official "${WORKDIR}official-output"
	archive_output "${WORKDIR}official-output" "${WORKDIR}official.tar.gz"
	diff -qs "${WORKDIR}local.tar.gz" "${WORKDIR}official.tar.gz"
fi

set -x
"./${OUTDIR}/bin/rustc" --version
"./${OUTDIR}/bin/cargo" --version
