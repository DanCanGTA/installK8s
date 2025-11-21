#!/usr/bin/env bash
set -euo pipefail

# Ports to check
PORTS=(6443 10250)

# Check firewalld installed
if ! command -v firewall-cmd >/dev/null 2>&1; then
    echo "ERROR: firewalld is not installed." >&2
    exit 1
fi

# Check firewalld active
if ! systemctl is-active --quiet firewalld; then
    echo "ERROR: firewalld service is not running." >&2
    exit 1
fi

# Determine zone
ZONE=$(firewall-cmd --get-active-zones | awk 'NR==1{print $1}')

OUTPUT_FOR_CHANGE=false
if [[ "${1-}" == "--outputForChange" ]]; then
    OUTPUT_FOR_CHANGE=true
fi

for port in "${PORTS[@]}"; do
    if firewall-cmd --zone="$ZONE" --query-port="${port}/tcp" >/dev/null 2>&1; then
        if ! $OUTPUT_FOR_CHANGE; then
            echo "[Opened] ${port}/tcp"
        fi
    else
        echo "[Not Opened] ${port}/tcp"
    fi
done
