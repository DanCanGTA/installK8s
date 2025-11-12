#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
CHECK="$SCRIPT_DIR/04_network_forwarding_check.sh"
OUT="/etc/sysctl.d/kubernetes.conf"

. "$SCRIPT_DIR/04_network_forwarding_config"

if [ ! -f "$CHECK" ]; then
    echo "Check script not found: $CHECK" >&2
    exit 2
fi

match_count=0
keys_missing=()

while IFS= read -r line; do
    # Handle MISSING
    if [[ "$line" =~ ^MISSING:\ (.*)$ ]]; then
        keys_missing+=("${BASH_REMATCH[1]}")
        continue
    fi

    # Handle VALUE_NOT_1: filename: key
    if [[ "$line" =~ ^VALUE_NOT_1:\ ([^:]+):[[:space:]]*(.*)$ ]]; then
        filename="${BASH_REMATCH[1]}"
        key="${BASH_REMATCH[2]}"
        echo "Fixing non-1 value for $key in $filename"
        # Replace value with 1 in-place
        sed -i -E "s|^(${key//./\\.}[[:space:]]*=[[:space:]]*)[0-9]+|\11|" "$filename"
        continue
    fi

    # Count correct lines
    if [[ "$line" =~ ^/etc/sysctl\.d/.*:net.*=[[:space:]]*1 ]]; then
        ((match_count++)) || true
        echo "$line"
        continue
    fi

    # Any other output lines
    echo "$line"
done < <("$CHECK")

# Check if all keys already correct
if [[ $match_count -eq ${#keys[@]} ]]; then
    echo "Network forwarding properly configured. No changes needed."
    exit 0
fi

# Handle missing keys
if [ "${#keys_missing[@]}" -ne 0 ]; then
    mkdir -p "$(dirname "$OUT")"
    {
        for key in "${keys_missing[@]}"; do
            printf '%s = 1\n' "$key"
        done
    } >> "$OUT"

    chown root:root "$OUT"
    chmod 0644 "$OUT"
    echo "Appended missing keys to $OUT"
fi

# Reload sysctl settings
sysctl --system >/dev/null || true

echo "Network forwarding configuration completed."
