#!/usr/bin/env bash
# /root/installK8s/04_network_forwarding_check.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
. "$SCRIPT_DIR/04_network_forwarding_config"

error=-1
return_code=$error
found_any_file=0

for key in "${keys[@]}"; do
    regex="^${key//./\\.}[[:space:]]*=[[:space:]]*1([[:space:]]|\$)"
    matches=$(grep -HnE "$regex" /etc/sysctl.d/* 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
        ((found_any_file++)) 
        printf '%s\n' "$matches"
    else
        file_match=$(grep -HnE "^${key//./\\.}[[:space:]]*=" /etc/sysctl.d/* 2>/dev/null || true)
        if [[ -n "$file_match" ]]; then
            # extract just filename(s)
            while IFS= read -r line; do
                filename="${line%%:*}"
                printf 'VALUE_NOT_1: %s: %s\n' "$filename" "$key"
            done <<< "$file_match"
        else
            printf 'MISSING: %s\n' "$key"
        fi
        return_code=1
    fi
done