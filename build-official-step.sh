#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
	echo "usage: $0 <from-version> <to-version>"
	exit 1
fi

FROM_VERSION="$1"
TO_VERSION="$2"

PARLEVEL="${PARLEVEL:-1}"
LLVM_PARLEVEL="${LLVM_PARLEVEL:-$PARLEVEL}"
COMPARE_WITH_OFFICIAL="${COMPARE_WITH_OFFICIAL:-0}"
RUSTC_TARGET="${RUSTC_TARGET:-x86_64-unknown-linux-gnu}"
WORKDIR="${WORKDIR:-rustc_bootstrap-${TO_VERSION}/}"
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

prepare_tree() {
	local mode="$1"
	rm -rf "${WORKDIR}${mode}"
	mkdir -p "${WORKDIR}${mode}/"
	tar -xzf "${SRC_TARBALL}" -C "${WORKDIR}${mode}/"
}

write_local_config() {
	cat > "${WORKDIR}local/rustc-${TO_VERSION}-src/config.toml" <<EOF
[build]
cargo = "${STAGE0_PREFIX}/bin/cargo"
rustc = "${STAGE0_PREFIX}/bin/rustc"
jobs = ${PARLEVEL}
full-bootstrap = true
vendor = true
extended = true
[llvm]
ninja = false
download-ci-llvm = false
EOF
}

write_official_config() {
	cat > "${WORKDIR}official/rustc-${TO_VERSION}-src/config.toml" <<EOF
[build]
jobs = ${PARLEVEL}
full-bootstrap = true
vendor = true
extended = true
[llvm]
ninja = false
download-ci-llvm = false
EOF
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
