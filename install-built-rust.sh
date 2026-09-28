#!/bin/bash
set -euo pipefail

usage() {
	cat <<EOF
usage: $0 [version]

Install a completed output-<version> Rust toolchain into /opt/rust.
With no version, the newest completed build is selected.

Examples:
  $0
  $0 1.96.1
  PREFIX=/tmp/rust $0 1.95.0
EOF
}

if [ "$#" -gt 1 ]; then
	usage >&2
	exit 1
fi
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
	usage
	exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PREFIX="${PREFIX:-/opt/rust}"

case "${PREFIX}" in
	/*) ;;
	*)
		echo "install prefix must be an absolute path: ${PREFIX}" >&2
		exit 1
		;;
esac
if [ "${PREFIX}" = "/" ]; then
	echo "refusing to install over /" >&2
	exit 1
fi
PREFIX="${PREFIX%/}"

is_complete_toolchain() {
	local output="$1"
	[ -x "${output}/bin/rustc" ] &&
		[ -x "${output}/bin/cargo" ] &&
		[ -d "${output}/lib/rustlib" ]
}

find_newest_version() {
	local output version
	local -a versions=()

	shopt -s nullglob
	for output in "${ROOT}"/output-*; do
		[ -d "${output}" ] || continue
		version="${output##*/output-}"
		[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
		is_complete_toolchain "${output}" || continue
		versions+=("${version}")
	done
	shopt -u nullglob

	if [ "${#versions[@]}" -eq 0 ]; then
		echo "no completed output-<version> toolchains found in ${ROOT}" >&2
		return 1
	fi

	printf '%s\n' "${versions[@]}" | sort -V | tail -n 1
}

if [ "$#" -eq 1 ]; then
	VERSION="${1#v}"
	if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		echo "invalid Rust version: $1" >&2
		exit 1
	fi
else
	VERSION="$(find_newest_version)"
fi

SOURCE="${ROOT}/output-${VERSION}"
if ! is_complete_toolchain "${SOURCE}"; then
	echo "output-${VERSION} is missing bin/rustc, bin/cargo, or lib/rustlib" >&2
	exit 1
fi

source_rustc_version="$("${SOURCE}/bin/rustc" --version)"
case "${source_rustc_version}" in
	"rustc ${VERSION} "*) ;;
	*)
		echo "output-${VERSION} reports an unexpected version: ${source_rustc_version}" >&2
		exit 1
		;;
esac

PARENT="$(dirname "${PREFIX}")"
NAME="$(basename "${PREFIX}")"
if ! mkdir -p "${PARENT}"; then
	echo "cannot create install parent ${PARENT}; run as a user with permission (usually root)" >&2
	exit 1
fi

STAGING=""
BACKUP=""
OLD_MOVED=0
COMMITTED=0

cleanup() {
	local status=$?
	trap - EXIT HUP INT TERM

	if [ "${COMMITTED}" -eq 0 ] && [ "${OLD_MOVED}" -eq 1 ]; then
		if [ ! -e "${PREFIX}" ] && [ ! -L "${PREFIX}" ] &&
			{ [ -e "${BACKUP}" ] || [ -L "${BACKUP}" ]; }; then
			if ! mv -- "${BACKUP}" "${PREFIX}"; then
				echo "error: failed to restore previous installation from ${BACKUP}" >&2
			else
				BACKUP=""
			fi
		fi
	fi

	if [ -n "${STAGING}" ] && [ -d "${STAGING}" ]; then
		rm -rf -- "${STAGING}"
	fi
	exit "${status}"
}
trap cleanup EXIT HUP INT TERM

STAGING="$(mktemp -d "${PARENT}/.${NAME}.install.XXXXXX")"
chmod 755 "${STAGING}"

echo "Staging Rust ${VERSION} from ${SOURCE}"
cp -a --no-preserve=ownership "${SOURCE}/." "${STAGING}/"

# Validate the private candidate before replacing the active installation.
staged_rustc_version="$(env -u LD_LIBRARY_PATH "${STAGING}/bin/rustc" --version)"
case "${staged_rustc_version}" in
	"rustc ${VERSION} "*) ;;
	*)
		echo "staged rustc reports an unexpected version: ${staged_rustc_version}" >&2
		exit 1
		;;
esac
env -u LD_LIBRARY_PATH "${STAGING}/bin/cargo" --version >/dev/null

if [ -e "${PREFIX}" ] || [ -L "${PREFIX}" ]; then
	BACKUP="$(mktemp -d "${PARENT}/.${NAME}.backup.XXXXXX")"
	rmdir "${BACKUP}"
	mv -- "${PREFIX}" "${BACKUP}"
	OLD_MOVED=1
fi

mv -- "${STAGING}" "${PREFIX}"
STAGING=""
COMMITTED=1
trap - EXIT HUP INT TERM

if [ -n "${BACKUP}" ]; then
	rm -rf -- "${BACKUP}"
fi

echo "Installed Rust ${VERSION} in ${PREFIX}"
"${PREFIX}/bin/rustc" --version
"${PREFIX}/bin/cargo" --version
