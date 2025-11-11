#!/usr/bin/env bash
set -euo pipefail

# /root/installK8s/4_network_forwarding.sh
# Invoke 04_network_forwarding_check.sh; if it fails, extract the "keys"
# variable from that script and write its lines to /etc/sysctl.d/kubernetes.conf

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
CHECK="$SCRIPT_DIR/04_network_forwarding_check.sh"
OUT="/etc/sysctl.d/kubernetes.conf"
TMPFRAG="$(mktemp)"

if [ ! -f "$CHECK" ]; then
    echo "Check script not found: $CHECK" >&2
    exit 2
fi

# Source the check script so it can populate a 'keys' variable in this shell.
# Use an if so a non-zero exit from the sourced script doesn't trigger 'set -e' to exit us.
if . "$CHECK"; then
    echo "Network forwarding was properly configured. No changes needed."
    exit 0
fi
RC=$?
if [ $RC -ne 1 ]; then
    echo "Network forwarding was not properly configured."
fi

# Write lines to /etc/sysctl.d/kubernetes.conf
mkdir -p "$(dirname "$OUT")"
{
    printf '%s = 1\n' "${keys[@]}"
} > "$OUT"

chown root:root "$OUT"
chmod 0644 "$OUT"

echo "Network forwarding configured successfully in $OUT"

# Inform kernel to reload sysctl settings
sysctl --system >/dev/null || true

exit 0