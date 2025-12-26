#!/usr/bin/env bash
set -euo pipefail

# Run all "0#" check scripts and present their human-readable output.
# This script is intended for a human to read the system status.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# send stdout/stderr to both screen and files
exec > >(tee "${SCRIPT_NAME}.log") 2> >(tee "${SCRIPT_NAME}.err" >&2)

echo "${SCRIPT_NAME} started at: $(date -u '+%Y-%m-%d %H:%M:%SZ')"

checks=(
    "01_os_packages_check.sh"
    "02_swap_disable_check.sh"
    "03_activate_modules_check.sh"
    "04_network_forwarding_check.sh"
    "05_SELinux_check.sh"
    "06_firewall_port_check.sh"
)

overall_status=0

for chk in "${checks[@]}"; do
    echo
    echo "==== Running check: $chk ===="
    path="$SCRIPT_DIR/$chk"
    if [ ! -x "$path" ]; then
        echo "MISSING: check script not found or not executable: $path" >&2
        overall_status=1
        continue
    fi

    # Run the check script capturing both stdout/stderr, but do not let a
    # failing check stop the rest of the checks. We'll record status and continue.
    if output="$($path 2>&1)"; then
        printf '%s\n' "$output"
    else
        rc=$?
        printf '%s\n' "$output"
        echo "-> $chk exited with status $rc" >&2
        overall_status=1
    fi
done

echo
if [ "$overall_status" -ne 0 ]; then
    echo "One or more checks reported problems." >&2
    exit 1
fi

echo "All checks appear OK."
exit 0
