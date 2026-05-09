#!/bin/sh
set -eu

is_target() {
    for a  in "$@"
    do
        case "$a" in
        --target|--target*|-vV)
            return 0
            ;;
        esac
    done
    return 1
}

has_target_feature_flag() {
    prev_was_c=0
    for a in "$@"
    do
        if [ "$prev_was_c" = 1 ]; then
            case "$a" in
            target-feature=*)
                return 0
                ;;
            esac
            prev_was_c=0
        fi
        case "$a" in
        -C)
            prev_was_c=1
            ;;
        -Ctarget-feature=*)
            return 0
            ;;
        esac
    done
    return 1
}

if is_target "$@"; then
    #echo "  [REAL]" "$@" >&2
    ${PROXY_RUSTC} "$@"
else
    #echo "  [BOOTSTRAP]" "$@" >&2
    case "${CFG_COMPILER_HOST_TRIPLE:-}" in
    *-linux-musl)
        if has_target_feature_flag "$@"; then
            ${PROXY_MRUSTC} "$@"
        else
            ${PROXY_MRUSTC} -C target-feature=-crt-static "$@"
        fi
        ;;
    *)
        ${PROXY_MRUSTC} "$@"
        ;;
    esac
fi
