#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# if check passes, nothing to do
if output="$("$DIR/02_swap_disable_check.sh" || true)"; then
    SWAP_TEMP_ON=false
    SWAP_PERM_ON=false

    if printf '%s' "$output" | grep -q 'SWAP_TEMP=on'; then
        SWAP_TEMP_ON=true
    fi
    if printf '%s' "$output" | grep -q 'SWAP_PERM=on'; then
        SWAP_PERM_ON=true
    fi

    # nothing to do
    if ! $SWAP_TEMP_ON && ! $SWAP_PERM_ON; then
        exit 0
    fi

    # perform requested actions
    if $SWAP_TEMP_ON; then
        swapoff -a
    fi
    if $SWAP_PERM_ON; then
        sed -i.bak -r '/^[[:space:]]*#/!{s/^([^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+swap\b.*)$/#\1/}' /etc/fstab
    fi

    # verify
    if "$DIR/02_swap_disable_check.sh"; then
        exit 0
    else
        echo "Failed to disable swap" >&2
        exit 1
    fi
fi
