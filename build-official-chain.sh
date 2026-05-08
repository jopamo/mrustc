#!/bin/bash
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
	echo "usage: $0 <from-version> [to-version|stable]"
	exit 1
fi

FROM_VERSION="$1"
TO_VERSION="${2:-next}"

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
		*) next_release "$1" ;;
	esac
}

version_le() {
	[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]
}

resolve_stable() {
	python3 - <<'PY'
import re
import urllib.request

text = urllib.request.urlopen("https://static.rust-lang.org/dist/channel-rust-stable.toml", timeout=30).read().decode("utf-8", "replace")
match = re.search(r'/rust-([0-9.]+)-x86_64-unknown-linux-gnu\.tar\.gz', text)
if not match:
    raise SystemExit("unable to resolve stable rust version")
print(match.group(1))
PY
}

if [ "${TO_VERSION}" = "stable" ]; then
	TO_VERSION="$(resolve_stable)"
fi
if [ "${TO_VERSION}" = "next" ]; then
	TO_VERSION="$(next_bootstrap_release "${FROM_VERSION}")"
fi

if [ "${FROM_VERSION}" = "${TO_VERSION}" ]; then
	echo "already at ${TO_VERSION}"
	exit 0
fi

if ! version_le "${FROM_VERSION}" "${TO_VERSION}"; then
	echo "target ${TO_VERSION} is older than ${FROM_VERSION}"
	exit 1
fi

current="${FROM_VERSION}"
while [ "${current}" != "${TO_VERSION}" ]; do
	next="$(next_bootstrap_release "${current}")"
	if ! version_le "${next}" "${TO_VERSION}"; then
		echo "cannot infer a patch-only hop from ${current} to ${TO_VERSION}; use build-official-step.sh directly"
		exit 1
	fi
	echo "=== ${current} -> ${next}"
	"./build-official-step.sh" "${current}" "${next}"
	current="${next}"
done
