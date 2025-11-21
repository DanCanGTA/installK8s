#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
CHECK_SCRIPT="${SCRIPT_DIR}/06_firewall_port_check.sh"

# Determine active zone
ZONE=$(firewall-cmd --get-active-zones | awk 'NR==1{print $1}')

# Run check script, capture output
OUTPUT=""
if ! OUTPUT=$("$CHECK_SCRIPT" --outputForChange); then
    # Check script already printed error to stderr
    exit 1
fi

# Parse ports needing changes
# Expected lines:   [Not Opened] 6443/tcp
NOT_OPENED_PORTS=$(echo "$OUTPUT" | awk '/^\[Not Opened\]/{print $3}')

log() { echo "[INFO] $*"; }
warn() { echo "[WARNING] $*" >&2; }
err() { echo "[ERROR] $*" >&2; }
fatal() { err "$*"; exit 1; }

if [[ -z "$NOT_OPENED_PORTS" ]]; then
    log "All required firewall ports are already opened in zone '$ZONE'."
    exit 0
fi


# Open missing ports
for port in $NOT_OPENED_PORTS; do
    log "Opening firewall port $port in zone '$ZONE'..."4
    firewall-cmd --zone="$ZONE" --add-port="$port" --permanent
    firewall-cmd --zone="$ZONE" --add-port="$port"
done
