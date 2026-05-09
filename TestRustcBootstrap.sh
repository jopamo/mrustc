#!/bin/bash
# Builds rustc with the mrustc stage0 and downloaded stage0
set -e  # Quit script on error
set -u  # Error on unset variables

WORKDIR=${WORKDIR:-rustc_bootstrap}
WORKDIR="${WORKDIR%/}/"

default_jobs() {
    nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1
}

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

RUSTC_TARGET=${RUSTC_TARGET:-$(default_rustc_target)}
RUSTC_VERSION=${*-1.29.0}
MRUSTC_PARLEVEL=${MRUSTC_PARLEVEL:-$(default_jobs)}
BOOTSTRAP_PARLEVEL=${BOOTSTRAP_PARLEVEL:-$(default_jobs)}
LLVM_PARLEVEL=${LLVM_PARLEVEL:-$BOOTSTRAP_PARLEVEL}
COMPARE_WITH_OFFICIAL=${COMPARE_WITH_OFFICIAL:-1}
RUN_RUSTC_SUF=""
if [[ "$RUSTC_VERSION" == "1.29.0" ]]; then
    RUSTC_VERSION_NEXT=1.30.0
elif [[ "$RUSTC_VERSION" == "1.19.0" ]]; then
    RUSTC_VERSION_NEXT=1.20.0
    RUN_RUSTC_SUF=-1.19.0
elif [[ "$RUSTC_VERSION" == "1.39.0" ]]; then
    RUSTC_VERSION_NEXT=1.40.0
    RUN_RUSTC_SUF=-1.39.0
elif [[ "$RUSTC_VERSION" == "1.54.0" ]]; then
    RUSTC_VERSION_NEXT=1.55.0
    RUN_RUSTC_SUF=-1.54.0
elif [[ "$RUSTC_VERSION" == "1.74.0" ]]; then
    RUSTC_VERSION_NEXT=1.75.0
    RUN_RUSTC_SUF=-1.74.0
elif [[ "$RUSTC_VERSION" == "1.90.0" ]]; then
    # 1.91 had a patch release
    RUSTC_VERSION_NEXT=1.91.1
    RUN_RUSTC_SUF=-1.90.0
else
    echo "Unknown rustc version"
fi

apply_rust_patches() {
    python3 scripts/fix_rust_libdir_symlink.py "$1"
}

append_target_bootstrap_config() {
    local cfg_path="$1"
    if [[ "${RUSTC_TARGET}" == *-linux-musl ]]; then
        cat - >> "${cfg_path}" <<EOF
[target.${RUSTC_TARGET}]
crt-static = false
EOF
    fi
}

echo "=== Building stage0 rustc (with libstd)"
make -j"${MRUSTC_PARLEVEL}" -C run_rustc RUSTC_VERSION=${RUSTC_VERSION} PARLEVEL=${MRUSTC_PARLEVEL}

MAKEFLAGS=-j${LLVM_PARLEVEL}
export MAKEFLAGS

PREFIX=${PWD}/run_rustc/output${RUN_RUSTC_SUF}/prefix/

if [ ! -e rustc-${RUSTC_VERSION_NEXT}-src.tar.gz ]; then
    wget https://static.rust-lang.org/dist/rustc-${RUSTC_VERSION_NEXT}-src.tar.gz
fi

echo "--- Working in directory ${WORKDIR}"
echo "=== Cleaning up"
rm -rf ${WORKDIR}build
#
# Build rustc using entirely mrustc-built tools
#
echo "=== Building rustc bootstrap mrustc stage0"
mkdir -p ${WORKDIR}mrustc/
tar -xzf rustc-${RUSTC_VERSION_NEXT}-src.tar.gz -C ${WORKDIR}mrustc/
apply_rust_patches ${WORKDIR}mrustc/rustc-${RUSTC_VERSION_NEXT}-src
cat - > ${WORKDIR}mrustc/rustc-${RUSTC_VERSION_NEXT}-src/config.toml <<EOF
[build]
cargo = "${PREFIX}bin/cargo"
rustc = "${PREFIX}bin/rustc"
jobs = ${BOOTSTRAP_PARLEVEL}
full-bootstrap = true
vendor = true
extended = true
[llvm]
ninja = false
download-ci-llvm = false
EOF
append_target_bootstrap_config ${WORKDIR}mrustc/rustc-${RUSTC_VERSION_NEXT}-src/config.toml
echo "--- Running x.py, see ${WORKDIR}mrustc.log for progress"
(cd ${WORKDIR} && mv mrustc build)
cleanup_mrustc() {
    (cd ${WORKDIR} && mv build mrustc)
}
trap cleanup_mrustc EXIT
rm -rf ${WORKDIR}build/rustc-${RUSTC_VERSION_NEXT}-src/build
(cd ${WORKDIR}build/rustc-${RUSTC_VERSION_NEXT}-src/ && LD_LIBRARY_PATH=${PREFIX}lib/rustlib/${RUSTC_TARGET}/lib ./x.py build --stage 3) > ${WORKDIR}mrustc.log 2>&1
cleanup_mrustc
trap - EXIT
rm -rf ${WORKDIR}mrustc-output
rm -rf ${WORKDIR}output
cp -r ${WORKDIR}mrustc/rustc-${RUSTC_VERSION_NEXT}-src/build/${RUSTC_TARGET}/stage3 ${WORKDIR}output
cp ${WORKDIR}mrustc/rustc-${RUSTC_VERSION_NEXT}-src/build/${RUSTC_TARGET}/stage3-tools-bin/* ${WORKDIR}output/bin/
rm -rf ${WORKDIR}output/lib/rustlib/src ${WORKDIR}output/lib/rustlib/rustc-src
tar --mtime="@0" --sort=name -czf ${WORKDIR}mrustc.tar.gz -C ${WORKDIR} output
mv ${WORKDIR}output ${WORKDIR}mrustc-output

#
# Build rustc by downloading the previous version of rustc (and its matching cargo)
#
if [ "${COMPARE_WITH_OFFICIAL}" != "0" ]; then
echo "=== Building rustc bootstrap downloaded stage0"
mkdir -p ${WORKDIR}official/
tar -xzf rustc-${RUSTC_VERSION_NEXT}-src.tar.gz -C ${WORKDIR}official/
apply_rust_patches ${WORKDIR}official/rustc-${RUSTC_VERSION_NEXT}-src
cat - > ${WORKDIR}official/rustc-${RUSTC_VERSION_NEXT}-src/config.toml <<EOF
[build]
jobs = ${BOOTSTRAP_PARLEVEL}
full-bootstrap = true
vendor = true
extended = true
[llvm]
ninja = false
download-ci-llvm = false
EOF
append_target_bootstrap_config ${WORKDIR}official/rustc-${RUSTC_VERSION_NEXT}-src/config.toml
echo "--- Running x.py, see ${WORKDIR}official.log for progress"
(cd ${WORKDIR} && mv official build)
(cd ${WORKDIR}build/rustc-${RUSTC_VERSION_NEXT}-src/ && ./x.py build --stage 3) > ${WORKDIR}official.log 2>&1
(cd ${WORKDIR} && mv build official)
rm -rf ${WORKDIR}official-output
rm -rf ${WORKDIR}output
cp -r ${WORKDIR}official/rustc-${RUSTC_VERSION_NEXT}-src/build/${RUSTC_TARGET}/stage3 ${WORKDIR}output
cp ${WORKDIR}official/rustc-${RUSTC_VERSION_NEXT}-src/build/${RUSTC_TARGET}/stage3-tools-bin/* ${WORKDIR}output/bin/
rm -rf ${WORKDIR}output/lib/rustlib/src ${WORKDIR}output/lib/rustlib/rustc-src
tar --mtime="@0" --sort=name -czf ${WORKDIR}official.tar.gz -C ${WORKDIR} output
mv ${WORKDIR}output ${WORKDIR}official-output

#
# Compare mrustc-built and official build artifacts
#
diff -qs ${WORKDIR}mrustc.tar.gz ${WORKDIR}official.tar.gz
fi
